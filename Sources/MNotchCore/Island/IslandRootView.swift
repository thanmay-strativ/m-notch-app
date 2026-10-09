// Structure and animation values ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import SwiftUI

/// Fills the transparent 720 x 560 panel; the island hangs from the top center.
struct IslandRootView: View {
    let model: IslandModel
    let store: SessionStore
    let preferences: Preferences
    let status: AppStatus
    let actions: IslandActions

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(model: model, store: store, preferences: preferences, status: status, actions: actions)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, .leftToRight)
    }
}

enum IslandAnimation {
    static let open = Animation.spring(response: 0.5, dampingFraction: 0.72)
    static let close = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
    static let contentIn = Animation.spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
    static let contentOut = Animation.easeIn(duration: 0.16)
    static let calendarSwitch = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

struct IslandContainer: View {
    let model: IslandModel
    let store: SessionStore
    let preferences: Preferences
    let status: AppStatus
    let actions: IslandActions

    @State private var islandWidth: CGFloat = IslandScreenGeometry.fallbackNotchWidth
    @State private var islandHeight: CGFloat = 32
    @State private var cornerRadius: CGFloat = IslandLayout.compactCorner
    @State private var bounceOffset: CGFloat = 0

    private enum Layer: Hashable { case list, request, diff, settings, calendar, music }

    private var openDiff: (FileDiff, Session)? { IslandLayout.openDiff(model: model, store: store) }

    private var activeLayer: Layer {
        if model.showingSettings { return .settings }
        if IslandLayout.shownRequest(model: model, store: store) != nil { return .request }
        if model.showingCalendar { return .calendar }
        if model.showingMusic && model.nowPlaying != nil { return .music }
        return openDiff == nil ? .list : .diff
    }

    private var targetSize: CGSize { IslandLayout.currentSize(model: model, store: store) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius)
                .fill(Color.black)
                .opacity(model.mode == .hidden && !model.hasNotch ? 0 : 1)

            if model.mode == .expanded {
                expandedContentView
                    .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
                    .clipShape(IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius))
                    .transition(.opacity)
                IslandHeader(model: model, store: store, preferences: preferences, status: status, actions: actions)
                    .frame(width: islandWidth, height: IslandLayout.headerHeight(notchHeight: model.notchHeight))
                    .transition(.opacity)
            }

