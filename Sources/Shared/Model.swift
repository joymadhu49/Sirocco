// The contract between Fanline.app (writes config, reads status) and fanlined (the reverse).
import Foundation

enum Paths {
    /// Root owned. fanlined writes status.json here, so nothing user writable sits next to it.
    static let supportDir = URL(fileURLWithPath: "/Library/Application Support/Fanline")
    /// Owned by the user at install time, so the app can save settings without root.
    static let userDir = supportDir.appendingPathComponent("user")
    static let config = userDir.appendingPathComponent("config.json")
    static let status = supportDir.appendingPathComponent("status.json")

    static let daemonLabel = "com.joymadhu.fanlined"
    static let daemonPlist = URL(fileURLWithPath: "/Library/LaunchDaemons/com.joymadhu.fanlined.plist")
    static let daemonBinary = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.joymadhu.fanlined")
}

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

    // Every field is optional on disk so an older or hand edited file still loads.
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

    /// Clamped to the hardware and to sane ranges. fanlined runs as root and reads a user
    /// writable file, so nothing in it is trusted as is.
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

    static func load() -> FanConfig {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: Paths.config.path),
              let size = attributes[.size] as? Int, size < 64 * 1024,
              let data = try? Data(contentsOf: Paths.config),
              let config = try? JSONDecoder().decode(FanConfig.self, from: data)
        else { return FanConfig() }
        return config
    }
}

enum FanState: String, Codable {
    case boosting
    case max
    case waitingForCharger
    case idle
    case off
    case safety

    var label: String {
        switch self {
        case .boosting: "Boosting"
        case .max: "Maximum"
        case .waitingForCharger: "On battery"
        case .idle: "You're away"
        case .off: "Apple control"
        case .safety: "Too hot, full speed"
        }
    }

    var isBoosting: Bool { self == .boosting || self == .max || self == .safety }
}

struct FanStatus: Codable {
    var updated: Date
    var state: FanState
    var targetRPM: Double
    var chipTemp: Double
    var onAC: Bool
    var idleSeconds: Double
    var fans: [SMC.Fan]

    static func load() -> FanStatus? {
        guard let data = try? Data(contentsOf: Paths.status) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(FanStatus.self, from: data)
    }
}
