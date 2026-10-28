import Foundation

@objc protocol ProbeInterface { func status(reply: @escaping (Data) -> Void) }
@main struct UnauthorizedClient {
    static func main() {
        let connection = NSXPCConnection(machServiceName: "vn.huytran.MacFan.Helper", options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ProbeInterface.self)
        connection.resume()
        defer { connection.invalidate() }
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var accepted = false
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() } as! ProbeInterface
        proxy.status { _ in lock.lock(); accepted = true; lock.unlock(); semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 8) == .success else { fputs("FAIL unauthorized probe timed out; inconclusive\n", stderr); exit(1) }
        lock.lock(); defer { lock.unlock() }
        guard !accepted else { fputs("FAIL helper accepted an unauthorized binary\n", stderr); exit(1) }
        print("PASS helper refused a client with a different code signature (requires positive live service test too).")
    }
}
