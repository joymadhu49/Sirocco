import Foundation
import ServiceManagement

/// Registration of the helper with launchd (SMAppService) and the XPC link to it.
///
/// The helper's launchd plist ships inside the app at Contents/Library/LaunchDaemons. The
/// first register() puts Sirocco under System Settings > General > Login Items, where the
/// user allows it once; launchd then starts the helper and keeps it running.
@MainActor
final class HelperConnection {
    private let service = SMAppService.daemon(plistName: Identity.helperPlistName)
    private var connection: NSXPCConnection?

    var registration: SMAppService.Status { service.status }

    func register() throws { try service.register() }

    func unregister() async throws { try await service.unregister() }

    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// Drops the current connection so the next call dials the helper again.
    func reset() {
        connection?.invalidate()
        connection = nil
    }

    func fetchStatus() async -> FanStatus? {
        guard let data: Data = await call({ proxy, reply in proxy.fetchStatus { reply($0) } }) ?? nil else { return nil }
        return try? JSONDecoder().decode(FanStatus.self, from: data)
    }

    func apply(_ config: FanConfig) async -> Bool {
        guard let data = try? JSONEncoder().encode(config) else { return false }
        return await call({ proxy, reply in proxy.applyConfig(data) { reply($0) } }) ?? false
    }

    // MARK: Plumbing

    private func makeConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: Identity.helperLabel, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: SiroccoHelperProtocol.self)
        // Talk only to our own helper, never to whatever registered the name first.
        c.setCodeSigningRequirement(Identity.helperRequirement)
        let drop: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.connection = nil } }
        c.invalidationHandler = drop
        c.interruptionHandler = drop
        c.resume()
        return c
    }

    /// One request, one answer: resolves with the reply, or nil if the connection fails or the
    /// helper does not answer within two seconds.
    private func call<T>(_ body: @escaping (SiroccoHelperProtocol, @escaping (T) -> Void) -> Void) async -> T? {
        let connection = self.connection ?? makeConnection()
        self.connection = connection
        return await withCheckedContinuation { continuation in
            let once = Once()
            let finish: (T?) -> Void = { value in if once.claim() { continuation.resume(returning: value) } }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in finish(nil) }) as? SiroccoHelperProtocol else {
                finish(nil)
                return
            }
            body(proxy) { finish($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { finish(nil) }
        }
    }
}

/// Lets exactly one of several racing callbacks resume a continuation.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
