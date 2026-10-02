import SwiftUI

struct PanelView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            readings
            modePicker
            if !model.helperRunning { helperBanner }
            Group {
                section("Fan speed") {
                    rpmSlider("Minimum", value: model.config.minRPM, set: model.setMin)
                    rpmSlider("Maximum", value: model.config.maxRPM, set: model.setMax)
                    if let preview = model.curvePreview, model.config.mode == .smart {
                        Text("At \(Int((model.chipTemp ?? 0).rounded()))°C the curve asks for \(rpm(preview))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                section("Ramp") {
                    tempStepper("Start rising at", value: model.config.startTemp, range: 30...85, set: model.setStartTemp)
                    tempStepper("Full speed at", value: model.config.fullTemp, range: 40...100, set: model.setFullTemp)
                }
                .disabled(model.config.mode != .smart)
                .opacity(model.config.mode == .smart ? 1 : 0.45)
                section("Boost only when") {
                    switchRow("Plugged in", isOn: $model.config.requireCharging)
                    switchRow("I'm using the Mac", isOn: $model.config.requireActive)
                    if model.config.requireActive {
                        HStack {
                            Text("Away after").font(.system(size: 12))
                            Spacer()
                            Picker("", selection: $model.config.idleMinutes) {
                                ForEach([2.0, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) min").tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
                .disabled(model.config.mode != .smart)
                .opacity(model.config.mode == .smart ? 1 : 0.45)
            }
            if model.saveFailed {
                Label("Settings could not be saved. Reinstall the helper.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            footer
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(16)
        .frame(width: 310)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.menuBarSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.isBoosting ? Color.accentColor : .secondary)
            Text("Fanline").font(.system(size: 14, weight: .semibold))
            Spacer()
            statePill
        }
    }

    private var statePill: some View {
        let label = model.state?.label ?? (model.helperInstalled ? "Helper stopped" : "Helper missing")
        let color: Color = model.isBoosting ? .accentColor : (model.helperRunning ? .secondary : .orange)
        return Text(label)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var readings: some View {
        HStack(spacing: 8) {
            tile("Chip", model.chipTemp.map { "\(Int($0.rounded()))°C" } ?? "n/a")
            tile("Fans", fanText)
            tile("Power", powerText, symbol: model.onAC ? "bolt.fill" : "battery.75percent")
        }
    }

    private var fanText: String {
        guard !model.fans.isEmpty else { return "n/a" }
        let avg = model.fans.map(\.actual).reduce(0, +) / Double(model.fans.count)
        return rpm(avg)
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
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach([(FanMode.smart, "Smart"), (.max, "Max"), (.off, "Off")], id: \.0) { mode, title in
                    let selected = model.config.mode == mode
                    Button { model.config.mode = mode } label: {
                        Text(title)
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
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text(modeHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeHint: String {
        switch model.config.mode {
        case .smart: "Follows the curve when the conditions below are met. Otherwise macOS runs the fans."
        case .max: "Fans held at your Maximum until you switch modes."
        case .off: "Fanline leaves the fans alone. macOS runs them."
        }
    }

    private var helperBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Fan control needs a small helper that runs as admin. You'll be asked for your password once.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button(model.installing ? "Installing…" : "Install helper") { model.runHelperScript("install-helper") }
                    .disabled(model.installing)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .tracking(0.6)
            content()
        }
    }

    private func rpmSlider(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(rpm(value)).monospacedDigit().foregroundStyle(.secondary)
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
                Text("\(Int(value))°C").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            switchRow("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: model.toggleLaunchAtLogin))
            HStack {
                Circle().fill(model.helperRunning ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(model.helperRunning ? "Helper running" : "Helper not running")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Reinstall helper") { model.runHelperScript("install-helper") }
                    Button("Remove helper") { model.runHelperScript("uninstall-helper") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Button("Quit") { NSApp.terminate(nil) }
            }
            Text("Quitting closes this menu only. The helper keeps applying your settings.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    private func rpm(_ value: Double) -> String { "\(Int(value.rounded()).formatted()) rpm" }
}
