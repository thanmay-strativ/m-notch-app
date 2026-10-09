import Foundation
import Observation

/// Live app health shown in settings and the menu bar: server, hooks, status line relay, terminal hook,
/// calendar access, login item, updates.
@MainActor
@Observable
final class AppStatus {
    var serverStatus: HookServer.Status = .starting
    var hookStatuses: [HookTarget: HookStatus] = [:]
    var statusLineStatus: HookStatus = .missing
    var shellHookStatus: HookStatus = .missing
    var calendarAccess: CalendarAccess = .notAsked
    var launchAtLoginError: String?
    var updateState: UpdateState = .idle

    @ObservationIgnored var installHooks: (HookTarget) -> Void = { _ in }
    @ObservationIgnored var uninstallHooks: (HookTarget) -> Void = { _ in }
    @ObservationIgnored var setStatusLineRelay: (Bool) -> Void = { _ in }
    @ObservationIgnored var setShellHook: (Bool) -> Void = { _ in }
    @ObservationIgnored var openSettingsWindow: () -> Void = {}
    @ObservationIgnored var requestAccessibility: () -> Void = {}
    @ObservationIgnored var checkForUpdates: () -> Void = {}
    @ObservationIgnored var installUpdate: () -> Void = {}

    var needsHookInstall: Bool { hookStatuses[.claude].map { $0 != .installed } ?? false }

    var serverLine: String {
        switch serverStatus {
        case .starting: return "starting"
        case .ready(let port): return "listening on 127.0.0.1:\(port)"
        case .failed(let reason): return reason
        }
    }
}
