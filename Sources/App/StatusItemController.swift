import AppKit
import Combine
import QuartzCore

/// The menu bar item: a fan that spins at a speed following the real fans, plus optional text.
///
/// Animating a menu bar icon is the last thing a cooling app should spend CPU on. Swapping the
/// button's image per frame measured 6 to 9% CPU, because the status bar re-lays out and
/// re-renders the button each time. Instead the fan is a Core Animation layer over the button
/// with one repeating rotation: the render server turns it, the app is not woken per frame
/// (measured near 0%), and the frame rate is capped at 30 fps to keep compositing light too.
/// The animation is removed entirely when the fans stop, the screen sleeps, or spinning is off.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private static let iconSide: CGFloat = 18

    private var statusItem: NSStatusItem?
    private let fanView = FanLayerView()
    private var degreesPerSecond: Double = 0
    private var screensAsleep = false
    private var cancellables: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?

    private override init() { super.init() }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // A clear template image holds the icon's place in the layout; the visible fan is
            // the layer view laid over it.
            button.image = Self.placeholder
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Sirocco")
            button.addSubview(fanView)
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] button, _ in
                let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                MainActor.assumeIsolated { self?.fanView.setTint(dark ? .white : .black) }
            }
        }
        statusItem = item

        // Model and preference changes are coalesced: a refresh publishes several fields at once.
        AppModel.shared.objectWillChange
            .merge(with: Preferences.shared.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        render()
    }

    /// Screen frame of the button, used to hang the panel under it.
    var buttonFrame: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private static let placeholder: NSImage = {
        let image = NSImage(size: NSSize(width: iconSide, height: iconSide))
        image.isTemplate = true
        return image
    }()

    // MARK: Rendering

    private func render() {
        guard let button = statusItem?.button else { return }
        let model = AppModel.shared
        let prefs = Preferences.shared

        let text: String
        switch prefs.menuBarText {
        case .none: text = ""
        case .temperature: text = model.chipTemp.map { " " + prefs.temperature($0, unit: false) } ?? ""
        case .speed: text = model.averageRPM > 0 ? " " + Preferences.shortRPM(model.averageRPM) : ""
        case .both:
            let parts = [model.chipTemp.map { prefs.temperature($0, unit: false) },
                         model.averageRPM > 0 ? Preferences.shortRPM(model.averageRPM) : nil].compactMap { $0 }
            text = parts.isEmpty ? "" : " " + parts.joined(separator: " ")
        }
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .baselineOffset: 0.5
        ])

        var tip = "Sirocco"
        if model.averageRPM > 0 { tip += ", fans \(Preferences.rpm(model.averageRPM))" }
        if let t = model.chipTemp { tip += ", chip \(prefs.temperature(t))" }
        if let state = model.state { tip += ", \(state.label.lowercased())" }
        button.toolTip = tip

        button.layoutSubtreeIfNeeded()
        if let cell = button.cell as? NSButtonCell {
            fanView.frame = cell.imageRect(forBounds: button.bounds)
        }
        fanView.setFilled(model.isBoosting)

        let rpm = model.averageRPM
        degreesPerSecond = prefs.spinIcon && rpm > 0 && !screensAsleep ? Self.spinSpeed(rpm: rpm) : 0
        fanView.spin(degreesPerSecond: degreesPerSecond)
    }

    /// Visual spin speed for a fan speed. A real fan at 3,500 rpm is a blur; this keeps the
    /// relation (faster fans, faster icon) while staying readable: about 150°/s at the usual
    /// idle of 2,300 rpm up to 360°/s near the maximum.
    private static func spinSpeed(rpm: Double) -> Double {
        min(max(60 + rpm * 0.04, 90), 360)
    }

    // MARK: Events

    @objc private func clicked() {
        PanelController.shared.statusItemFrame = buttonFrame
        PanelController.shared.toggle()
    }

    @objc private func screensDidSleep() {
        screensAsleep = true
        render()
    }

    @objc private func screensDidWake() {
        screensAsleep = false
        render()
    }
}

/// A layer-hosting view: AppKit leaves its sublayers alone, so the fan layer keeps a centred
/// anchor point and its rotation animation.
@MainActor
final class FanLayerView: NSView {
    private let fanLayer = CALayer()
    private var tint: NSColor = .white
    private var filled = false
    private var currentSpeed: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(fanLayer)
        fanLayer.contentsGravity = .resizeAspect
        updateContents()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Clicks go to the status bar button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fanLayer.bounds = bounds
        fanLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        fanLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContents()
    }

    func setTint(_ color: NSColor) {
        guard color != tint else { return }
        tint = color
        updateContents()
    }

    func setFilled(_ value: Bool) {
        guard value != filled else { return }
        filled = value
        updateContents()
    }

    func spin(degreesPerSecond: Double) {
        // Small wobbles in fan speed would restart the animation for no visible difference.
        if currentSpeed > 0, degreesPerSecond > 0, abs(degreesPerSecond - currentSpeed) / currentSpeed < 0.1 { return }
        guard degreesPerSecond != currentSpeed else { return }
        currentSpeed = degreesPerSecond

        // Carry on from where the fan is now, so a speed change does not snap it back to 0°.
        let angle = (fanLayer.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? 0
        fanLayer.removeAnimation(forKey: "spin")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fanLayer.setValue(angle, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
        guard degreesPerSecond > 0 else { return }

        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        // Negative is clockwise here, the way the blades are drawn to turn.
        animation.fromValue = angle
        animation.toValue = angle - 2 * Double.pi
        animation.duration = 360 / degreesPerSecond
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        fanLayer.add(animation, forKey: "spin")
    }

    private func updateContents() {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(.init(paletteColors: [tint]))
        guard let symbol = NSImage(systemSymbolName: filled ? "fan.fill" : "fan", accessibilityDescription: "Sirocco")?
            .withSymbolConfiguration(config) else { return }
        let side: CGFloat = 18
        let scale = window?.backingScaleFactor ?? 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            symbol.draw(in: NSRect(x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: side * scale, height: side * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fanLayer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
        CATransaction.commit()
    }
}
