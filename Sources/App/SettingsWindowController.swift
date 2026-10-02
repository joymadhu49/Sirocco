import AppKit
import SwiftUI

/// Owns the settings window, which is what opening Sirocco from Finder, Spotlight or Launchpad
/// shows. The menu bar panel stays the quick view; this is the full one.
///
/// While the window is open the app is a regular one (Dock icon, Cmd-Tab, a menu bar), so the
/// window cannot get lost behind others. Closing it turns Sirocco back into a menu bar extra.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        PanelController.shared.hide()
        let window = window ?? makeWindow()
        self.window = window
        Task { await AppModel.shared.refresh() }

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "Sirocco Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsRoot())
        window.setContentSize(NSSize(width: 720, height: 520))
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.center()
        window.setFrameAutosaveName("SiroccoSettings")
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The menu bar shown while the settings window is open, and the source of the usual shortcuts
/// (Cmd-W, Cmd-Q, Cmd-comma) at all times.
@MainActor
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Sirocco", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
        settings.target = NSApp.delegate
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Sirocco", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Sirocco", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "Sirocco"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(windowMenu, title: "Window"))

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
