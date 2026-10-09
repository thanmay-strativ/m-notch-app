import AppKit
import LocalAuthentication
import SwiftUI
import os

/// What a click in the island does. Risky approvals go through Touch ID first.
@MainActor
final class IslandActions {
    private let store: SessionStore
    private let model: IslandModel
    private let preferences: Preferences
    private let logger = Logger(subsystem: "local.mnotch", category: "actions")
    /// Set by the island controller: hands play/pause, next and previous to the now playing helper.
    var onMediaCommand: (NowPlayingCommand) -> Void = { _ in }

    init(store: SessionStore, model: IslandModel, preferences: Preferences) {
        self.store = store
        self.model = model
        self.preferences = preferences
    }

    func jump(to session: Session) { IDEJump.focus(session, raiseExactWindow: preferences.raiseExactWindow) }

    func open(_ diff: FileDiff, in session: Session) {
        IDEJump.open(file: diff.filePath, line: diff.firstChangedLine, in: session)
    }

    func showDiff(_ diff: FileDiff, in session: Session) {
        model.openDiff = IslandModel.OpenDiff(sessionId: session.id, diffId: diff.id)
    }

    func closeDiff() { model.openDiff = nil }

    func decide(_ request: PendingRequest, _ decision: PermissionDecision) {
        if case .deny = decision {
            store.decide(request.id, decision)
            return
        }
        guard let risk = request.risk, preferences.touchIdForRisky else {
            store.decide(request.id, decision)
            return
        }
        let context = LAContext()
        let reason = "allow the risky command (\(risk)) in \(store.session(for: request)?.name ?? "a session")"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
            let errorText = error?.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if success {
                        self.store.decide(request.id, decision)
                    } else {
                        self.logger.info("Touch ID for request \(request.id, privacy: .public) (\(risk, privacy: .public)) not confirmed: \(errorText ?? "cancelled", privacy: .public)")
                    }
                }
            }
        }
    }

    func decideOldest(_ decision: PermissionDecision) {
        guard let request = store.pending.first, request.kind == .permission || isPlan(request) else { return }
        decide(request, decision)
    }

    func answer(_ request: PendingRequest, selections: [[String]]) {
        store.answer(request.id, selections: selections)
    }

    func replyInTerminal(_ request: PendingRequest) { store.replyInTerminal(request.id) }

    func hideRequests() { model.requestsHidden = true }

    func join(_ event: CalendarEvent) {
        guard let joinURL = event.joinURL else { return }
        if !NSWorkspace.shared.open(joinURL) {
            logger.error("Could not open the join link \(joinURL.absoluteString, privacy: .public) for event \(event.title, privacy: .public)")
        }
    }

    /// Opens the calendar tab on today. A waiting request steps aside, like with the house tab.
    func showCalendar() {
        model.calendarDay = Calendar.current.startOfDay(for: Date())
        model.showingCalendar = true
        model.showingMusic = false
        model.showingSettings = false
        model.openDiff = nil
        if !store.pending.isEmpty { model.requestsHidden = true }
    }

    /// Moves the calendar tab to another day with a slide. A leaving view keeps the slide direction of its last
    /// render, so the direction is set one beat before the day changes and the old day leaves the right way.
    func selectCalendarDay(_ day: Date) {
        let startOfDay = Calendar.current.startOfDay(for: day)
        guard startOfDay != model.calendarDay else { return }
        model.calendarMovingForward = startOfDay > model.calendarDay
        DispatchQueue.main.async { [model] in
            withAnimation(IslandAnimation.calendarSwitch) { model.calendarDay = startOfDay }
        }
    }

    /// Opens the music tab. A waiting request steps aside, like with the house tab.
    func showMusic() {
        model.showingMusic = true
        model.showingCalendar = false
        model.showingSettings = false
        model.openDiff = nil
        if !store.pending.isEmpty { model.requestsHidden = true }
    }

    /// Play/pause and seeking show right away; the helper's next report confirms them.
    func sendMediaCommand(_ command: NowPlayingCommand) {
        onMediaCommand(command)
        guard let track = model.nowPlaying else { return }
        switch command {
        case .toggle: model.nowPlaying = track.toggled(now: Date())
        case .seek(let seconds): model.nowPlaying = track.seeked(to: seconds, now: Date())
        case .next, .previous: break
        }
    }

    func shiftCalendarWeek(by weeks: Int) {
        guard let day = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: model.calendarDay) else { return }
        selectCalendarDay(day)
    }

    func dismissFinishedCommand() { store.dismissFinishedCommand() }

    /// A session row click: show that session's waiting request, or switch to its IDE when nothing waits.
    func showRequestOrJump(to session: Session) {
        guard let request = store.pending.first(where: { $0.sessionId == session.id }) else {
            jump(to: session)
            return
        }
        model.focusedRequestId = request.id
        model.openDiff = nil
        model.showingSettings = false
        model.requestsHidden = false
    }

    private func isPlan(_ request: PendingRequest) -> Bool {
        if case .plan = request.kind { return true }
        return false
    }
}
