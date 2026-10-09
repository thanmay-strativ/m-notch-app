import SwiftUI

/// The calendar tab: a week strip, the chosen day's title, then its events with a red now line.
/// Changing the day slides the agenda sideways, and the selected-day highlight glides between days.
struct CalendarView: View {
    let model: IslandModel
    let status: AppStatus
    let actions: IslandActions

    private var slideEdge: Edge { model.calendarMovingForward ? .trailing : .leading }

    var body: some View {
        if status.calendarAccess == .allowed {
            VStack(alignment: .leading, spacing: 6) {
                WeekStrip(model: model, actions: actions, slideEdge: slideEdge)
                CalendarDayTitle(day: model.calendarDay, actions: actions)
                ZStack(alignment: .top) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        AgendaView(agenda: DayAgenda(day: model.calendarDay, events: model.weekEvents, now: context.date),
                                   now: context.date, actions: actions)
                    }
                    .id(model.calendarDay)
                    .transition(.push(from: slideEdge))
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
            }
        } else {
            CalendarAccessNote(access: status.calendarAccess)
        }
    }
}

/// `‹  MON 6  TUE 7  [WED 8]  ...  ›` with up to three dots in the colors of each day's calendars.
struct WeekStrip: View {
    let model: IslandModel
    let actions: IslandActions
    let slideEdge: Edge
    @Namespace private var highlight

    var body: some View {
        let days = CalendarWeek.days(containing: model.calendarDay)
        let weekStart = days.first ?? model.calendarDay
        HStack(spacing: 4) {
            StripArrow(icon: "chevron.left", help: "Previous week") { actions.shiftCalendarWeek(by: -1) }
            ZStack {
                HStack(spacing: 2) {
                    ForEach(days, id: \.self) { day in
                        DayCell(day: day, isSelected: day == model.calendarDay, dotColors: dotColors(on: day),
                                highlight: highlight, highlightId: weekStart) {
                            actions.selectCalendarDay(day)
                        }
                    }
                }
                .id(weekStart)
                .transition(.push(from: slideEdge))
            }
            .clipped()
            StripArrow(icon: "chevron.right", help: "Next week") { actions.shiftCalendarWeek(by: 1) }
        }
        .frame(height: 44)
    }

    private func dotColors(on day: Date) -> [String] {
        let colors = DayAgenda(day: day, events: model.weekEvents, now: .distantPast).timed.map(\.colorHex)
        return Array(colors.reduce(into: [String]()) { unique, hex in if !unique.contains(hex) { unique.append(hex) } }.prefix(3))
    }
}

struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let dotColors: [String]
    let highlight: Namespace.ID
    let highlightId: Date
    let action: () -> Void
    @State private var isHovered = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var numberColor: Color {
        if isSelected { return isToday ? .white : Palette.text }
        return isToday ? Palette.danger : Palette.text
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(verbatim: day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(isSelected ? Palette.text.opacity(0.75) : Palette.tertiary)
                Text(verbatim: day.formatted(.dateTime.day()))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(numberColor)
                HStack(spacing: 2) {
                    ForEach(dotColors, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isToday ? Palette.danger.opacity(0.85) : Color.white.opacity(0.13))
                        .matchedGeometryEffect(id: highlightId, in: highlight)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
    }
}

struct StripArrow: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isHovered ? Palette.text : Palette.secondary)
                .frame(width: 22, height: 42)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(isHovered ? 0.07 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// "Today  Thursday, October 8" with a Today button when another day is shown.
struct CalendarDayTitle: View {
    let day: Date
    let actions: IslandActions

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: title).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.text)
            Text(verbatim: day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 11)).foregroundColor(Palette.tertiary)
            Spacer(minLength: 4)
            if !Calendar.current.isDateInToday(day) {
                Button { actions.selectCalendarDay(Date()) } label: {
                    Text(verbatim: "Today")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundColor(Palette.text)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.white.opacity(0.09)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 4)
        .frame(height: 18)
    }
}

