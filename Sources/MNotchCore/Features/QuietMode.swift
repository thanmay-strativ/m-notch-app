import AppKit

/// True when the session's IDE is already the front app, so the island does not need to pop out.
/// ponytail: app-level check only (no Accessibility permission), so two PyCharm projects count as one.
enum QuietMode {
    @MainActor
    static func isLooking(at session: Session) -> Bool {
        guard let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return session.host.bundleIds.contains(frontBundleId)
    }
}
