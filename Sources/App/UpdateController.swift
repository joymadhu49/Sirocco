import AppKit
import Combine
import Sparkle

/// Owns Sparkle. Updates come from the appcast attached to the newest GitHub release, and every
/// archive is checked against the EdDSA key in Info.plist before it is installed.
///
/// The update check is the only network request Sirocco makes, and system profiling is off.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = false {
        didSet {
            guard started, automaticallyChecks != updater.automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    private var started = false

    private var updater: SPUUpdater { controller.updater }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// Called once at launch. A development build without a feed would only log errors, so the
    /// updater starts for a build that has one.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller.startUpdater()
        started = true
        automaticallyChecks = updater.automaticallyChecksForUpdates
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheckForUpdates = value }
            }
        ]
    }

    func checkForUpdates() {
        // A menu bar app is never frontmost on its own, and Sparkle's window would open behind
        // whatever the user was working in.
        PanelController.shared.hide()
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    /// Sirocco has no Dock icon and is rarely frontmost. Gentle reminders let Sparkle show a
    /// scheduled update without stealing focus, instead of warning that a background app
    /// cannot present one well.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard handleShowingUpdate, state.userInitiated else { return }
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }
}
