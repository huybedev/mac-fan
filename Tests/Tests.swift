import Foundation

final class FakeHardware: FanHardware {
    var readings = [FanReading(id: 0, actual: 1000, minimum: 1000, maximum: 4900, target: 1000, hardwareMode: 0)]
    var cpu = [SensorReading(key: "Tp01", temperature: 50), SensorReading(key: "Tp05", temperature: 55)]
    var gpu = [SensorReading(key: "Tg0G", temperature: 45)]
    var commands: [(Int, Double)] = []
    var restores: [[Int]] = []
    var failWrite = false
    var failRestore = false
    var failRead = false
    func fans() throws -> [FanReading] { if failRead { throw FanError("read failed") }; return readings }
    func temperatures(_ keys: [String]) -> [SensorReading] { keys == SMC.cpuKeys ? cpu : gpu }
    func setFan(_ fan: FanReading, rpm: Double) throws {
        commands.append((fan.id, rpm))
        if failWrite { throw FanError("write rejected") }
    }
    func restore(_ ids: [Int]) throws {
        restores.append(ids)
        if failRestore { throw FanError("restore rejected") }
    }
}

@main struct Tests {
    static var count = 0
    static func check(_ label: String, _ body: () throws -> Void) rethrows {
        try body(); count += 1; print("PASS \(label)")
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String = "assertion failed", line: UInt = #line) {
        if !condition() { fatalError("\(message) at line \(line)") }
    }
    static func rejected(_ body: () throws -> Void) { do { try body(); fatalError("expected rejection") } catch {} }
    static func main() throws {
        check("languages translate UI, format values, and preserve Vietnamese") {
            require(AppLanguage.vietnamese.text("Áp dụng") == "Áp dụng")
            require(AppLanguage.english.text("Áp dụng") == "Apply")
            require(AppLanguage.chinese.text("Áp dụng") == "应用")
            require(AppLanguage.english.format("MỐC %d", 2) == "POINT 2")
            require(AppLanguage.chinese.format("Quạt %d: %d RPM", 1, 2000) == "风扇 1：2000 RPM")
            require(AppLanguage(rawValue: "zh-Hans") == .chinese)
        }
        check("helper and validation errors translate with dynamic details") {
            let message = "Đang thử trả quyền về macOS: Quạt 1 chưa trở về macOS."
            require(AppLanguage.english.message(message) == "Trying to return control to macOS: Fan 1 has not returned to macOS control.")
            require(AppLanguage.chinese.message("Không đọc được trạng thái quạt 2.") == "无法读取风扇 2 的状态。")
            require(AppLanguage.english.message("SMC F0Md từ chối lệnh (0x82).") == "SMC F0Md rejected the command (0x82).")
            require(AppLanguage.english.message("Nhiệt độ phải tăng dần và mức quạt không được giảm.") == "Temperatures must increase and fan levels must not decrease.")
        }
        let fan = FanReading(id: 0, actual: 1000, minimum: 1000, maximum: 4900, target: 1000, hardwareMode: 0)
        var config = FanConfiguration(); config.mode = .curve
        try check("curve endpoints and linear interpolation") {
            _ = try config.validated()
            require(config.fraction(at: 20) == 0)
            require(abs(config.fraction(at: 62.5) - 0.4) < 0.00001)
            require(config.fraction(at: 100) == 1)
        }
        check("invalid temperatures / descending curve / nonfinite rejected") {
            var invalid = config; invalid.points[1].temperature = 39; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points[1].percent = -1; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points[2].percent = 1; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points[3].percent = 99; rejected { _ = try invalid.validated() }
            invalid = config; invalid.manualRPM = .nan; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points = []; rejected { _ = try invalid.validated() }
        }
        check("RPM clamping at hardware boundaries") {
            var policy = FanPolicy(); var manual = config; manual.mode = .manual; manual.manualRPM = 16000
            require(policy.target(config: manual, fan: fan, cpu: 50, gpu: nil) == 4900)
            policy.reset(); manual.manualRPM = 500
            require(policy.target(config: manual, fan: fan, cpu: 50, gpu: nil) == 1000)
        }
        check("CPU and GPU emergency override manual RPM") {
            var policy = FanPolicy(); var manual = config; manual.mode = .manual; manual.manualRPM = 1000
            require(policy.target(config: manual, fan: fan, cpu: 90, gpu: nil) == 4900)
            require(policy.target(config: manual, fan: fan, cpu: 50, gpu: 95) == 4900)
        }
        check("rising cooling immediate, declining cooling limited") {
            var policy = FanPolicy()
            require(policy.target(config: config, fan: fan, cpu: 40, gpu: nil) == 1000)
            require(policy.target(config: config, fan: fan, cpu: 90, gpu: nil) == 4900)
            require(policy.target(config: config, fan: fan, cpu: 40, gpu: nil) == 4750)
        }
        try check("SMC float / fixed-point codecs and signed temperature") {
            let float = SMCValue(type: "flt ", bytes: [0, 0, 0, 0])
            let encodedFloat = try float.encoding(2375); require(encodedFloat.number == 2375)
            let fixed = SMCValue(type: "fpe2", bytes: [0, 0])
            let encodedFixed = try fixed.encoding(4900); require(encodedFixed.number == 4900)
            require(SMCValue(type: "sp78", bytes: [255, 0]).number == -1)
            require(SMCValue(type: "flt ", bytes: [0]).number == nil)
            rejected { _ = try fixed.encoding(17000) }
        }
        try check("SMC waits for deferred takeover and release transitions") {
            var mode: Double = 0
            var pendingMode: Double = 0
            var target: Double = 1000
            var releasePolls = 0
            let smc = SMC(testTransport: { key, command, size, _, bytes in
                guard key == "F0Md" || key == "F0Tg" else { throw FanError("not found") }
                let type = key == "F0Md" ? "ui8 " : "flt "
                var packet = [UInt8](repeating: 0, count: 80)
                if command == 9 {
                    packet.withUnsafeMutableBytes {
                        $0.storeBytes(of: UInt32(key == "F0Md" ? 1 : 4), toByteOffset: 28, as: UInt32.self)
                        $0.storeBytes(of: type.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }, toByteOffset: 32, as: UInt32.self)
                    }
                } else if command == 6 {
                    require(size == bytes.count)
                    if key == "F0Md" { pendingMode = SMCValue(type: type, bytes: bytes).number! }
                    else { target = SMCValue(type: type, bytes: bytes).number!; if pendingMode != 0 || target != 0 { mode = pendingMode } }
                } else if command == 5 {
                    if key == "F0Md", pendingMode == 0, target == 0 {
                        releasePolls += 1
                        if releasePolls >= 3 { mode = 0 }
                    }
                    let value = try SMCValue(type: type, bytes: Array(repeating: 0, count: key == "F0Md" ? 1 : 4)).encoding(key == "F0Md" ? mode : target)
                    for (index, byte) in value.bytes.enumerated() { packet[48 + index] = byte }
                }
                return packet
            })
            try smc.setFan(fan, rpm: 2000)
            require(mode == 1 && target == 2000)
            try smc.restore([0])
            require(mode == 0 && target == 0 && releasePolls >= 3)
        }
        check("monitoring never writes hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            controller.tick(); _ = controller.status(client: UUID())
            require(hw.commands.isEmpty && hw.restores.isEmpty)
        }
        try check("curve applies to hottest CPU sensor") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID())
            require(hw.commands.last!.1 == 1975)
            require(controller.snapshot.mode == .curve)
        }
        try check("watchdog returns to macOS without heartbeat") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let now = Date()
            try controller.configure(config, client: UUID(), now: now)
            controller.tick(now: now.addingTimeInterval(13))
            require(hw.restores == [[0]] && controller.snapshot.mode == .system)
        }
        try check("owner heartbeat renews lease; other clients do not") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let client = UUID(); let now = Date()
            try controller.configure(config, client: client, now: now)
            _ = controller.status(client: client, now: now.addingTimeInterval(10))
            controller.tick(now: now.addingTimeInterval(15)); require(hw.restores.isEmpty)
            _ = controller.status(client: UUID(), now: now.addingTimeInterval(22))
            controller.tick(now: now.addingTimeInterval(23)); require(hw.restores == [[0]])
        }
        try check("disconnect releases only the owning session") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let client = UUID()
            try controller.configure(config, client: client)
            controller.disconnected(UUID()); require(hw.restores.isEmpty)
            controller.disconnected(client); require(hw.restores == [[0]])
        }
        try check("another client cannot replace active control") {
            let controller = FanController(hardware: FakeHardware())
            try controller.configure(config, client: UUID())
            rejected { try controller.configure(config, client: UUID()) }
        }
        try check("missing any discovered CPU sensor releases hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID()); hw.cpu.removeLast(); controller.tick()
            require(hw.restores == [[0]] && controller.snapshot.error != nil)
        }
        try check("missing GPU sensor releases hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID()); hw.gpu = []; controller.tick()
            require(hw.restores == [[0]] && controller.snapshot.mode == .system)
        }
        try check("fan read failure releases hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID()); hw.failRead = true; controller.tick()
            require(hw.restores == [[0]] && controller.snapshot.error != nil)
        }
        check("firmware write rejection rolls back takeover") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); hw.failWrite = true
            rejected { try controller.configure(config, client: UUID()) }
            require(hw.restores == [[0]] && controller.snapshot.mode == .system)
        }
        try check("failed restore retained and retried") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let client = UUID()
            try controller.configure(config, client: client); hw.failRestore = true
            controller.disconnected(client); require(controller.snapshot.error != nil)
            hw.failRestore = false; controller.tick()
            require(hw.restores == [[0], [0]] && controller.snapshot.error == nil)
        }
        check("external fan controller prevents takeover") {
            let hw = FakeHardware(); hw.readings = [FanReading(id: 0, actual: 1000, minimum: 1000, maximum: 4900, target: 1000, hardwareMode: 1)]
            let controller = FanController(hardware: hw)
            rejected { try controller.configure(config, client: UUID()) }
            require(hw.commands.isEmpty && hw.restores.isEmpty)
        }
        try check("recovery journal persisted before write and removed after release") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            let hw = FakeHardware(); let controller = FanController(hardware: hw, journal: file); let client = UUID()
            try controller.configure(config, client: client)
            require(FileManager.default.fileExists(atPath: file.path))
            controller.disconnected(client)
            require(!FileManager.default.fileExists(atPath: file.path))
        }
        try check("daemon restart restores stale journal without reapplying curve") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            try JSONEncoder().encode([0]).write(to: file)
            let hw = FakeHardware(); let controller = FanController(hardware: hw, journal: file)
            require(hw.restores == [[0]] && hw.commands.isEmpty && controller.snapshot.mode == .system)
        }
        print("\(count) behavioral tests passed.")
    }
}
