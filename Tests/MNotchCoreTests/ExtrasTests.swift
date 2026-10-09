import Foundation
import Testing
@testable import MNotchCore

struct FinishedCommandTests {
    private let finishedAt = Date(timeIntervalSince1970: 1_000_000)

    @Test func readsTheFormBodyCurlSends() throws {
        let body = Data("command=pytest%20-x%20%22a%2Bb%22&exit=1&seconds=130&cwd=%2FUsers%2Fme%2Fweb-app".utf8)
        let command = try #require(FinishedCommand(formBody: body, finishedAt: finishedAt))
        #expect(command.command == #"pytest -x "a+b""#)
        #expect(command.exitCode == 1 && !command.succeeded)
        #expect(command.folder == "web-app")
        #expect(command.durationText == "2m 10s")
    }

    @Test func rejectsABodyWithoutCommandOrNumbers() {
        #expect(FinishedCommand(formBody: Data("exit=0&seconds=40".utf8), finishedAt: finishedAt) == nil)
        #expect(FinishedCommand(formBody: Data("command=make&exit=zero&seconds=40".utf8), finishedAt: finishedAt) == nil)
        #expect(FinishedCommand(formBody: Data("command=%20&exit=0&seconds=40".utf8), finishedAt: finishedAt) == nil)
    }

    @Test func durationReadsNaturally() throws {
        func duration(_ seconds: Int) throws -> String {
            try #require(FinishedCommand(formBody: Data("command=make&exit=0&seconds=\(seconds)".utf8), finishedAt: finishedAt)).durationText
        }
        #expect(try duration(45) == "45s")
        #expect(try duration(65) == "1m 05s")
        #expect(try duration(3_900) == "1h 05m")
    }
}

struct ShellHookTests {
    private func makeHome(zshrc: String?) throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("m_notch-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let zshrc { try Data(zshrc.utf8).write(to: home.appendingPathComponent(".zshrc")) }
        return home.path
    }

    @Test func installAppendsOneMarkedBlockAndRemovalRestoresTheFile() throws {
        let original = "export PATH=\"$HOME/bin:$PATH\"\nalias gs='git status'"
        let home = try makeHome(zshrc: original)
        let installPlan = try ShellHook.plan(install: true, home: home)
        let installed = installPlan.preview
        #expect(installed.hasPrefix(original + "\n\n" + ShellHook.beginMarker))
        #expect(installed.components(separatedBy: ShellHook.beginMarker).count == 2)
        try HookInstaller.apply(installPlan)

        #expect(try ShellHook.plan(install: true, home: home).preview == installed)
        let removed = try ShellHook.plan(install: false, home: home).preview
        #expect(removed == original + "\n")
    }

    @Test func installCreatesAMissingZshrc() throws {
        let home = try makeHome(zshrc: nil)
        let plan = try ShellHook.plan(install: true, home: home)
        #expect(plan.originalBytes == nil)
        #expect(plan.preview == ShellHook.block + "\n")
    }

    @Test func statusNeedsTheZshrcLineAndTheCurrentScript() throws {
        let home = try makeHome(zshrc: "alias ll='ls -l'\n")
        #expect(ShellHook.status(port: 47823, token: "secret", home: home) == .missing)
        try HookInstaller.apply(ShellHook.plan(install: true, home: home))
        #expect(ShellHook.status(port: 47823, token: "secret", home: home) == .outdated)
        try ShellHook.writeScript(port: 47823, token: "secret", home: home)
        #expect(ShellHook.status(port: 47823, token: "secret", home: home) == .installed)
        #expect(ShellHook.status(port: 47823, token: "rotated", home: home) == .outdated)
        try ShellHook.removeScript(home: home)
        #expect(ShellHook.status(port: 47823, token: "secret", home: home) == .outdated)
    }

