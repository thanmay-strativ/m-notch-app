// Panel setup, polling and click handling ported from coucou (https://github.com/Louis-CFM/coucou),
// MIT License, Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import AppKit
import SwiftUI

/// Borderless, non-activating panel that may sit over the menu bar and the notch.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Delivers the first click to SwiftUI even though the panel never becomes key or active.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the island window: placement, hover and clicks, the state machine and reactions to hook events.
@MainActor
final class IslandController {
    static let fastPoll: TimeInterval = 1.0 / 60.0
    static let idlePoll: TimeInterval = 1.0 / 8.0
    static let celebrateDuration: TimeInterval = 5.2

    let model: IslandModel
    let store: SessionStore
    let preferences: Preferences
    let status: AppStatus
    let keepAwake = KeepAwake()
    private let calendar = CalendarWatcher()
    private let nowPlaying = NowPlayingWatcher()
    private let actions: IslandActions
    private let hotKeys = HotKeys()
    private let machine = IslandStateMachine()
    private let panel: IslandPanel
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private var currentScreen: NSScreen?
    private var isPointerInside = false
    private var pendingClick = false
    private var celebrateUntil = Date.distantPast
    private var celebrateState: BotState = .finished
    private var botHoverStart: Date?
    private var lastLoveAt = Date.distantPast
    private var lastPendingCount = 0
    private var appliedDisplayChoice: IslandDisplayChoice

    init(store: SessionStore, model: IslandModel, preferences: Preferences, status: AppStatus) {
        self.store = store
        self.model = model
        self.preferences = preferences
        self.status = status
        self.actions = IslandActions(store: store, model: model, preferences: preferences)
        self.appliedDisplayChoice = preferences.displayChoice
        let panelSize = IslandLayout.panelSize
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configurePanel()
        wireStateMachine()
        wireStore()
        wireCalendar()
        wireNowPlaying()
        wireHotKeys()
        installMouseMonitors()
        relocate(to: appliedDisplayChoice.targetScreen())
        panel.orderFrontRegardless()
        startPolling(interval: Self.fastPoll)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.relocate(to: self.appliedDisplayChoice.targetScreen())
            }
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        let hosting = FirstClickHostingView(rootView: IslandRootView(model: model, store: store, preferences: preferences,
                                                                     status: status, actions: actions))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: IslandLayout.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    private func relocate(to screen: NSScreen?) {
        guard let screen else { return }
        let geometry = IslandScreenGeometry(screen: screen)
        model.notchWidth = geometry.width
        model.notchHeight = geometry.height
        model.hasNotch = geometry.hasNotch
        currentScreen = screen
        let frame = screen.frame
        let size = IslandLayout.panelSize
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func followMouseIfNeeded(_ mouse: NSPoint) {
        guard appliedDisplayChoice == .followMouse, model.mode != .expanded else { return }
        if let currentScreen, currentScreen.frame.contains(mouse) { return }
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), target != currentScreen else { return }
        relocate(to: target)
    }

    // MARK: - State machine and hook signals

    private func wireStateMachine() {
        machine.isHeldOpen = { [weak self] in
            guard let self else { return false }
            return !self.store.pending.isEmpty && !self.model.requestsHidden
        }
        machine.isBusy = { [weak self] in
            guard let self else { return false }
            return self.store.isAnySessionBusy || !self.store.pending.isEmpty
        }
        machine.onTransition = { [weak self] oldState, newState in
            guard let self else { return }
            withAnimation(newState < oldState ? IslandAnimation.close : IslandAnimation.open) {
                self.model.mode = newState
            }
            if newState != .expanded {
                self.model.openDiff = nil
                self.model.showingSettings = false
                self.model.showingCalendar = false
                self.model.showingMusic = false
            }
        }
    }