/// The day's all-day chips, then its timed events with the now line between past and upcoming ones.
struct AgendaView: View {
    let agenda: DayAgenda
    let now: Date
    let actions: IslandActions

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if !agenda.allDay.isEmpty {
                    AllDayChips(events: agenda.allDay)
                }
                if agenda.timed.isEmpty {
                    EmptyDayRow(hasAllDayEvents: !agenda.allDay.isEmpty)
                }
                ForEach(Array(agenda.timed.enumerated()), id: \.element.id) { index, event in
                    if index == agenda.nowLineIndex { NowLine(now: now) }
                    CalendarEventRow(event: event, now: now, isNext: event.id == agenda.nextEventId, actions: actions)
                }
                if agenda.nowLineIndex == agenda.timed.count { NowLine(now: now) }
            }
        }
    }
}

/// "9:30 AM ▌ Daily standup / 15 min · Work   in 5m [Join]". A meeting in progress fills with its color as it goes;
/// ended ones fade back.
struct CalendarEventRow: View {
    let event: CalendarEvent
    let now: Date
    let isNext: Bool
    let actions: IslandActions
    @State private var isHovered = false

    private var color: Color { Color(hex: event.colorHex) }

    private var detail: String {
        event.calendarTitle.isEmpty ? event.durationText : "\(event.durationText) · \(event.calendarTitle)"
    }

    var body: some View {
        let isOngoing = event.isOngoing(now: now)
        let hasEnded = event.hasEnded(now: now)
        HStack(spacing: 10) {
            Text(verbatim: event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundColor(isOngoing ? Palette.text : Palette.secondary)
                .frame(width: 58, alignment: .trailing)
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.text)
                Text(verbatim: detail).font(.system(size: 10.5)).foregroundColor(Palette.tertiary)
            }
            Spacer(minLength: 4)
            if isOngoing {
                Text(verbatim: "now").font(.system(size: 11, weight: .semibold)).foregroundColor(color)
            } else if isNext {
                Text(verbatim: event.countdownText(now: now)).font(.system(size: 11)).foregroundColor(Palette.secondary)
            }
            if event.joinURL != nil && !hasEnded {
                BannerButton(title: "Join") { actions.join(event) }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: IslandLayout.calendarEventHeight - 4)
        .background(background(progress: isOngoing ? event.progress(now: now) : 0))
        .opacity(hasEnded ? 0.45 : 1)
        .padding(.bottom, 4)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
    }

    private func background(progress: Double) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(isHovered ? 0.07 : 0.035))
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle().fill(color.opacity(0.2)).frame(width: geometry.size.width * progress)
                        .animation(.easeInOut(duration: 0.8), value: progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// "9:25 AM ●──────" in red, lined up with the event color bars.
struct NowLine: View {
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9.5, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundColor(Palette.danger)
                .frame(width: 58, alignment: .trailing)
            Circle().fill(Palette.danger).frame(width: 6, height: 6)
            Capsule().fill(Palette.danger).frame(height: 1.5)
        }
        .padding(.horizontal, 10)
        .frame(height: IslandLayout.calendarNowLineHeight)
    }
}

struct AllDayChips: View {
    let events: [CalendarEvent]

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: "All day").font(.system(size: 10.5, weight: .medium)).foregroundColor(Palette.tertiary)
                .frame(width: 58, alignment: .trailing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(events) { event in
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: event.colorHex)).frame(width: 6, height: 6)
                            Text(verbatim: event.title).font(.system(size: 11)).foregroundColor(Palette.text)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: event.colorHex).opacity(0.16))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: IslandLayout.calendarAllDayHeight - 4)
        .padding(.bottom, 4)
    }
}

struct EmptyDayRow: View {
    let hasAllDayEvents: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hasAllDayEvents ? "checkmark.circle" : "sun.max").font(.system(size: 12))
            Text(verbatim: hasAllDayEvents ? "No meetings" : "Nothing planned").font(.system(size: 12))
        }
        .foregroundColor(Palette.tertiary)
        .padding(.leading, 78)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: IslandLayout.calendarEventHeight)
    }
}

/// Shown instead of the calendar until macOS allows m_notch to read it.
struct CalendarAccessNote: View {
    let access: CalendarAccess
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(access == .notAsked ? "Waiting for the Calendars permission" : "m_notch can't read your calendars",
                  systemImage: "calendar.badge.exclamationmark")
                .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Palette.text)
            Text(verbatim: "Allow m_notch in System Settings > Privacy & Security > Calendars.")
                .font(.system(size: 11.5)).foregroundColor(Palette.secondary)
            if access == .denied {
                PillButton(title: "Open System Settings…") {
                    openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