    @Test func scriptPostsToTheShellPathAndKeepsTheTokenOutOfZshrc() throws {
        let script = ShellHook.script(port: 47823, token: "secret")
        #expect(script.contains("http://127.0.0.1:47823/m_notch/shell"))
        #expect(script.contains("Bearer secret"))
        #expect(script.contains("(( seconds >= 30 ))"))
        #expect(!ShellHook.block.contains("secret"))
    }
}

struct CalendarEventTests {
    /// 1970-01-12 13:46:40 UTC, a Monday.
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func entry(_ title: String, startsIn minutes: Double, lasts length: Double = 30, isAllDay: Bool = false,
                       isDeclined: Bool = false, isCanceled: Bool = false, links: [String] = []) -> CalendarEntry {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEntry(id: title, title: title, start: start, end: start.addingTimeInterval(length * 60),
                             isAllDay: isAllDay, isDeclined: isDeclined, isCanceled: isCanceled,
                             calendarTitle: "Work", colorHex: "#3B82F6", linkTexts: links)
    }

    @Test func picksTheEarliestMeetingWithinTheHour() {
        let entries = [
            entry("Retro", startsIn: 40),
            entry("Holiday", startsIn: -60, lasts: 24 * 60, isAllDay: true),
            entry("Declined sync", startsIn: 5, isDeclined: true),
            entry("Canceled demo", startsIn: 10, isCanceled: true),
            entry("Standup", startsIn: 20),
            entry("Tomorrow planning", startsIn: 90),
        ]
        #expect(CalendarEvent.next(from: entries, now: now)?.title == "Standup")
    }

    @Test func keepsAMeetingForTenMinutesAfterItStarts() {
        #expect(CalendarEvent.next(from: [entry("Standup", startsIn: -9)], now: now)?.title == "Standup")
        #expect(CalendarEvent.next(from: [entry("Standup", startsIn: -11)], now: now) == nil)
        #expect(CalendarEvent.next(from: [entry("Quick sync", startsIn: -8, lasts: 5)], now: now) == nil)
    }

    @Test func findsTheVideoLinkInNotesOrLocation() {
        let notes = "Agenda below.\nJoin: https://us02web.zoom.us/j/123456?pwd=abc\nDial-in: +1 555"
        #expect(CalendarEvent.joinURL(in: ["Room 4", notes])?.absoluteString == "https://us02web.zoom.us/j/123456?pwd=abc")
        #expect(CalendarEvent.joinURL(in: ["<https://meet.google.com/abc-defg-hij>"])?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(CalendarEvent.joinURL(in: ["https://example.com/agenda", "Room 4"]) == nil)
    }

    @Test func describesTimeLeftLengthAndProgress() throws {
        let standup = CalendarEvent(entry: entry("Standup", startsIn: 25, lasts: 90))
        #expect(standup.countdownText(now: now) == "in 25m")
        #expect(standup.countdownText(now: standup.start.addingTimeInterval(-30)) == "in 1m")
        #expect(standup.countdownText(now: standup.start.addingTimeInterval(120)) == "now")
        #expect(standup.countdownText(now: standup.start.addingTimeInterval(-125 * 60)) == "in 2h 05m")
        #expect(standup.durationText == "1 h 30 min")
        #expect(CalendarEvent(entry: entry("Sync", startsIn: 0, lasts: 15)).durationText == "15 min")
        #expect(standup.progress(now: now) == 0)
        #expect(standup.progress(now: standup.start.addingTimeInterval(45 * 60)) == 0.5)
        #expect(standup.progress(now: standup.end.addingTimeInterval(60)) == 1)
    }

