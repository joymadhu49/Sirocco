import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var config: FanConfig {
        didSet { if config != oldValue { scheduleSave() } }
    }
    @Published private(set) var status: FanStatus?
    @Published private(set) var helperRunning = false
    @Published private(set) var helperInstalled = false
    @Published private(set) var fans: [SMC.Fan] = []
    @Published private(set) var chipTemp: Double?
    @Published private(set) var onAC = false
    @Published private(set) var battery: (percent: Int, charging: Bool)?
    @Published private(set) var saveFailed = false
    @Published private(set) var installing = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private(set) var hardwareMin: Double = 2300
    private(set) var hardwareMax: Double = 7800

    private let smc = SMC()
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?

    init() {
        config = FanConfig.load()
        // A menu bar app that vanishes after a restart is no use; opt in once, the toggle undoes it.
        if !UserDefaults.standard.bool(forKey: "didSetLoginDefault") {
            UserDefaults.standard.set(true, forKey: "didSetLoginDefault")
            try? SMAppService.mainApp.register()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        if let fans = smc?.fans(), !fans.isEmpty {
            hardwareMin = (fans.map(\.min).max() ?? hardwareMin).rounded()
            hardwareMax = (fans.map(\.max).min() ?? hardwareMax).rounded()
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var state: FanState? { helperRunning ? status?.state : nil }
    var isBoosting: Bool { state?.isBoosting ?? false }
    var menuBarSymbol: String { isBoosting ? "fan.fill" : "fan" }

    /// What the curve asks for right now, shown under the sliders.
    var curvePreview: Double? {
        guard let t = chipTemp else { return nil }
        return config.sanitized(hardwareMin: hardwareMin, hardwareMax: hardwareMax).curveRPM(at: t)
    }

    func refresh() {
        helperInstalled = FileManager.default.fileExists(atPath: Paths.daemonPlist.path)
        if let s = FanStatus.load(), Date().timeIntervalSince(s.updated) < 8 {
            status = s
            helperRunning = true
            fans = s.fans
            chipTemp = s.chipTemp
            onAC = s.onAC
        } else {
            // No helper: still show live readings. Reading the SMC needs no privileges.
            status = nil
            helperRunning = false
            fans = smc?.fans() ?? []
            chipTemp = Sensors.chipTemperature()
            onAC = Sensors.onACPower()
        }
        battery = Sensors.battery()
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

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(config).write(to: Paths.config, options: .atomic)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    func toggleLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Helper

    /// Runs a bundled script as root through the standard admin password prompt.
    func runHelperScript(_ name: String) {
        guard let script = Bundle.main.path(forResource: name, ofType: "sh") else { return }
        let appPath = Bundle.main.bundlePath
        let user = NSUserName()
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = "/bin/bash \(quoted(script)) \(quoted(appPath)) \(quoted(user))"
        let source = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        installing = true
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            try? process.run()
            process.waitUntilExit()
            // The model lives as long as the app, so the strong capture is fine.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.installing = false
                if name == "install-helper" { self.save() }
                self.refresh()
            }
        }
    }
}
