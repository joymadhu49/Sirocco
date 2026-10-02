// The data the app and the helper exchange over XPC.
import Foundation

enum FanMode: String, Codable, CaseIterable {
    /// Boost on the curve when the conditions hold, otherwise leave the fans to macOS.
    case smart
    /// Always at the Maximum setting.
    case max
    /// Never touch the fans.
    case off
}

struct FanConfig: Codable, Equatable {
    var mode: FanMode = .smart
    var minRPM: Double = 3500
    var maxRPM: Double = 6500
    var startTemp: Double = 55
    var fullTemp: Double = 80
    var requireCharging = true
    var requireActive = true
    var idleMinutes: Double = 5

    init() {}

    // Every field is optional so a config saved by an older version still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FanConfig()
        mode = (try? c.decodeIfPresent(FanMode.self, forKey: .mode)) ?? d.mode
        minRPM = (try? c.decodeIfPresent(Double.self, forKey: .minRPM)) ?? d.minRPM
        maxRPM = (try? c.decodeIfPresent(Double.self, forKey: .maxRPM)) ?? d.maxRPM
        startTemp = (try? c.decodeIfPresent(Double.self, forKey: .startTemp)) ?? d.startTemp
        fullTemp = (try? c.decodeIfPresent(Double.self, forKey: .fullTemp)) ?? d.fullTemp
        requireCharging = (try? c.decodeIfPresent(Bool.self, forKey: .requireCharging)) ?? d.requireCharging
        requireActive = (try? c.decodeIfPresent(Bool.self, forKey: .requireActive)) ?? d.requireActive
        idleMinutes = (try? c.decodeIfPresent(Double.self, forKey: .idleMinutes)) ?? d.idleMinutes
    }

    /// Clamped to the hardware and to sane ranges. The helper runs as root, so nothing that
    /// arrives over XPC is used as is.
    func sanitized(hardwareMin: Double, hardwareMax: Double) -> FanConfig {
        var c = self
        let lo = hardwareMin > 0 ? hardwareMin : 1000
        let hi = hardwareMax > lo ? hardwareMax : 8000
        c.minRPM = minRPM.isFinite ? Swift.min(Swift.max(minRPM, lo), hi) : lo
        c.maxRPM = maxRPM.isFinite ? Swift.min(Swift.max(maxRPM, c.minRPM), hi) : hi
        c.startTemp = startTemp.isFinite ? Swift.min(Swift.max(startTemp, 30), 90) : 55
        c.fullTemp = fullTemp.isFinite ? Swift.min(Swift.max(fullTemp, c.startTemp + 5), 100) : 80
        c.idleMinutes = idleMinutes.isFinite ? Swift.min(Swift.max(idleMinutes, 1), 60) : 5
        return c
    }

    /// Fan target for a chip temperature: Minimum below startTemp, Maximum from fullTemp,
    /// a straight line between.
    func curveRPM(at temperature: Double) -> Double {
        guard fullTemp > startTemp else { return maxRPM }
        let t = Swift.min(Swift.max((temperature - startTemp) / (fullTemp - startTemp), 0), 1)
        return minRPM + (maxRPM - minRPM) * t
    }
}

/// Ready made settings, scaled to whatever range the Mac's fans have.
enum FanPreset: String, CaseIterable, Identifiable {
    case quiet, balanced, cool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: "Quiet"
        case .balanced: "Balanced"
        case .cool: "Cool"
        }
    }

    func apply(to config: FanConfig, hardwareMin: Double, hardwareMax: Double) -> FanConfig {
        var c = config
        let span = hardwareMax - hardwareMin
        switch self {
        case .quiet:
            c.minRPM = hardwareMin
            c.maxRPM = hardwareMin + span * 0.4
            c.startTemp = 65
            c.fullTemp = 90
        case .balanced:
            c.minRPM = hardwareMin + span * 0.2
            c.maxRPM = hardwareMin + span * 0.75
            c.startTemp = 55
            c.fullTemp = 80
        case .cool:
            c.minRPM = hardwareMin + span * 0.4
            c.maxRPM = hardwareMax
            c.startTemp = 45
            c.fullTemp = 70
        }
        c.minRPM = (c.minRPM / 100).rounded() * 100
        c.maxRPM = (c.maxRPM / 100).rounded() * 100
        return c.sanitized(hardwareMin: hardwareMin, hardwareMax: hardwareMax)
    }
}

enum FanState: String, Codable {
    case boosting
    case max
    case waitingForCharger
    case idle
    case off
    case safety
    case noFans
    case smcRefused

    var label: String {
        switch self {
        case .boosting: "Boosting"
        case .max: "Maximum"
        case .waitingForCharger: "On battery"
        case .idle: "You're away"
        case .off: "Apple control"
        case .safety: "Too hot, full speed"
        case .noFans: "No fans"
        case .smcRefused: "Fans locked"
        }
    }

    var isBoosting: Bool { self == .boosting || self == .max || self == .safety }
}

struct FanStatus: Codable {
    var helperVersion: String
    var state: FanState
    var config: FanConfig
    var targetRPM: Double
    var chipTemp: Double
    var onAC: Bool
    var idleSeconds: Double
    var fans: [SMC.Fan]
}
