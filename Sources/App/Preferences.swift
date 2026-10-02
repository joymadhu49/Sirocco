import Foundation

/// Preferences that only affect this app's display. Fan settings live in the helper.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum MenuBarText: String, CaseIterable, Identifiable {
        case none, temperature, speed, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "Icon only"
            case .temperature: "Chip temperature"
            case .speed: "Fan speed"
            case .both: "Temperature and speed"
            }
        }
    }

    private let defaults = UserDefaults.standard

    @Published var spinIcon: Bool { didSet { defaults.set(spinIcon, forKey: "spinIcon") } }
    @Published var menuBarText: MenuBarText { didSet { defaults.set(menuBarText.rawValue, forKey: "menuBarText") } }
    @Published var fahrenheit: Bool { didSet { defaults.set(fahrenheit, forKey: "fahrenheit") } }

    private init() {
        defaults.register(defaults: ["spinIcon": true, "menuBarText": MenuBarText.none.rawValue, "fahrenheit": false])
        spinIcon = defaults.bool(forKey: "spinIcon")
        menuBarText = MenuBarText(rawValue: defaults.string(forKey: "menuBarText") ?? "") ?? .none
        fahrenheit = defaults.bool(forKey: "fahrenheit")
    }

    /// Celsius in, formatted in the chosen unit out.
    func temperature(_ celsius: Double, unit: Bool = true) -> String {
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°" + (unit ? (fahrenheit ? "F" : "C") : "")
    }

    static func rpm(_ value: Double) -> String { "\(Int(value.rounded()).formatted()) rpm" }

    /// "3.5k" style, for the narrow menu bar.
    static func shortRPM(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value.rounded()))"
    }
}
