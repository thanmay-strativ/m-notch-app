import AppKit
import os

/// Brings the right IDE window forward, or opens a file at a line in it. Needs no macOS permission.
@MainActor
enum IDEJump {
    nonisolated private static let logger = Logger(subsystem: "local.mnotch", category: "jump")

    static func appURL(for host: HostApp) -> URL? {
        let running = NSWorkspace.shared.runningApplications
        for bundleId in host.bundleIds {
            if let app = running.first(where: { $0.bundleIdentifier == bundleId }), let url = app.bundleURL { return url }
        }
        return host.bundleIds.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    /// Activates the session's IDE. Never asks the IDE to open the project folder again: PyCharm answers that
    /// with an empty new project frame and hangs when the project is already open.
    static func focus(_ session: Session, raiseExactWindow: Bool) {
        guard let app = runningApp(for: session.host) else {
            logger.warning("\(session.host.displayName, privacy: .public) is not running for session \(session.id, privacy: .public)")
            return
        }
        app.activate()
        guard raiseExactWindow else { return }
        if !raiseWindow(of: app, titled: session.name) {
            logger.info("No \(session.host.displayName, privacy: .public) window titled \(session.name, privacy: .public) to raise (Accessibility trusted: \(AXIsProcessTrusted(), privacy: .public))")
        }
    }

    static func runningApp(for host: HostApp) -> NSRunningApplication? {
        host.bundleIds.lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
    }

    /// Needs the Accessibility permission. Titles look like "m_notch \u{2013} views.py" (PyCharm) or "views.py \u{2014} m_notch" (VS Code).
    static func raiseWindow(of app: NSRunningApplication, titled projectName: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return false }
        let window = windows.first { titleParts(of: $0).contains(projectName) }
            ?? windows.first { titleParts(of: $0).contains { $0.hasPrefix(projectName + " [") } }
        guard let window else { return false }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    static func titleParts(of window: AXUIElement) -> [String] {
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
              let title = titleValue as? String else { return [] }
        return splitTitle(title)
    }

    nonisolated static func splitTitle(_ title: String) -> [String] {
        title.components(separatedBy: CharacterSet(charactersIn: "\u{2013}\u{2014}"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func open(file path: String, line: Int, in session: Session) {
        guard let appURL = appURL(for: session.host) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        switch session.host {
        case .pycharm:
            run("/usr/bin/open", ["-na", appURL.path, "--args", "--line", String(line), path])
        case .vscode:
            run(appURL.appendingPathComponent("Contents/Resources/app/bin/code").path, ["-g", "\(path):\(line)"])
        default:
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            logger.error("Could not run \(executable, privacy: .public) \(arguments.joined(separator: " "), privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
