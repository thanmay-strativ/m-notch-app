import AppKit
import SwiftUI

/// The full settings window, opened from the island gear card or the menu bar.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(preferences: Preferences, status: AppStatus, store: SessionStore, coordinator: AppCoordinator) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "m_notch Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsWindowView(
            preferences: preferences, status: status, store: store,
            setLaunchAtLogin: { [weak coordinator] enabled in coordinator?.setLaunchAtLogin(enabled) }))
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
