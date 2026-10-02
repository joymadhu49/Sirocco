// fanlined: the root helper behind Fanline.app.
//
// Every two seconds it reads the settings the app saved, decides whether the fans should be
// boosted, and either drives them on the temperature curve or leaves them to macOS. It only
// ever holds the fans while a boost is wanted; the rest of the time macOS is in charge.
import Foundation

guard getuid() == 0 else {
    FileHandle.standardError.write("fanlined must run as root (it is started by launchd)\n".data(using: .utf8)!)
    exit(1)
}
guard let smc = SMC() else {
    FileHandle.standardError.write("fanlined: cannot open AppleSMC\n".data(using: .utf8)!)
    exit(1)
}

let tick: TimeInterval = 2
/// Above this the fans go to the hardware maximum whatever the settings say, while held.
let safetyTemp: Double = 95
/// How fast a boost winds down per tick. Rising is immediate; falling slowly stops the fans
/// hunting up and down as the temperature wobbles around a point on the curve.
let maxDropPerTick: Double = 200

var holding = false
var lastTarget: Double = 0
var lastState: FanState?

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) \(message)\n".data(using: .utf8)!)
}

func release(_ reason: String) {
    smc.releaseToSystem()
    holding = false
    lastTarget = 0
    log("released fans to macOS (\(reason))")
}

func writeStatus(_ status: FanStatus) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    guard let data = try? encoder.encode(status) else { return }
    // Atomic write goes through a temp file in the same root owned directory.
    try? data.write(to: Paths.status, options: .atomic)
}

func step() {
    let fans = smc.fans()
    let hardwareMin = fans.map(\.min).max() ?? 0
    let hardwareMax = fans.map(\.max).min() ?? 0
    let config = FanConfig.load().sanitized(hardwareMin: hardwareMin, hardwareMax: hardwareMax)
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
        if temperature >= safetyTemp {
            target = hardwareMax
            state = .safety
        } else if holding, target < lastTarget {
            target = max(target, lastTarget - maxDropPerTick)
        }
        target = target.rounded()
        // macOS takes the fans back after sleep, so check the mode, not only our own flag.
        let systemTookOver = fans.contains { !$0.manual }
        if !holding || systemTookOver || abs(target - lastTarget) >= 50 {
            if smc.setManual(rpm: target) {
                if !holding || systemTookOver { log("holding fans at \(Int(target)) rpm (\(state.rawValue))") }
                holding = true
                lastTarget = target
            } else {
                log("SMC refused manual mode")
            }
        }
    } else if holding || fans.contains(where: \.manual) {
        release(state.rawValue)
    }

    if state != lastState {
        log("state \(state.rawValue), \(Int(temperature)) C, \(onAC ? "AC" : "battery"), idle \(Int(idle)) s")
        lastState = state
    }

    writeStatus(FanStatus(updated: Date(), state: state, targetRPM: holding ? lastTarget : 0,
                          chipTemp: temperature, onAC: onAC, idleSeconds: idle, fans: smc.fans()))
}

// Never leave the fans pinned when launchd stops us (unload, uninstall, shutdown).
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        release("stopping")
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

log("fanlined started")
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: tick)
timer.setEventHandler { step() }
timer.resume()
dispatchMain()
