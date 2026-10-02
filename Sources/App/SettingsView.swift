import SwiftUI

struct SettingsRoot: View {
    var body: some View {
        SettingsView()
            .environmentObject(AppModel.shared)
            .environmentObject(Preferences.shared)
            .environmentObject(UpdateController.shared)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case fans, menuBar, general, helper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fans: "Fan Control"
        case .menuBar: "Menu Bar"
        case .general: "General"
        case .helper: "Helper"
        }
    }

    var symbol: String {
        switch self {
        case .fans: "fan"
        case .menuBar: "menubar.rectangle"
        case .general: "gearshape"
        case .helper: "lock.shield"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var updates: UpdateController
    @State private var pane: SettingsPane = .fans
    @State private var showTroubleshooting = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 640, minHeight: 420)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { item in
                let selected = pane == item
                Button { pane = item } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13))
                            .frame(width: 20)
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                        Text(item.title).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(selected ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            status
        }
        .padding(.horizontal, 10)
        .padding(.top, 52)
        .padding(.bottom, 12)
        .frame(width: 190)
        .background(VisualEffectBackground(material: .sidebar))
    }

    /// Live state at the foot of the sidebar, visible from every pane.
    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(model.phase == .ready ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(stateText).font(.system(size: 11, weight: .medium))
            }
            Text(readingText).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var stateText: String {
        switch model.phase {
        case .ready: model.state?.label ?? "Ready"
        case .unsupported: "No fans"
        case .notInstalled: "Setup needed"
        case .needsApproval: "Needs approval"
        case .starting: "Starting"
        case .notResponding: "Not responding"
        }
    }

    private var readingText: String {
        var parts: [String] = []
        if let t = model.chipTemp { parts.append(prefs.temperature(t)) }
        if model.averageRPM > 0 { parts.append(Preferences.rpm(model.averageRPM)) }
        return parts.isEmpty ? "No readings" : parts.joined(separator: " · ")
    }

    // MARK: Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pane.title)
                .font(.system(size: 20, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
            Form {
                switch pane {
                case .fans: fansPane
                case .menuBar: menuBarPane
                case .general: generalPane
                case .helper: helperPane
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Fan Control

    @ViewBuilder
    private var fansPane: some View {
        if model.phase != .ready {
            Section { SetupCard() }
        }
        if model.phase != .unsupported {
            Section("Now") {
                LabeledContent("Chip", value: model.chipTemp.map { prefs.temperature($0) } ?? "n/a")
                ForEach(Array(model.fans.enumerated()), id: \.offset) { index, fan in
                    LabeledContent(model.fans.count > 1 ? "Fan \(index + 1)" : "Fan",
                                   value: fan.actual > 0 ? Preferences.rpm(fan.actual) : "Stopped")
                }
                LabeledContent("Power", value: powerText)
            }
            .monospacedDigit()

            Group {
                Section {
                    Picker("Mode", selection: $model.config.mode) {
                        ForEach(FanMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    footnote(model.config.mode.hint)
                }

                Section {
                    rpmSlider("Minimum", value: model.config.minRPM, set: model.setMin)
                    rpmSlider("Maximum", value: model.config.maxRPM, set: model.setMax)
                } header: {
                    HStack {
                        Text("Fan speed")
                        Spacer()
                        Menu("Presets") {
                            ForEach(FanPreset.allCases) { preset in
                                Button(preset.title) { model.apply(preset) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } footer: {
                    if let preview = model.curvePreview, model.config.mode == .smart, let t = model.chipTemp {
                        footnote("At \(prefs.temperature(t)) the curve asks for \(Preferences.rpm(preview)).")
                    }
                }

                Group {
                    Section("Ramp") {
                        CurveGraph(config: model.config, hardwareMin: model.hardwareMin, hardwareMax: model.hardwareMax,
                                   temperature: model.chipTemp, label: { prefs.temperature($0, unit: $1) })
                            .frame(height: 120)
                            .padding(.vertical, 4)
                        tempStepper("Start rising at", value: model.config.startTemp, range: 30...85, set: model.setStartTemp)
                        tempStepper("Full speed at", value: model.config.fullTemp, range: 40...100, set: model.setFullTemp)
                    }
                    Section("Boost only when") {
                        Toggle("Plugged in", isOn: $model.config.requireCharging)
                        Toggle("I'm using the Mac", isOn: $model.config.requireActive)
                        if model.config.requireActive {
                            Picker("Away after", selection: $model.config.idleMinutes) {
                                ForEach([2.0, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) min").tag($0) }
                            }
                        }
                    }
                }
                .disabled(model.config.mode != .smart)

                Section {
                    Button("Reset Fan Settings") { model.resetToDefaults() }
                }
            }
            .disabled(!model.controlsEnabled)
        }
    }

    private var powerText: String {
        let source = model.onAC ? "Plugged in" : "On battery"
        guard let battery = model.battery else { return source }
        return "\(source), \(battery.percent)%"
    }

    private func rpmSlider(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: { set(($0 / 100).rounded() * 100) }),
                       in: model.hardwareMin...model.hardwareMax)
                    .frame(minWidth: 180)
                Text(Preferences.rpm(value)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }

    private func tempStepper(_ title: String, value: Double, range: ClosedRange<Double>,
                             set: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            Stepper(value: Binding(get: { value }, set: set), in: range, step: 5) {
                Text(prefs.temperature(value)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Menu Bar

    @ViewBuilder
    private var menuBarPane: some View {
        Section {
            Picker("Next to the icon", selection: $prefs.menuBarText) {
                ForEach(Preferences.MenuBarText.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Spin the icon with the fans", isOn: $prefs.spinIcon)
        } footer: {
            footnote("Click the fan in the menu bar for the quick panel.")
        }
        Section {
            Picker("Temperature", selection: $prefs.fahrenheit) {
                Text("Celsius").tag(false)
                Text("Fahrenheit").tag(true)
            }
        }
    }

    // MARK: General

    @ViewBuilder
    private var generalPane: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
        }
        Section("Updates") {
            Toggle("Check automatically", isOn: $updates.automaticallyChecks)
            LabeledContent("Sirocco \(model.appVersion)") {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            }
        }
        Section {
            LabeledContent("Quit Sirocco") {
                Button("Quit") { NSApp.terminate(nil) }
            }
        } footer: {
            if model.phase == .ready {
                footnote("Quitting closes the app only. The helper keeps applying your settings.")
            }
        }
    }

    // MARK: Helper

    @ViewBuilder
    private var helperPane: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle().fill(model.phase == .ready ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(helperStatusText)
                }
            }
            if let version = model.status?.helperVersion {
                LabeledContent("Version", value: version)
            }
        } footer: {
            footnote("Changing fan speeds needs root, so a small helper inside the app does it. Sirocco starts it, updates it and restarts it for you. It hands the fans back to macOS whenever it stops.")
        }
        if model.phase != .ready {
            Section { SetupCard() }
        }
        if model.phase != .unsupported {
            Section {
                DisclosureGroup("Troubleshooting", isExpanded: $showTroubleshooting) {
                    LabeledContent("Restart the helper") {
                        Button(model.busy ? "Restarting…" : "Restart") { model.restartHelper() }
                    }
                    .disabled(model.phase == .notInstalled)
                    LabeledContent("Remove the helper") {
                        Button("Remove") { model.removeHelper() }
                    }
                    .disabled(model.phase == .notInstalled)
                }
            } footer: {
                if showTroubleshooting {
                    footnote("Remove the helper before deleting Sirocco. Fan control stays off until you turn it on again.")
                }
            }
            .disabled(model.busy)
        }
        if let error = model.lastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    private var helperStatusText: String {
        switch model.phase {
        case .ready: "Running"
        case .starting: "Starting"
        case .needsApproval: "Waiting for your approval"
        case .notInstalled: "Off"
        case .notResponding: model.busy ? "Restarting" : "Not responding"
        case .unsupported: "Not needed"
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The fan curve: Minimum up to the start temperature, a straight climb to Maximum at the full
/// temperature, with a dot where the chip is now.
struct CurveGraph: View {
    let config: FanConfig
    let hardwareMin: Double
    let hardwareMax: Double
    let temperature: Double?
    let label: (Double, Bool) -> String

    private let temperatures: ClosedRange<Double> = 30...100

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let plot = CGRect(x: 0, y: 6, width: size.width, height: size.height - 26)
            ZStack(alignment: .topLeading) {
                Path { path in
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = plot.maxY - plot.height * fraction
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                }
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                curve(in: plot, closed: true).fill(Color.accentColor.opacity(0.12))
                curve(in: plot, closed: false)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let temperature {
                    let clamped = min(max(temperature, temperatures.lowerBound), temperatures.upperBound)
                    Circle()
                        .fill(Color.accentColor)
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .frame(width: 11, height: 11)
                        .position(point(clamped, config.curveRPM(at: clamped), in: plot))
                }

                ForEach([config.startTemp, config.fullTemp], id: \.self) { value in
                    Text(label(value, false))
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        .position(x: min(max(point(value, 0, in: plot).x, 14), size.width - 14), y: size.height - 7)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Fan curve from \(Preferences.rpm(config.minRPM)) at \(label(config.startTemp, true)) to \(Preferences.rpm(config.maxRPM)) at \(label(config.fullTemp, true))")
    }

    private func point(_ temperature: Double, _ rpm: Double, in plot: CGRect) -> CGPoint {
        let x = (temperature - temperatures.lowerBound) / (temperatures.upperBound - temperatures.lowerBound)
        let span = max(hardwareMax - hardwareMin, 1)
        let y = min(max((rpm - hardwareMin) / span, 0), 1)
        // A little headroom so a curve at the hardware limits is not drawn on the edge.
        return CGPoint(x: plot.minX + plot.width * x, y: plot.maxY - plot.height * (0.06 + 0.88 * y))
    }

    private func curve(in plot: CGRect, closed: Bool) -> Path {
        Path { path in
            let points = [temperatures.lowerBound, config.startTemp, config.fullTemp, temperatures.upperBound]
                .map { point($0, config.curveRPM(at: $0), in: plot) }
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            if closed {
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                path.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
                path.closeSubpath()
            }
        }
    }
}
