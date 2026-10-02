import SwiftUI

struct PanelView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.phase == .unsupported {
                SetupCard()
            } else {
                if model.phase != .ready { SetupCard() }
                readings
                Group {
                    modePicker
                    fanSpeedSection
                    rampSection
                    conditionsSection
                }
                .disabled(!model.controlsEnabled)
                .opacity(model.controlsEnabled ? 1 : 0.5)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(16)
        .frame(width: 330)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isBoosting ? "fan.fill" : "fan")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.isBoosting ? Color.accentColor : .secondary)
            Text("Sirocco").font(.system(size: 14, weight: .semibold))
            Spacer()
            statePill
        }
    }

    private var statePill: some View {
        let label: String
        switch model.phase {
        case .ready: label = model.state?.label ?? "Ready"
        case .unsupported: label = "No fans"
        case .notInstalled: label = "Setup needed"
        case .needsApproval: label = "Needs approval"
        case .starting: label = "Starting"
        case .notResponding: label = "Not responding"
        }
        let attention = model.phase != .ready && model.phase != .unsupported
        let color: Color = model.isBoosting ? .accentColor : (attention ? .orange : .secondary)
        return Text(label)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: Readings

    private var readings: some View {
        HStack(spacing: 8) {
            tile("Chip", model.chipTemp.map { prefs.temperature($0) } ?? "n/a")
            tile("Fans", model.averageRPM > 0 ? Preferences.rpm(model.averageRPM) : (model.fans.isEmpty ? "n/a" : "Stopped"))
            tile("Power", powerText, symbol: model.onAC ? "bolt.fill" : "battery.75percent")
        }
    }

    private var powerText: String {
        guard let b = model.battery else { return model.onAC ? "Plugged in" : "Battery" }
        return "\(b.percent)%"
    }

    private func tile(_ title: String, _ value: String, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary) }
                Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Mode

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(FanMode.allCases, id: \.self) { mode in
                    let selected = model.config.mode == mode
                    Button { model.config.mode = mode } label: {
                        Text(mode.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(selected ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? .primary : .secondary)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            Text(model.config.mode.hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sections

    private var fanSpeedSection: some View {
        section("Fan speed", trailing: AnyView(presetMenu)) {
            rpmSlider("Minimum", value: model.config.minRPM, set: model.setMin)
            rpmSlider("Maximum", value: model.config.maxRPM, set: model.setMax)
            if let preview = model.curvePreview, model.config.mode == .smart, let t = model.chipTemp {
                Text("At \(prefs.temperature(t)) the curve asks for \(Preferences.rpm(preview))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var presetMenu: some View {
        Menu("Presets") {
            ForEach(FanPreset.allCases) { preset in
                Button(preset.title) { model.apply(preset) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
    }

    private var rampSection: some View {
        section("Ramp") {
            tempStepper("Start rising at", value: model.config.startTemp, range: 30...85, set: model.setStartTemp)
            tempStepper("Full speed at", value: model.config.fullTemp, range: 40...100, set: model.setFullTemp)
        }
        .disabled(model.config.mode != .smart)
        .opacity(model.config.mode == .smart ? 1 : 0.45)
    }

    private var conditionsSection: some View {
        section("Boost only when") {
            switchRow("Plugged in", isOn: $model.config.requireCharging)
            switchRow("I'm using the Mac", isOn: $model.config.requireActive)
            if model.config.requireActive {
                HStack {
                    Text("Away after").font(.system(size: 12))
                    Spacer()
                    // Buttons, not a Picker: in this panel a menu's picker items come up
                    // disabled, because the panel can never be the main window.
                    Menu("\(Int(model.config.idleMinutes)) min") {
                        ForEach([2.0, 5, 10, 15, 30], id: \.self) { minutes in
                            Button("\(Int(minutes)) min") { model.config.idleMinutes = minutes }
                        }
                    }
                    .fixedSize()
                }
            }
        }
        .disabled(model.config.mode != .smart)
        .opacity(model.config.mode == .smart ? 1 : 0.45)
    }

    private func section<Content: View>(_ title: String, trailing: AnyView? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
    }

    private func rpmSlider(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(Preferences.rpm(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            Slider(value: Binding(get: { value }, set: { set(($0 / 100).rounded() * 100) }),
                   in: model.hardwareMin...model.hardwareMax)
        }
    }

    private func tempStepper(_ title: String, value: Double, range: ClosedRange<Double>,
                             set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: set), in: range, step: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(prefs.temperature(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(model.phase == .ready ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(model.phase == .ready ? "Helper running" : "Helper not running")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Everything that is not a fan control lives in the settings window.
                Button { SettingsWindowController.shared.show() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            if model.phase == .ready {
                Text("Quitting closes this menu only. The helper keeps applying your settings.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension FanMode {
    var title: String {
        switch self {
        case .smart: "Smart"
        case .max: "Max"
        case .off: "Off"
        }
    }

    var hint: String {
        switch self {
        case .smart: "Boosts along your curve when the conditions below are met. Otherwise macOS runs the fans."
        case .max: "Fans held at your Maximum until you switch modes."
        case .off: "Sirocco leaves the fans alone. macOS runs them."
        }
    }
}

/// What stands between the user and working fan control, with the button that fixes it.
/// Empty once the helper is ready. Shared by the panel and the settings window.
struct SetupCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.phase {
        case .unsupported:
            card(symbol: "wind", title: "This Mac has no fans",
                 body: "Sirocco controls fan speed, and this Mac cools itself without fans, so there is nothing for it to do here.") {
                EmptyView()
            }
        case .notInstalled:
            card(symbol: "lock.shield", title: "Turn on fan control",
                 body: "Sirocco uses a small helper to change fan speeds. macOS asks you to allow it once.") {
                Button("Turn On") { model.enableHelper() }.buttonStyle(.borderedProminent)
            }
        case .needsApproval:
            card(symbol: "hand.raised", title: "Allow Sirocco in System Settings",
                 body: "In General, Login Items & Extensions, switch on Sirocco under Allow in the Background. This updates on its own.") {
                Button("Open System Settings") { model.openApprovalSettings() }.buttonStyle(.borderedProminent)
            }
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting the helper").font(.caption).foregroundStyle(.secondary)
            }
        case .notResponding:
            card(symbol: "exclamationmark.triangle", title: "The helper is not responding",
                 body: "Restarting it usually fixes this.") {
                Button(model.busy ? "Restarting…" : "Restart Helper") { model.restartHelper() }
                    .disabled(model.busy)
            }
        case .ready:
            EmptyView()
        }
    }

    private func card<Actions: View>(symbol: String, title: String, body: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions().padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
