import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.applyFirstLaunchDefaults()
        AppModel.shared.start()
        StatusItemController.shared.install()
        UpdateController.shared.start()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the panel, since there is no
    /// window or Dock icon to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.statusItemFrame = StatusItemController.shared.buttonFrame
        PanelController.shared.show()
        return false
    }
}
