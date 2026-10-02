import AppKit
import ServiceManagement
import SwiftUI

// Sirocco is an AppKit app (NSStatusItem, so the icon can spin) with SwiftUI content.
//
// Two command line modes exist for support and QA, and exit without showing any UI:
//
//   Sirocco.app/Contents/MacOS/Sirocco --helper status|register|unregister
//   Sirocco.app/Contents/MacOS/Sirocco --snapshot out.png [light|dark]
let arguments = CommandLine.arguments

MainActor.assumeIsolated {
    if let i = arguments.firstIndex(of: "--helper") {
        HelperCommand.run(arguments.count > i + 1 ? arguments[i + 1] : "status")
    }
    if let i = arguments.firstIndex(of: "--snapshot"), arguments.count > i + 1 {
        Snapshot.render(to: arguments[i + 1], dark: arguments.last != "light")
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

@MainActor
enum HelperCommand {
    static func run(_ command: String) -> Never {
        let service = SMAppService.daemon(plistName: Identity.helperPlistName)
        switch command {
        case "register":
            do { try service.register() } catch { print("register: \(error.localizedDescription)") }
        case "unregister":
            var done = false
            service.unregister { error in
                if let error { print("unregister: \(error.localizedDescription)") }
                done = true
            }
            while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        default:
            break
        }
        print("helper: \(describe(service.status))")
        exit(0)
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "not registered"
        case .enabled: "enabled"
        case .requiresApproval: "requires approval in System Settings > General > Login Items"
        case .notFound: "not registered yet (run --helper register)"
        @unknown default: "unknown"
        }
    }
}

/// Renders the panel to a PNG using live data, for README screenshots and visual checks.
@MainActor
enum Snapshot {
    static func render(to path: String, dark: Bool) -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = AppModel.shared
        var finished = false
        Task {
            await model.refresh()
            finished = true
        }
        while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

        let host = NSHostingView(rootView: PanelRoot())
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = host.appearance
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(Int(size.width))x\(Int(size.height)))")
            exit(0)
        } catch {
            print("snapshot: \(error.localizedDescription)")
            exit(1)
        }
    }
}
