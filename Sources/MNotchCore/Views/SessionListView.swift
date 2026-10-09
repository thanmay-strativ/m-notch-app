import SwiftUI

/// Every live session, "needs you" first, below the playing track, the next meeting and the last long terminal command.
/// A click opens the session's waiting request, or switches to its IDE when nothing waits.
struct SessionListView: View {
    let store: SessionStore
    let preferences: Preferences
    let model: IslandModel
    let actions: IslandActions

    var body: some View {
        VStack(spacing: 4) {
            if let track = model.nowPlaying {
                NowPlayingRow(track: track, actions: actions)
            }
            if let meeting = model.nextMeeting {
                MeetingRow(meeting: meeting, actions: actions)
            }
            if let command = store.finishedCommand {
                FinishedCommandRow(command: command, actions: actions)
            }
            sessionList
        }
    }

    @ViewBuilder private var sessionList: some View {
        let sessions = store.sortedSessions
        if sessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "No sessions yet").font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.text)
                Text(verbatim: "Start Claude Code in PyCharm or VS Code. If nothing shows up, open settings (the gear, top right) and install the Claude hooks.")
                    .font(.system(size: 11.5)).foregroundColor(Palette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(sessions) { session in
                        SessionRowView(session: session, preferences: preferences, rowHeight: model.rowHeight, actions: actions)
                    }
                }
            }
        }
    }
}

struct SessionRowView: View {
    let session: Session
    let preferences: Preferences
    let rowHeight: CGFloat
    let actions: IslandActions
    @State private var isHovering = false

    private var statusLabel: String {
        switch session.state {
        case .thinking: return "thinking"
        case .working: return "working"
        case .needsYou: return "needs you"
        case .done: return "done"
        }
    }

    private var detail: String {
        session.state == .done ? session.finishedLine : session.stepText
    }

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(state: session.state)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: session.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.text)
                    Text(verbatim: "\(session.agent.displayName) · \(session.host.displayName)")
                        .font(.system(size: 11)).foregroundColor(Palette.tertiary)
                    Spacer(minLength: 4)
                    if !preferences.showSessionStats, let percent = session.contextPercent {
                        Text(verbatim: "ctx \(percent)%")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(StatsStyle.color(forPercent: percent, otherwise: Palette.tertiary))
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(verbatim: "\(statusLabel) · \(RelativeAge.text(since: session.lastChange, now: context.date))")
                            .font(.system(size: 11)).foregroundColor(Palette.color(for: session.state))
                    }
                }
                HStack(spacing: 6) {
                    Text(verbatim: detail.isEmpty ? " " : detail)
                        .font(.system(size: 11)).foregroundColor(Palette.secondary)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if preferences.showDiffChips, let diff = session.diffs.last {
                        Button { actions.showDiff(diff, in: session) } label: {
                            Text(verbatim: "\(diff.fileName) +\(diff.added) -\(diff.removed)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.white.opacity(0.07)).clipShape(Capsule())
                                .foregroundColor(Palette.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if preferences.showSessionStats {
                    SessionStatsLine(session: session)
                }
            }
            .lineLimit(1)
            Button { actions.jump(to: session) } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color(hex: "#5F646D"))
                    .frame(width: 16, height: 16)
                    .background(Color.white.opacity(isHovering ? 0.14 : 0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Switch to \(session.host.displayName)")
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight - 4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(isHovering ? 0.07 : 0.035)))
        .contentShape(Rectangle())
        .onTapGesture { actions.showRequestOrJump(to: session) }
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovering = hovering }
        }
    }
}

/// "Standup  10:30 to 11:00 · in 5m  [Join]", shown while a meeting starts within the hour. A click opens the calendar tab.
struct MeetingRow: View {
    let meeting: CalendarEvent
    let actions: IslandActions

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: meeting.colorHex)).frame(width: 3, height: 16)
                Text(verbatim: meeting.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.text)
                Text(verbatim: meeting.timeRangeText).font(.system(size: 11)).foregroundColor(Palette.tertiary)
                Spacer(minLength: 4)
                Text(verbatim: meeting.countdownText(now: context.date))
                    .font(.system(size: 11)).foregroundColor(Palette.secondary)
                if meeting.joinURL != nil {
                    BannerButton(title: "Join") { actions.join(meeting) }
                }
            }
            .bannerStyle()
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { actions.showCalendar() } }
        }
    }
}

/// "✓ pytest -x  web-app   done in 2m 10s · 1m  ×", shown for 10 minutes after a long terminal command ends.
struct FinishedCommandRow: View {
    let command: FinishedCommand
    let actions: IslandActions

    private var outcome: String {
        command.succeeded ? "done in \(command.durationText)" : "failed (exit \(command.exitCode)) after \(command.durationText)"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                Image(systemName: command.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(command.succeeded ? Palette.done : Palette.danger)
                Text(verbatim: command.command)
                    .font(.system(size: 11.5, design: .monospaced)).foregroundColor(Palette.text)
                    .truncationMode(.middle)
                Text(verbatim: command.folder).font(.system(size: 11)).foregroundColor(Palette.tertiary).layoutPriority(1)
                Spacer(minLength: 4)
                Text(verbatim: "\(outcome) · \(RelativeAge.text(since: command.finishedAt, now: context.date))")
                    .font(.system(size: 11))
                    .foregroundColor(command.succeeded ? Palette.secondary : Palette.danger)
                    .layoutPriority(1)
                Button { actions.dismissFinishedCommand() } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(Palette.tertiary)
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.07)).clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Hide")
            }
            .bannerStyle()
        }
    }
}

struct BannerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#0B0C0E"))
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(Palette.text)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// One-line row above the session list, `IslandLayout.bannerHeight` tall with its spacing.
    func bannerStyle() -> some View {
        lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: IslandLayout.bannerHeight - 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
    }
}

struct StatusDot: View {
    let state: SessionState
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Palette.color(for: state))
            .frame(width: 7, height: 7)
            .scaleEffect(isPulsing && state == .needsYou ? 1.35 : 1)
            .opacity(isPulsing && state == .working ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isPulsing = true }
            }
    }
}

/// "Opus 5.5 · ctx 465k/1000k · tools 150 · up 1h 05m", the numbers from the Claude status line.
struct SessionStatsLine: View {
    let session: Session

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                if let model = session.modelName { stat(model, color: Palette.secondary) }
                if let used = session.contextUsed, let window = session.contextWindow {
                    stat("ctx \(StatsFormat.tokens(used))/\(StatsFormat.tokens(window))",
                         color: StatsStyle.color(forPercent: session.contextPercent ?? 0, otherwise: Palette.tertiary))
                }
                stat("tools \(session.toolCount)", color: Palette.tertiary)
                stat("up \(StatsFormat.duration(context.date.timeIntervalSince(session.startedAt)))", color: Palette.tertiary)
            }
        }
    }

    private func stat(_ text: String, color: Color) -> some View {
        Text(verbatim: text).font(.system(size: 10.5, design: .monospaced)).foregroundColor(color)
    }
}

enum StatsStyle {
    static func color(forPercent percent: Int, otherwise: Color) -> Color {
        if percent >= 80 { return Palette.danger }
        if percent >= 50 { return Palette.needsYou }
        return otherwise
    }
}
