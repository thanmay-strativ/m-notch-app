import AppKit
import EventKit
import os

/// Whether m_notch may read the calendars of the macOS Calendar app.
enum CalendarAccess: Equatable {
    case notAsked, allowed, denied

    static var current: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    var label: String {
        switch self {
        case .notAsked: return "Calendars: asked when you turn this on"
        case .allowed: return "Calendars: allowed"
        case .denied: return "Calendars: not allowed"
        }
    }
}

/// Finds the next meeting and the events of the week shown in the calendar tab, every minute and whenever
/// a calendar changes. Asks for the Calendars permission the first time it is enabled.
@MainActor
final class CalendarWatcher {
    static let refreshInterval: TimeInterval = 60
    nonisolated static let fallbackColorHex = "#8E939C"

    var onNextMeeting: (CalendarEvent?) -> Void = { _ in }
    var onWeekEvents: ([CalendarEvent]) -> Void = { _ in }
    var onAccessChange: (CalendarAccess) -> Void = { _ in }
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }
    var shownWeek: DateInterval? {
        didSet {
            guard shownWeek != oldValue, refreshTimer != nil else { return }
            refresh()
        }
    }
    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var lastNextMeeting: CalendarEvent?
    private var lastWeekEvents: [CalendarEvent] = []
    private let logger = Logger(subsystem: "local.mnotch", category: "calendar")

    private func start() {
        switch CalendarAccess.current {
        case .allowed:
            beginWatching()
        case .notAsked:
            eventStore.requestFullAccessToEvents { @Sendable [weak self] granted, error in
                let errorText = error?.localizedDescription
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.onAccessChange(CalendarAccess.current)
                        guard granted else {
                            self.logger.warning("Calendar access not granted: \(errorText ?? "denied by the user", privacy: .public)")
                            return
                        }
                        if self.isEnabled { self.beginWatching() }
                    }
                }
            }
        case .denied:
            logger.warning("Calendar access status is \(EKEventStore.authorizationStatus(for: .event).rawValue, privacy: .public), so no meetings are shown")
        }
    }

    private func beginWatching() {
        guard refreshTimer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        publish(nextMeeting: nil, weekEvents: [])
    }

    private func refresh() {
        let now = Date()
        let soonEntries = entries(from: now.addingTimeInterval(-CalendarEvent.showAfterStart),
                                  to: now.addingTimeInterval(CalendarEvent.lookAhead))
        let weekEvents = shownWeek.map { CalendarEvent.shown(entries(from: $0.start, to: $0.end)) } ?? []
        publish(nextMeeting: CalendarEvent.next(from: soonEntries, now: now), weekEvents: weekEvents)
    }

    private func entries(from start: Date, to end: Date) -> [CalendarEntry] {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).map(CalendarEntry.init(event:))
    }

    private func publish(nextMeeting: CalendarEvent?, weekEvents: [CalendarEvent]) {
        if nextMeeting != lastNextMeeting {
            lastNextMeeting = nextMeeting
            onNextMeeting(nextMeeting)
        }
        if weekEvents != lastWeekEvents {
            lastWeekEvents = weekEvents
            onWeekEvents(weekEvents)
        }
    }

    /// "#RRGGBB" for a calendar's color, gray when it has none.
    nonisolated static func hex(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return fallbackColorHex }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}

extension CalendarEntry {
    init(event: EKEvent) {
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(id: "\(event.calendarItemIdentifier) \(event.startDate.timeIntervalSince1970)",
                  title: title.isEmpty ? "Meeting" : title,
                  start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                  isDeclined: event.attendees?.contains(where: { attendee in
                      attendee.isCurrentUser && attendee.participantStatus == .declined
                  }) ?? false,
                  isCanceled: event.status == .canceled,
                  calendarTitle: event.calendar?.title ?? "",
                  colorHex: CalendarWatcher.hex(event.calendar?.color),
                  linkTexts: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 })
    }
}
