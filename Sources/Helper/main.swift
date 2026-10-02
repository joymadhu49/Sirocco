// SiroccoHelper: the root daemon behind Sirocco.app.
//
// Registered by the app through SMAppService and started by launchd from inside the app
// bundle. Every two seconds it decides whether the fans should be boosted and either drives
// them on the temperature curve or leaves them to macOS. It only ever holds the fans while a
// boost is wanted. The app talks to it over XPC; nothing else is accepted.
import Foundation

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}

guard getuid() == 0 else {
    log("SiroccoHelper must be started by launchd as root")
    exit(1)
}
guard let smc = SMC() else {
    log("cannot open AppleSMC")
    exit(1)
}

final class FanController {
    static let tick: TimeInterval = 2
    /// Above this the fans go to the hardware maximum whatever the settings say, while held.
    static let safetyTemp: Double = 95
    /// How fast a boost winds down per tick. Rising is immediate; falling slowly stops the fans
    /// hunting up and down as the temperature wobbles around a point on the curve.
    static let maxDropPerTick: Double = 200

    private static let configURL = URL(fileURLWithPath: "/Library/Application Support/Sirocco/config.json")

    private let smc: SMC
    private let version: String
    private(set) var config: FanConfig
    private var holding = false
    private var lastTarget: Double = 0
    private var lastState: FanState?
    private(set) var status: FanStatus

    init(smc: SMC) {
        self.smc = smc
        // The helper lives in Sirocco.app/Contents/MacOS, so Bundle.main is the app bundle.
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        config = FanController.loadConfig()
        status = FanStatus(helperVersion: version, state: .off, config: config, targetRPM: 0,
                           chipTemp: 0, onAC: false, idleSeconds: 0, fans: [])
    }

    // MARK: Config

    private static func loadConfig() -> FanConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(FanConfig.self, from: data)
        else { return FanConfig() }
        return config
    }

    func apply(_ newConfig: FanConfig) {
        let fans = smc.fans()
        config = newConfig.sanitized(hardwareMin: fans.map(\.min).max() ?? 0,
                                     hardwareMax: fans.map(\.max).min() ?? 0)
        do {
            try FileManager.default.createDirectory(at: FanController.configURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: FanController.configURL, options: .atomic)
        } catch {
            log("could not save config: \(error.localizedDescription)")
        }
        step()
    }

    // MARK: Control loop

    func step() {
        let fans = smc.fans()
        guard !fans.isEmpty else {
            publish(.noFans, temperature: Sensors.chipTemperature() ?? 0, onAC: Sensors.onACPower(),
                    idle: Sensors.idleSeconds(), fans: [])
            return
        }
        let hardwareMin = fans.map(\.min).max() ?? 0
        let hardwareMax = fans.map(\.max).min() ?? 0
        let config = self.config.sanitized(hardwareMin: hardwareMin, hardwareMax: hardwareMax)
        let temperature = Sensors.chipTemperature() ?? 0
        let onAC = Sensors.onACPower()
        let idle = Sensors.idleSeconds()

        var want: Double?
        var state: FanState
        switch config.mode {
        case .off:
            state = .off
        case .max:
            state = .max
            want = config.maxRPM
        case .smart:
            if config.requireCharging && !onAC {
                state = .waitingForCharger
            } else if config.requireActive && idle > config.idleMinutes * 60 {
                state = .idle
            } else {
                state = .boosting
                want = config.curveRPM(at: temperature)
            }
        }

        if var target = want {
            if temperature >= FanController.safetyTemp {
                target = hardwareMax
                state = .safety
            } else if holding, target < lastTarget {
                target = max(target, lastTarget - FanController.maxDropPerTick)
            }
            target = target.rounded()
            // macOS takes the fans back after sleep, so check the mode, not only our own flag.
            let systemTookOver = fans.contains { !$0.manual }
            if !holding || systemTookOver || abs(target - lastTarget) >= 50 {
                if smc.setManual(rpm: target) {
                    if !holding { log("holding fans at \(Int(target)) rpm (\(state.rawValue))") }
                    holding = true
                    lastTarget = target
                } else {
                    state = .smcRefused
                    holding = false
                    log("SMC refused manual fan mode")
                }
            }
        } else if holding || fans.contains(where: \.manual) {
            release(state.rawValue)
        }

        publish(state, temperature: temperature, onAC: onAC, idle: idle, fans: smc.fans())
    }

    func release(_ reason: String) {
        smc.releaseToSystem()
        holding = false
        lastTarget = 0
        log("released fans to macOS (\(reason))")
    }

    private func publish(_ state: FanState, temperature: Double, onAC: Bool, idle: Double, fans: [SMC.Fan]) {
        if state != lastState {
            log("state \(state.rawValue), \(Int(temperature)) C, \(onAC ? "AC" : "battery"), idle \(Int(idle)) s")
            lastState = state
        }
        status = FanStatus(helperVersion: version, state: state, config: config,
                           targetRPM: holding ? lastTarget : 0, chipTemp: temperature,
                           onAC: onAC, idleSeconds: idle, fans: fans)
    }
}

// MARK: XPC

/// Every call hops to the main queue, where the control loop runs, so FanController is only
/// ever touched from one thread.
final class HelperService: NSObject, SiroccoHelperProtocol {
    private let controller: FanController

    init(controller: FanController) { self.controller = controller }

    func fetchStatus(withReply reply: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            reply(try? JSONEncoder().encode(self.controller.status))
        }
    }

    func applyConfig(_ data: Data, withReply reply: @escaping (Bool) -> Void) {
        guard data.count < 64 * 1024, let config = try? JSONDecoder().decode(FanConfig.self, from: data) else {
            reply(false)
            return
        }
        DispatchQueue.main.async {
            self.controller.apply(config)
            reply(true)
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperService

    init(service: HelperService) { self.service = service }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SiroccoHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

// MARK: Startup

let controller = FanController(smc: smc)
let listener = NSXPCListener(machServiceName: Identity.helperLabel)
// Only a Sirocco.app signed by our team gets a connection; the check happens in the kernel
// handshake, before shouldAcceptNewConnection is ever called.
listener.setConnectionCodeSigningRequirement(Identity.appRequirement)
let listenerDelegate = ListenerDelegate(service: HelperService(controller: controller))
listener.delegate = listenerDelegate
listener.resume()

// Never leave the fans pinned when launchd stops us (unregister, app deleted, shutdown).
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signalSources = [SIGTERM, SIGINT].map { sig -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        controller.release("stopping")
        exit(0)
    }
    source.resume()
    return source
}

/// An update replaces the whole app bundle, this binary included, but the old process keeps
/// running. When the file on disk is no longer the one we started from, hand the fans back
/// and exit; launchd's KeepAlive starts the new binary in its place.
let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
func fileIdentity(_ path: String) -> (UInt64, Int)? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return (UInt64(info.st_ino), info.st_mtimespec.tv_sec)
}
let startedFrom = fileIdentity(executablePath)
var ticks = 0

log("SiroccoHelper \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") started")
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: FanController.tick)
timer.setEventHandler {
    ticks += 1
    if ticks % 5 == 0, let then = startedFrom {
        let now = fileIdentity(executablePath)
        // Missing means the app was deleted: release and stop rather than run orphaned.
        if now == nil || now! != then {
            controller.release(now == nil ? "app was removed" : "binary replaced by an update")
            exit(0)
        }
    }
    controller.step()
}
timer.resume()
withExtendedLifetime((listener, listenerDelegate, signalSources)) { dispatchMain() }
