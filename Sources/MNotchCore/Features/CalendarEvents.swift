import Foundation

/// One event from the user's calendars, as the island shows it.
public struct CalendarEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let colorHex: String
    public let joinURL: URL?

    static let lookAhead: TimeInterval = 60 * 60
    static let showAfterStart: TimeInterval = 10 * 60

    /// "in 25m", "in 2h 05m", "now".
    func countdownText(now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        return minutes < 60 ? "in \(minutes)m" : "in \(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// "10:30 to 11:00" in the user's clock format.
    var timeRangeText: String {
        "\(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// "15 min", "1 h", "1 h 30 min".
    var durationText: String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    func isOngoing(now: Date) -> Bool { start <= now && now < end }

    func hasEnded(now: Date) -> Bool { end <= now }

    /// How far through the event `now` is: 0 before it starts, 1 once it ended.
    func progress(now: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return hasEnded(now: now) ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(start) / length))
    }
}

/// One calendar event reduced to plain values, so choosing what to show is testable without EventKit.
struct CalendarEntry {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isDeclined: Bool
    let isCanceled: Bool
    let calendarTitle: String
    let colorHex: String
    let linkTexts: [String]
}

extension CalendarEvent {
    init(entry: CalendarEntry) {
        self.init(id: entry.id, title: entry.title, start: entry.start, end: entry.end, isAllDay: entry.isAllDay,
                  calendarTitle: entry.calendarTitle, colorHex: entry.colorHex, joinURL: Self.joinURL(in: entry.linkTexts))
    }

    /// Every event worth showing: declined and canceled ones never are.
    static func shown(_ entries: [CalendarEntry]) -> [CalendarEvent] {
        entries.filter { !$0.isDeclined && !$0.isCanceled }.map(CalendarEvent.init(entry:))
    }

    /// The earliest timed event that starts within the hour, or started less than 10 minutes ago and has not ended.
    static func next(from entries: [CalendarEntry], now: Date) -> CalendarEvent? {
        shown(entries)
            .filter { event in
                !event.isAllDay && event.end > now
                    && event.start.timeIntervalSince(now) <= lookAhead && now.timeIntervalSince(event.start) <= showAfterStart
            }
            .min { $0.start < $1.start }
    }

    /// The first Zoom, Google Meet, Microsoft Teams or Webex link in the event's URL, location or notes.
    static func joinURL(in texts: [String]) -> URL? {
        let pattern = #"https://[A-Za-z0-9.-]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com)/[^\s<>"')]+"#
        for text in texts {
            if let range = text.range(of: pattern, options: .regularExpression) { return URL(string: String(text[range])) }
        }
        return nil
    }
}

/// One day of the calendar tab: all-day events as chips, timed events in order, and where the red now line goes.
struct DayAgenda: Equatable {
    let allDay: [CalendarEvent]
    let timed: [CalendarEvent]
    /// The line sits before `timed[nowLineIndex]` (after the last row when it equals `timed.count`).
    /// Only today has one, and only when it has timed events.
    let nowLineIndex: Int?

    init(day: Date, events: [CalendarEvent], now: Date, calendar: Calendar = .current) {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else {
            (allDay, timed, nowLineIndex) = ([], [], nil)
            return
        }
        let onDay = events.filter { $0.start < dayInterval.end && $0.end > dayInterval.start }
        allDay = onDay.filter(\.isAllDay)
        timed = onDay.filter { !$0.isAllDay }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        nowLineIndex = dayInterval.contains(now) && !timed.isEmpty ? (timed.firstIndex { $0.start > now } ?? timed.count) : nil
    }

    /// The first event still to start today, which gets the countdown.
    var nextEventId: String? {
        guard let nowLineIndex, nowLineIndex < timed.count else { return nil }
        return timed[nowLineIndex].id
    }
}

/// The week shown in the calendar strip, starting on the user's first weekday.
enum CalendarWeek {
    static func interval(containing day: Date, calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: day)
    }

    static func days(containing day: Date, calendar: Calendar = .current) -> [Date] {
        guard let week = interval(containing: day, calendar: calendar) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }
}