    @Test func todaysAgendaSortsEventsAndPutsTheNowLineBeforeTheNextOne() {
        let events = CalendarEvent.shown([
            entry("Lunch", startsIn: 30),
            entry("Standup", startsIn: -120),
            entry("Holiday", startsIn: -13 * 60, lasts: 24 * 60, isAllDay: true),
            entry("Review", startsIn: 90),
            entry("Declined", startsIn: 60, isDeclined: true),
            entry("Tomorrow", startsIn: 24 * 60),
        ])
        let agenda = DayAgenda(day: now, events: events, now: now, calendar: utcCalendar)
        #expect(agenda.allDay.map(\.title) == ["Holiday"])
        #expect(agenda.timed.map(\.title) == ["Standup", "Lunch", "Review"])
        #expect(agenda.nowLineIndex == 1)
        #expect(agenda.nextEventId == "Lunch")
    }

    @Test func otherDaysHaveNoNowLineAndLateEventsPutItLast() {
        let events = CalendarEvent.shown([entry("Standup", startsIn: -120), entry("Late call", startsIn: 10 * 60, lasts: 120)])
        let today = DayAgenda(day: now, events: events, now: now.addingTimeInterval(10 * 3600 + 5 * 60), calendar: utcCalendar)
        #expect(today.nowLineIndex == 2 && today.nextEventId == nil)
        let tomorrow = DayAgenda(day: now.addingTimeInterval(86_400), events: events, now: now, calendar: utcCalendar)
        #expect(tomorrow.timed.map(\.title) == ["Late call"])
        #expect(tomorrow.nowLineIndex == nil)
    }

    @Test func weekStartsOnTheUsersFirstWeekday() throws {
        let days = CalendarWeek.days(containing: now.addingTimeInterval(3 * 86_400), calendar: utcCalendar)
        #expect(days.count == 7)
        #expect(days.first == utcCalendar.startOfDay(for: now))
        #expect(try #require(days.last).timeIntervalSince(try #require(days.first)) == 6 * 86_400)
    }

    @Test func calendarTabGrowsWithItsRows() {
        let top = IslandLayout.contentTop(notchHeight: 32)
        let busyDay = IslandLayout.expandedHeight(for: .calendar(timedEvents: 3, hasAllDay: true, hasNowLine: true), notchHeight: 32)
        #expect(busyDay == top + IslandLayout.calendarHeaderHeight + 3 * IslandLayout.calendarEventHeight
                + IslandLayout.calendarAllDayHeight + IslandLayout.calendarNowLineHeight + 14)
        let emptyDay = IslandLayout.expandedHeight(for: .calendar(timedEvents: 0, hasAllDay: false, hasNowLine: false), notchHeight: 32)
        #expect(emptyDay == max(IslandLayout.minExpandedHeight, top + IslandLayout.calendarHeaderHeight + IslandLayout.calendarEventHeight + 14))
    }
}

@MainActor
struct FinishedCommandStoreTests {
    @Test func storeSignalsTheCommandAndForgetsItAfterTenMinutes() throws {
        let store = SessionStore()
        nonisolated(unsafe) var current = Date(timeIntervalSince1970: 1_000_000)
        store.now = { current }
        var signals: [StoreSignal] = []
        store.onSignal = { signals.append($0) }
        let body = Data("command=make%20build&exit=0&seconds=95&cwd=%2Fwork%2Fm_notch".utf8)
        store.handleFinishedCommand(try #require(FinishedCommand(formBody: body, finishedAt: current)))
        #expect(signals == [.commandFinished])
        #expect(store.finishedCommand?.command == "make build")

        current = current.addingTimeInterval(9 * 60)
        store.tick()
        #expect(store.finishedCommand != nil)
        current = current.addingTimeInterval(2 * 60)
        store.tick()
        #expect(store.finishedCommand == nil)
    }

    @Test func meetingAndCommandRowsMakeTheListTaller() {
        let plain = IslandLayout.expandedHeight(for: .list(rows: 3, rowHeight: 44), notchHeight: 32)
        let withBanners = IslandLayout.expandedHeight(for: .list(rows: 3, rowHeight: 44, banners: 2), notchHeight: 32)
        #expect(withBanners == plain + 2 * IslandLayout.bannerHeight)
    }
}
