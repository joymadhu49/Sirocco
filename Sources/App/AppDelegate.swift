import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.applyFirstLaunchDefaults()
        AppModel.shared.start()
        StatusItemController.shared.install()
        UpdateController.shared.start()
        MainMenu.install()

        // Someone who opens the app expects to see it, and a menu bar icon alone is easy to
        // miss. Starting quietly is right only when macOS opens Sirocco at login.
        if !Self.launchedAsLoginItem { showSettings() }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc func showSettings() {
        SettingsWindowController.shared.show()
    }

    /// The launch Apple event says whether macOS started the app as a login item.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
