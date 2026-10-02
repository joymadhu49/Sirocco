import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that can take key, so its controls respond to the first click.
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting controller that reports back after every layout pass, so the panel stays anchored
/// under the menu bar while its height changes (the setup card comes and goes).
private final class PanelHostingController<Content: View>: NSHostingController<Content> {
    var onLayout: (() -> Void)?

    override func viewDidLayout() {
        super.viewDidLayout()
        onLayout?()
    }
}

/// Owns the panel: placement, show and hide.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private var panel: Panel?
    private var keyMonitor: Any?
    private var isVisible = false
    private var isPositioning = false
    /// When the panel last closed because it lost key. Clicking the menu bar icon while the
    /// panel is open takes key away from it first, so without this the close and the click
    /// would cancel out and the panel would never shut from its own icon.
    private var lastResignHide = Date.distantPast

    var statusItemFrame: NSRect?

    private override init() { super.init() }

    func toggle() {
        if isVisible {
            hide()
        } else if Date().timeIntervalSince(lastResignHide) > 0.25 {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        Task { await AppModel.shared.refresh() }
        position(panel)

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        isVisible = true
        installKeyMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    // MARK: Construction

    private func makePanel() -> Panel {
        let controller = PanelHostingController(rootView: PanelRoot())
        controller.sizingOptions = [.preferredContentSize]
        controller.onLayout = { [weak self] in self?.repositionAfterResize() }

        let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 400),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        panel.contentViewController = controller
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.delegate = self
        return panel
    }

    // MARK: Placement

    /// Hangs the panel under the menu bar icon, pulled back onto the screen near an edge.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let margin: CGFloat = 8

        var origin: NSPoint
        if let anchor = statusItemFrame {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 5)
        } else {
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = max(origin.y, visible.minY + margin)

        isPositioning = true
        panel.setFrameOrigin(origin)
        panel.invalidateShadow()
        isPositioning = false
    }

    /// SwiftUI resizes the window from its bottom left; re-anchoring keeps the top edge put.
    private func repositionAfterResize() {
        guard let panel, isVisible, !isPositioning else { return }
        position(panel)
    }

    private var screen: NSScreen {
        if let anchor = statusItemFrame, let match = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, Int(event.keyCode) == kVK_Escape else { return event }
            self.hide()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: Window delegate

    func windowDidResignKey(_ notification: Notification) {
        guard NSApp.modalWindow == nil else { return }
        lastResignHide = Date()
        hide()
    }
}

/// The panel's root: the content on the system popover material, so it reads like a native
/// menu bar extra in both light and dark mode.
struct PanelRoot: View {
    var body: some View {
        PanelView()
            .environmentObject(AppModel.shared)
            .environmentObject(Preferences.shared)
            .environmentObject(UpdateController.shared)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
