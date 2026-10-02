import Foundation
import ServiceManagement
import SwiftUI

/// Where the helper stands, which decides what the panel offers.
enum HelperPhase: Equatable {
    /// This Mac has no fans (MacBook Air), so there is nothing to control.
    case unsupported
    case notInstalled
    case needsApproval
    case starting
    case notResponding
    case ready
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var config = FanConfig() {
        didSet {
            guard config != oldValue, !adoptingRemote else { return }
            hasLocalEdits = true
            schedulePush()
        }
    }
    @Published private(set) var phase: HelperPhase = .starting
    @Published private(set) var status: FanStatus?
    @Published private(set) var fans: [SMC.Fan] = []
    @Published private(set) var chipTemp: Double?
    @Published private(set) var onAC = false
    @Published private(set) var battery: (percent: Int, charging: Bool)?
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private(set) var hardwareMin: Double = 2300
    private(set) var hardwareMax: Double = 7800
    private(set) var fanCount = 0

    private let helper = HelperConnection()
    private let smc = SMC()
    private var timer: Timer?
    private var pushWork: DispatchWorkItem?
    private var adoptingRemote = false
    private var hasLocalEdits = false
    private var syncedWithHelper = false
    private var lastContact = Date.distantPast
    private var enabledSince: Date?
    private var autoRestarts = 0
    private var lastAutoRestart = Date.distantPast

    /// Set when the user removes the helper themselves, so Sirocco does not put it straight back.
    private var helperRemovedByUser: Bool {
        get { UserDefaults.standard.bool(forKey: "helperRemovedByUser") }
        set { UserDefaults.standard.set(newValue, forKey: "helperRemovedByUser") }
    }

    private init() {
        if let smc {
            fanCount = smc.fanCount
            let fans = smc.fans()
            if !fans.isEmpty {
                hardwareMin = (fans.map(\.min).max() ?? hardwareMin).rounded()
                hardwareMax = (fans.map(\.max).min() ?? hardwareMax).rounded()
            }
        }
        if let data = UserDefaults.standard.data(forKey: "lastConfig"),
           let saved = try? JSONDecoder().decode(FanConfig.self, from: data) {
            adoptingRemote = true
            config = saved
            adoptingRemote = false
        }
    }

    func start() {
        guard timer == nil else { return }
        registerHelperIfNeeded()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 0.3
    }

    // MARK: Derived

    var state: FanState? { phase == .ready ? status?.state : nil }
    var isBoosting: Bool { state?.isBoosting ?? false }
    var controlsEnabled: Bool { phase == .ready }

    var averageRPM: Double {
        guard !fans.isEmpty else { return 0 }
        return fans.map(\.actual).reduce(0, +) / Double(fans.count)
    }

