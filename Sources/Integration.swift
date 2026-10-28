import Foundation
import Security

// Explicit diagnostic command, never run on an ordinary app launch.
// Exercises the signed UI binary → authenticated XPC → root helper → SMC path.
func runIntegrationTests() throws {
    func connect() throws -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: helperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanServiceProtocol.self)
        var parsedRequirement: SecRequirement?
        guard let path = Bundle.main.path(forResource: "helper-requirement", ofType: "txt"), let requirement = try? String(contentsOfFile: path, encoding: .utf8),
              SecRequirementCreateWithString(requirement.trimmingCharacters(in: .whitespacesAndNewlines) as CFString, [], &parsedRequirement) == errSecSuccess else { throw FanError("Chữ ký helper sai định dạng.") }
        connection.setCodeSigningRequirement(requirement.trimmingCharacters(in: .whitespacesAndNewlines))
        connection.resume()
        return connection
    }
    func request(_ connection: NSXPCConnection, _ action: (FanServiceProtocol, @escaping (Data) -> Void) -> Void) throws -> ServiceResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var received: Data?
        var failure: Error?
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in lock.lock(); failure = error; lock.unlock(); semaphore.signal() }) as? FanServiceProtocol else { throw FanError("Không có XPC proxy.") }
        action(proxy) { data in lock.lock(); received = data; lock.unlock(); semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 10) == .success else { throw FanError("XPC timeout.") }
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        guard let received else { throw FanError("XPC thiếu phản hồi.") }
        return try JSONDecoder().decode(ServiceResponse.self, from: received)
    }
    func status(_ connection: NSXPCConnection) throws -> StatusSnapshot {
        let response = try request(connection) { $0.status(reply: $1) }
        guard response.error == nil, let snapshot = response.status, snapshot.error == nil else { throw FanError(response.error ?? response.status?.error ?? "Không có trạng thái.") }
        return snapshot
    }
    func configure(_ connection: NSXPCConnection, _ config: FanConfiguration) throws {
        let data = try JSONEncoder().encode(config)
        let response = try request(connection) { $0.configure(data, reply: $1) }
        if let error = response.error ?? response.status?.error { throw FanError(error) }
    }
    func awaitAutomatic(_ connection: NSXPCConnection) throws -> StatusSnapshot {
        let deadline = Date().addingTimeInterval(5)
        var latest: StatusSnapshot?
        repeat {
            let response = try request(connection) { $0.status(reply: $1) }
            latest = response.status
            if let snapshot = latest, response.error == nil, snapshot.error == nil,
               snapshot.mode == .system, !snapshot.fans.isEmpty,
               snapshot.fans.allSatisfy({ $0.hardwareMode == 0 || $0.hardwareMode == 3 }) { return snapshot }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        throw FanError("Quạt chưa về macOS: mode=\(latest?.mode.rawValue ?? "?"); hardware=\(latest?.fans.map { String($0.hardwareMode) }.joined(separator: ",") ?? "?"); lỗi=\(latest?.error ?? "không có").")
    }
    let connection = try connect()
    defer {
        _ = try? request(connection) { $0.releaseControl(reply: $1) }
        connection.invalidate()
    }
    let baseline = try awaitAutomatic(connection)
    guard let fan = baseline.fans.first, baseline.cpuTemperature != nil, baseline.mode == .system, fan.hardwareMode != 1 else { throw FanError("Kiểm thử cần quạt đang do macOS quản lý.") }
    print("PASS authenticated XPC; CPU \(baseline.cpuTemperature!), fan \(fan.actual) RPM")
    var config = FanConfiguration(); config.mode = .manual; config.manualRPM = max(fan.minimum, min(2000, fan.maximum))
    try configure(connection, config)
    Thread.sleep(forTimeInterval: 5)
    let manual = try status(connection)
    guard manual.mode == .manual, let applied = manual.fans.first, applied.hardwareMode == 1,
          abs((applied.target ?? 0) - config.manualRPM) <= 50, applied.actual > fan.minimum + 100 else { throw FanError("RPM thực chưa đáp ứng chế độ thủ công.") }
    print("PASS manual target \(config.manualRPM), actual \(applied.actual) RPM")
    config.mode = .curve
    try configure(connection, config)
    let curved = try status(connection)
    guard curved.mode == .curve else { throw FanError("Không bật được đường nhiệt.") }
    print("PASS CPU curve mode; target \(curved.fans.first?.target ?? -1) RPM")
    var invalid = config; invalid.points[1].temperature = 20
    let invalidData = try JSONEncoder().encode(invalid)
    let rejected = try request(connection) { $0.configure(invalidData, reply: $1) }
    guard rejected.error != nil else { throw FanError("Helper chấp nhận cấu hình sai.") }
    print("PASS helper rejects invalid curve")
    _ = try request(connection) { $0.releaseControl(reply: $1) }
    let restored = try awaitAutomatic(connection)
    guard restored.mode == .system, restored.fans.allSatisfy({ $0.hardwareMode == 0 || $0.hardwareMode == 3 }) else { throw FanError("Chưa trả quyền về macOS.") }
    print("PASS explicit release to macOS")
    try configure(connection, config)
    Thread.sleep(forTimeInterval: 15)
    let expired = try awaitAutomatic(connection)
    guard expired.mode == .system, expired.fans.allSatisfy({ $0.hardwareMode != 1 }) else { throw FanError("Watchdog không trả quyền sau timeout.") }
    print("PASS hardware watchdog returns to macOS after missed heartbeat")
    try configure(connection, config)
    connection.invalidate()
    Thread.sleep(forTimeInterval: 2)
    let verification = try connect()
    defer { verification.invalidate() }
    let disconnected = try awaitAutomatic(verification)
    guard disconnected.mode == .system, disconnected.fans.allSatisfy({ $0.hardwareMode != 1 }) else { throw FanError("Mất kết nối chưa trả về macOS.") }
    print("PASS disconnect recovery; final hardware mode \(disconnected.fans.first!.hardwareMode)")
    print("7 live integration checks passed.")
}