    private func wireStore() {
        store.onSignal = { [weak self] signal in self?.handle(signal) }
        let tickTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.tick() }
        }
        tickTimer.tolerance = 1
        RunLoop.main.add(tickTimer, forMode: .common)
    }

    private func wireCalendar() {
        status.calendarAccess = CalendarAccess.current
        calendar.onAccessChange = { [weak self] access in self?.status.calendarAccess = access }
        calendar.onNextMeeting = { [weak self] meeting in self?.model.nextMeeting = meeting }
        calendar.onWeekEvents = { [weak self] events in self?.model.weekEvents = events }
    }

    private func wireNowPlaying() {
        nowPlaying.onChange = { [weak self] track in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                self.model.nowPlaying = track
                if track == nil { self.model.showingMusic = false }
            }
        }
        actions.onMediaCommand = { [weak self] command in self?.nowPlaying.send(command) }
    }

    private func handle(_ signal: StoreSignal) {
        switch signal {
        case .activity(let sessionId):
            guard preferences.revealOnActivity, let session = store.sessions[sessionId], !isQuiet(for: session) else { return }
            machine.reveal()
        case .finished(let sessionId):
            celebrate(as: .finished)
            if preferences.soundsEnabled { SoundPlayer.play(preferences.finishedSound, volume: preferences.soundVolume) }
            guard preferences.revealOnFinish, let session = store.sessions[sessionId], !isQuiet(for: session) else { return }
            machine.reveal()
        case .requestsChanged:
            if store.pending.count > lastPendingCount {
                model.showingSettings = false
                model.requestsHidden = false
                if preferences.soundsEnabled { SoundPlayer.play(preferences.needsYouSound, volume: preferences.soundVolume) }
            }
            lastPendingCount = store.pending.count
            if !store.pending.isEmpty && !model.requestsHidden {
                if machine.state != .expanded { machine.expand() }
            } else {
                machine.settleSoon()
            }
        case .nudge:
            guard preferences.nudgeEnabled else { return }
            if machine.state == .hidden { machine.reveal() }
            model.bounce()
            model.emote(.surprised)
        case .commandFinished:
            guard let command = store.finishedCommand else { return }
            celebrate(as: command.succeeded ? .finished : .error)
            if preferences.soundsEnabled {
                SoundPlayer.play(command.succeeded ? preferences.finishedSound : preferences.needsYouSound,
                                 volume: preferences.soundVolume)
            }
            if preferences.revealOnFinish { machine.reveal() }
        }
    }

    private func celebrate(as state: BotState) {
        celebrateState = state
        celebrateUntil = Date().addingTimeInterval(Self.celebrateDuration)
    }

    private func isQuiet(for session: Session) -> Bool {
        preferences.quietWhenLooking && QuietMode.isLooking(at: session)
    }

    private func wireHotKeys() {
        hotKeys.onAction = { [weak self] action in
            guard let self else { return }
            if action == .toggleIsland {
                self.machine.toggle()
                return
            }
            guard let request = IslandLayout.shownRequest(model: self.model, store: self.store) else { return }
            switch (action, request.kind) {
            case (.allow, .permission), (.allow, .plan):
                self.actions.decide(request, .allow)
            case (.always, .permission):
                self.actions.decide(request, .always)
            case (.deny, .permission):
                self.actions.decide(request, .deny(message: HookReply.deniedMessage))
            case (.deny, .plan):
                self.actions.decide(request, .deny(message: HookReply.keepPlanningMessage))
            case (.option1, .question): self.model.pickOption(0)
            case (.option2, .question): self.model.pickOption(1)
            case (.option3, .question): self.model.pickOption(2)
            case (.option4, .question): self.model.pickOption(3)
            default: break
            }
        }
    }

    // MARK: - Mouse

    private func installMouseMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isPointerInside else { return }
                self.pendingClick = true
                if self.model.mode == .expanded && self.isBotHit(event.locationInWindow) { self.model.poke() }
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.pendingClick && self.model.mode != .expanded { self.machine.click() }
                self.pendingClick = false
            }
            return event
        }
    }

    private func startPolling(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = interval == Self.idlePoll ? 0.04 : 0
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func syncPreferences() {
        machine.openOnHover = preferences.openOnHover
        machine.leaveDelay = preferences.closeDelay
        machine.activityHold = preferences.activityHold
        machine.compactHold = preferences.compactHold
        keepAwake.isEnabled = preferences.keepAwake
        calendar.isEnabled = preferences.showCalendar
        calendar.shownWeek = CalendarWeek.interval(containing: model.calendarDay)
        if !preferences.showCalendar && model.showingCalendar { model.showingCalendar = false }
        nowPlaying.isEnabled = preferences.showNowPlaying
        let rowHeight = preferences.showSessionStats ? IslandLayout.rowHeightWithStats : IslandLayout.rowHeight
        if model.rowHeight != rowHeight { model.rowHeight = rowHeight }
        if preferences.displayChoice != appliedDisplayChoice {
            appliedDisplayChoice = preferences.displayChoice
            relocate(to: appliedDisplayChoice.targetScreen())
        }
    }

    private func poll() {
        syncPreferences()
        let mouse = NSEvent.mouseLocation
        followMouseIfNeeded(mouse)
        let panelFrame = panel.frame
        let local = CGPoint(x: mouse.x - panelFrame.minX, y: mouse.y - panelFrame.minY)
        let islandRect = currentIslandRect()
        let hoverRect = !model.hasNotch && model.mode != .expanded ? islandRect : islandRect.insetBy(dx: -6, dy: -6)
        let inside = hoverRect.contains(local)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside != isPointerInside {
            isPointerInside = inside
            inside ? machine.mouseEntered() : machine.mouseLeft()
        }
        updateLook(mouse: mouse)
        updateBotHover(local: local)
        refreshDerivedState()
        let nearIsland = panelFrame.insetBy(dx: -120, dy: -120).contains(mouse)
        let wanted = model.mode != .hidden || nearIsland ? Self.fastPoll : Self.idlePoll
        if wanted != pollInterval { startPolling(interval: wanted) }
    }

    private func currentIslandRect() -> CGRect {
        let size = IslandLayout.currentSize(model: model, store: store)
        let panelSize = IslandLayout.panelSize
        return CGRect(x: (panelSize.width - size.width) / 2, y: panelSize.height - size.height,
                      width: size.width, height: size.height)
    }

    private func botCenterInPanel() -> (CGPoint, CGFloat) {
        let islandRect = currentIslandRect()
        let placement = IslandLayout.botPlacement(mode: model.mode, islandSize: islandRect.size,
                                                  notchHeight: model.notchHeight, hasNotch: model.hasNotch)
        return (CGPoint(x: islandRect.minX + placement.center.x, y: IslandLayout.panelSize.height - placement.center.y),
                placement.diameter)
    }

    private func isBotHit(_ pointInPanel: CGPoint) -> Bool {
        let (center, diameter) = botCenterInPanel()
        return hypot(pointInPanel.x - center.x, pointInPanel.y - center.y) < diameter * 0.6
    }

    private func updateLook(mouse: NSPoint) {
        let (center, _) = botCenterInPanel()
        let botOnScreen = CGPoint(x: panel.frame.minX + center.x, y: panel.frame.minY + center.y)
        let origin = IslandLayout.lookOrigin(mode: model.mode, botOnScreen: botOnScreen,
                                             screenFrame: currentScreen?.frame ?? panel.frame)
        model.look = CGPoint(x: tanh((mouse.x - origin.x) / 260), y: tanh((mouse.y - origin.y) / 200))
    }

    private func updateBotHover(local: CGPoint) {
        let hovering = model.mode == .expanded && isBotHit(local)
        if hovering != model.botHovered { model.botHovered = hovering }
        guard hovering else {
            botHoverStart = nil
            return
        }
        let start = botHoverStart ?? Date()
        botHoverStart = start
        if Date().timeIntervalSince(start) > 1.9 && Date().timeIntervalSince(lastLoveAt) > 6 {
            lastLoveAt = Date()
            model.emote(.love)
        }
    }

    private func refreshDerivedState() {
        let state = currentBotState()
        if model.botState != state { model.botState = state }
        keepAwake.update(isBusy: store.isAnySessionBusy)
        hotKeys.update(requestKeys: preferences.shortcutsEnabled && !store.pending.isEmpty && !model.requestsHidden,
                       toggleKey: preferences.toggleIslandShortcut)
    }

    private func currentBotState() -> BotState {
        if let request = store.pending.first {
            if case .question = request.kind { return .question }
            return .approval
        }
        if Date() < celebrateUntil { return celebrateState }
        let states = Set(store.sessions.values.map(\.state))
        if states.contains(.needsYou) { return .question }
        if states.contains(.working) { return .working }
        if states.contains(.thinking) { return .thinking }
        return .idle
    }
}