    /// What the curve asks for at the current temperature, shown under the sliders.
    var curvePreview: Double? {
        guard let t = chipTemp else { return nil }
        return config.sanitized(hardwareMin: hardwareMin, hardwareMax: hardwareMax).curveRPM(at: t)
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: Refresh

    func refresh() async {
        if fanCount == 0 {
            phase = .unsupported
            readLocally()
            return
        }

        let registration = helper.registration
        var fresh: FanStatus?
        if registration == .enabled {
            if enabledSince == nil { enabledSince = Date() }
            fresh = await helper.fetchStatus()
        } else {
            enabledSince = nil
        }

        if let fresh {
            lastContact = Date()
            status = fresh
            fans = fresh.fans
            chipTemp = fresh.chipTemp
            onAC = fresh.onAC
            syncConfig(from: fresh.config)
        } else {
            status = nil
            readLocally()
        }
        battery = Sensors.battery()

        switch registration {
        case .notRegistered, .notFound:
            phase = .notInstalled
        case .requiresApproval:
            phase = .needsApproval
        case .enabled:
            if Date().timeIntervalSince(lastContact) < 6 {
                phase = .ready
            } else if let since = enabledSince, Date().timeIntervalSince(since) < 10 {
                phase = .starting
            } else {
                phase = .notResponding
            }
        @unknown default:
            phase = .notInstalled
        }
        if phase == .ready { autoRestarts = 0 }
        recoverHelperIfNeeded()
    }

    // MARK: Looking after the helper
    //
    // The helper is plumbing, and the user should not have to manage it. Sirocco registers it
    // on launch and restarts it when it stops answering; the one thing only the user can do is
    // allow it in System Settings, once.

    /// Registers the helper without being asked. Quiet: it does not open System Settings, the
    /// setup card offers that.
    private func registerHelperIfNeeded() {
        guard fanCount > 0, !helperRemovedByUser else { return }
        let registration = helper.registration
        guard registration == .notRegistered || registration == .notFound else { return }
        try? helper.register()
    }

    /// A helper that is registered but silent gets restarted, a few times at most and a minute
    /// apart, before the setup card asks the user to step in.
    private func recoverHelperIfNeeded() {
        guard phase == .notResponding, !busy, autoRestarts < 3,
              Date().timeIntervalSince(lastAutoRestart) > 60 else { return }
        autoRestarts += 1
        lastAutoRestart = Date()
        restartHelper()
    }

    /// No helper to ask: the SMC and sensors are readable without privileges.
    private func readLocally() {
        fans = smc?.fans() ?? []
        chipTemp = Sensors.chipTemperature()
        onAC = Sensors.onACPower()
        battery = Sensors.battery()
    }

    /// The helper's saved config wins on first contact, unless the user changed something here
    /// while it was unreachable, in which case that change is sent instead.
    private func syncConfig(from remote: FanConfig) {
        if !syncedWithHelper {
            syncedWithHelper = true
            if hasLocalEdits { schedulePush(); return }
        }
        guard !hasLocalEdits, remote != config else { return }
        adoptingRemote = true
        config = remote
        adoptingRemote = false
        remember(remote)
    }

    // MARK: Settings

    func setMin(_ value: Double) {
        config.minRPM = value
        if config.maxRPM < value { config.maxRPM = value }
    }

    func setMax(_ value: Double) {
        config.maxRPM = value
        if config.minRPM > value { config.minRPM = value }
    }

    func setStartTemp(_ value: Double) {
        config.startTemp = value
        if config.fullTemp < value + 5 { config.fullTemp = value + 5 }
    }

    func setFullTemp(_ value: Double) {
        config.fullTemp = value
        if config.startTemp > value - 5 { config.startTemp = value - 5 }
    }

    func apply(_ preset: FanPreset) {
        config = preset.apply(to: config, hardwareMin: hardwareMin, hardwareMax: hardwareMax)
    }

    func resetToDefaults() {
        config = FanConfig().sanitized(hardwareMin: hardwareMin, hardwareMax: hardwareMax)
    }

    private func schedulePush() {
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.push() }
        }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func push() async {
        let sent = config
        remember(sent)
        guard phase == .ready || phase == .starting else { return }
        if await helper.apply(sent), sent == config {
            hasLocalEdits = false
        }
    }

    private func remember(_ config: FanConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "lastConfig")
        }
    }

    // MARK: Helper lifecycle

    func enableHelper() {
        lastError = nil
        helperRemovedByUser = false
        do {
            try helper.register()
        } catch {
            // Registering a daemon throws "Operation not permitted" when it still needs the
            // user's approval, which is the normal first-run path, not a failure.
            if helper.registration != .requiresApproval {
                lastError = error.localizedDescription
            }
        }
        if helper.registration == .requiresApproval { helper.openApprovalSettings() }
        Task { await refresh() }
    }

    func openApprovalSettings() { helper.openApprovalSettings() }

    func restartHelper() {
        busy = true
        lastError = nil
        Task {
            try? await helper.unregister()
            helper.reset()
            do { try helper.register() } catch {
                if helper.registration != .requiresApproval { lastError = error.localizedDescription }
            }
            enabledSince = nil
            syncedWithHelper = false
            busy = false
            await refresh()
        }
    }

    /// Unregistering stops the helper; it hands the fans back to macOS on the way out.
    func removeHelper() {
        busy = true
        helperRemovedByUser = true
        Task {
            try? await helper.unregister()
            helper.reset()
            syncedWithHelper = false
            busy = false
            await refresh()
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Opt in to opening at login once, on first launch. The toggle undoes it.
    func applyFirstLaunchDefaults() {
        guard !UserDefaults.standard.bool(forKey: "didSetLoginDefault") else { return }
        UserDefaults.standard.set(true, forKey: "didSetLoginDefault")
        try? SMAppService.mainApp.register()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