            Group {
                if model.mode == .compact {
                    CompactStatusView(store: store)
                        .position(x: islandWidth - IslandLayout.compactEarWidth / 2, y: islandHeight / 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.mode == .compact)

            if preferences.showCharacter {
                BotPlacementView(model: model, preferences: preferences, islandSize: CGSize(width: islandWidth, height: islandHeight))
            }
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .offset(y: bounceOffset)
        .onChange(of: model.mode) { oldMode, newMode in
            let target = targetSize
            withAnimation(newMode < oldMode ? IslandAnimation.close : IslandAnimation.open) {
                islandWidth = target.width
                islandHeight = target.height
                cornerRadius = newMode == .expanded ? IslandLayout.expandedCorner : IslandLayout.compactCorner
            }
        }
        .onChange(of: targetSize) { _, newSize in
            guard model.mode == .expanded else { return }
            withAnimation(IslandAnimation.open) {
                islandWidth = newSize.width
                islandHeight = newSize.height
            }
        }
        .onChange(of: CGSize(width: model.notchWidth, height: model.notchHeight)) { _, _ in
            let target = targetSize
            islandWidth = target.width
            islandHeight = target.height
        }
        .onChange(of: model.bounceCount) { _, _ in bounce() }
        .onAppear {
            let target = targetSize
            islandWidth = target.width
            islandHeight = target.height
            cornerRadius = model.mode == .expanded ? IslandLayout.expandedCorner : IslandLayout.compactCorner
        }
    }

    @ViewBuilder private var expandedContentView: some View {
        let top = IslandLayout.contentTop(notchHeight: model.notchHeight)
        ZStack(alignment: .topLeading) {
            layer(.list) { SessionListView(store: store, preferences: preferences, model: model, actions: actions) }
            layer(.request) { requestCard }
            layer(.diff) {
                if let open = openDiff { DiffView(diff: open.0, session: open.1, actions: actions) }
            }
            layer(.settings) { QuickSettingsView(preferences: preferences, status: status) }
            if preferences.showCalendar {
                layer(.calendar) { CalendarView(model: model, status: status, actions: actions) }
            }
            if preferences.showNowPlaying {
                layer(.music) { NowPlayingView(model: model, actions: actions) }
            }
        }
        .padding(.top, top)
        .padding(.leading, preferences.showCharacter ? IslandLayout.contentLeading : 16)
        .padding(.trailing, 14)
        .padding(.bottom, 12)
    }

    /// Every layer takes exactly the island's content size. With only a maximum, a hidden layer taller than the
    /// island (quick settings) would grow the stack, and the shown card would center itself below the visible area.
    private func layer<Content: View>(_ kind: Layer, @ViewBuilder content: () -> Content) -> some View {
        let isActive = activeLayer == kind
        return content()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .opacity(isActive ? 1 : 0)
            .scaleEffect(isActive ? 1 : 0.97)
            .allowsHitTesting(isActive)
            .animation(isActive ? IslandAnimation.contentIn : IslandAnimation.contentOut, value: activeLayer)
    }

    @ViewBuilder private var requestCard: some View {
        if let request = IslandLayout.focusedRequest(model: model, store: store) {
            let session = store.session(for: request)
            let position = (store.pending.firstIndex { $0.id == request.id } ?? 0) + 1
            let counter = store.pending.count > 1 ? "\(position) of \(store.pending.count)" : nil
            Group {
                switch request.kind {
                case .permission:
                    ApprovalCardView(request: request, session: session, counter: counter, actions: actions)
                case .plan(let plan):
                    PlanCardView(request: request, plan: plan, session: session, counter: counter, actions: actions)
                case .question(let question):
                    QuestionCardView(request: request, question: question, session: session, counter: counter,
                                     model: model, actions: actions)
                }
            }
            .id(request.id)
            .transition(.opacity)
        }
    }

    private func bounce() {
        withAnimation(.easeOut(duration: 0.12)) { bounceOffset = 7 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { bounceOffset = 0 }
        }
    }
}

/// Right ear of the compact island: a terminal command result for a minute after it ends,
/// otherwise one dot per session (orange when one needs you).
struct CompactStatusView: View {
    static let commandFreshness: TimeInterval = 60
    let store: SessionStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let command = store.finishedCommand,
               context.date.timeIntervalSince(command.finishedAt) < Self.commandFreshness {
                earLabel(icon: command.succeeded ? "checkmark" : "xmark", text: command.durationText,
                         color: command.succeeded ? Palette.done : Palette.danger)
            } else {
                sessionDots
            }
        }
    }

    private var sessionDots: some View {
        let sessions = Array(store.sortedSessions.prefix(4))
        return HStack(spacing: 4) {
            if sessions.isEmpty {
                Circle().fill(Palette.tertiary).frame(width: 6, height: 6)
            }
            ForEach(sessions) { session in
                StatusDot(state: session.state)
            }
            if !store.pending.isEmpty {
                Text(verbatim: "\(store.pending.count)")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(Palette.needsYou)
            }
        }
    }

    private func earLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(verbatim: text).font(.system(size: 10.5, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// The character, its glow, and where it sits for each mode.
struct BotPlacementView: View {
    let model: IslandModel
    let preferences: Preferences
    let islandSize: CGSize
    private let overhang: CGFloat = 40

    var body: some View {
        let placement = IslandLayout.botPlacement(mode: model.mode, islandSize: islandSize,
                                                  notchHeight: model.notchHeight, hasNotch: model.hasNotch)
        let canvasSize = placement.diameter / 0.6
        ZStack {
            if model.mode == .expanded && preferences.showGlow {
                Circle()
                    .fill(RadialGradient(gradient: Gradient(stops: [.init(color: glowColor, location: 0), .init(color: .clear, location: 0.62)]),
                                         center: .center, startRadius: 0, endRadius: placement.diameter * 1.1))
                    .frame(width: placement.diameter * 2.2, height: placement.diameter * 2.2)
                    .blur(radius: 6)
                    .opacity(model.botState == .idle ? 0.15 : 0.65)
                    .position(placement.center)
                    .animation(.easeInOut(duration: 0.4), value: model.botState)
            }
            BotCanvasView(model: model, preferences: preferences, particleOverhang: overhang)
                .frame(width: canvasSize, height: canvasSize + overhang)
                .opacity(placement.opacity)
                .position(x: placement.center.x, y: placement.center.y - overhang / 2)
                .animation(IslandAnimation.open, value: placement)
        }
        .allowsHitTesting(false)
    }

    private var glowColor: Color {
        switch model.botState {
        case .working: return Palette.working
        case .thinking: return Palette.thinking
        case .approval, .question: return Palette.needsYou
        case .error: return Palette.danger
        case .finished: return Palette.done
        default: return .white
        }
    }
}

extension IslandLayout {
    @MainActor
    static func openDiff(model: IslandModel, store: SessionStore) -> (FileDiff, Session)? {
        guard let target = model.openDiff, let session = store.sessions[target.sessionId],
              let diff = session.diffs.first(where: { $0.id == target.diffId }) else { return nil }
        return (diff, session)
    }

    @MainActor
    static func focusedRequest(model: IslandModel, store: SessionStore) -> PendingRequest? {
        store.pending.first { $0.id == model.focusedRequestId } ?? store.pending.first
    }

    @MainActor
    static func shownRequest(model: IslandModel, store: SessionStore) -> PendingRequest? {
        model.requestsHidden ? nil : focusedRequest(model: model, store: store)
    }

    @MainActor
    static func expandedContent(model: IslandModel, store: SessionStore) -> ExpandedContent {
        if model.showingSettings { return .settings }
        if let request = shownRequest(model: model, store: store) {
            switch request.kind {
            case .permission:
                return .permission(commandLines: wrappedLineCount(request.summary), hasRisk: request.risk != nil)
            case .question(let question): return .question(estimatedHeight: question.estimatedHeight)
            case .plan: return .plan
            }
        }
        if model.showingCalendar {
            let agenda = DayAgenda(day: model.calendarDay, events: model.weekEvents, now: Date())
            return .calendar(timedEvents: agenda.timed.count, hasAllDay: !agenda.allDay.isEmpty,
                             hasNowLine: agenda.nowLineIndex != nil)
        }
        if model.showingMusic && model.nowPlaying != nil { return .music }
        let banners = (model.nextMeeting == nil ? 0 : 1) + (store.finishedCommand == nil ? 0 : 1) + (model.nowPlaying == nil ? 0 : 1)
        return openDiff(model: model, store: store) == nil
            ? .list(rows: store.sessions.count, rowHeight: model.rowHeight, banners: banners) : .diff
    }

    @MainActor
    static func currentSize(model: IslandModel, store: SessionStore) -> CGSize {
        size(mode: model.mode, notchWidth: model.notchWidth, notchHeight: model.notchHeight,
             expandedHeight: expandedHeight(for: expandedContent(model: model, store: store), notchHeight: model.notchHeight))
    }
}
