// Ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import Foundation

/// hidden / compact / expanded. When the pointer leaves, the island settles back to its resting size
/// after `leaveDelay`: compact while an agent is busy, just showed activity, or for `compactHold` after the
/// pointer left; hidden otherwise.
@MainActor
public final class IslandStateMachine {
    public enum State: Int, Comparable, Sendable {
        case hidden, compact, expanded

        public static func < (lhs: State, rhs: State) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public private(set) var state: State = .hidden
    public var onTransition: ((State, State) -> Void)?
    public var isHeldOpen: () -> Bool = { false }
    public var isBusy: () -> Bool = { false }
    public var now: () -> Date = Date.init

    public var openOnHover = false
    public var leaveDelay: TimeInterval = 0.5
    public var activityHold: TimeInterval = 60
    public var compactHold: TimeInterval = 5
    static let busyRecheck: TimeInterval = 10

    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var settleWork: DispatchWorkItem?
    private var compactUntil = Date.distantPast
    private var isPointerInside = false

    public init(schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
    }) {
        self.schedule = schedule
    }

    public var restingState: State {
        if isHeldOpen() { return .expanded }
        return isBusy() || now() < compactUntil ? .compact : .hidden
    }

    public func mouseEntered() {
        isPointerInside = true
        cancelSettle()
        switch state {
        case .hidden: transition(to: openOnHover ? .expanded : .compact)
        case .compact: if openOnHover { transition(to: .expanded) }
        case .expanded: break
        }
    }

    public func mouseLeft() {
        isPointerInside = false
        holdCompact(for: leaveDelay + compactHold)
        scheduleSettle(after: leaveDelay)
    }

    public func click() {
        guard state != .expanded else { return }
        cancelSettle()
        transition(to: .expanded)
    }

    public func toggle() {
        if state == .expanded && !isHeldOpen() {
            settle()
        } else {
            click()
            if !isPointerInside { scheduleSettle(after: max(leaveDelay, 3)) }
        }
    }

    public func reveal() {
        holdCompact(for: activityHold)
        guard state == .hidden else { return }
        transition(to: .compact)
        if !isPointerInside { scheduleSettle(after: activityHold) }
    }

    public func expand() {
        cancelSettle()
        transition(to: .expanded)
        if !isPointerInside { scheduleSettle(after: leaveDelay) }
    }

    public func settleSoon() {
        guard !isPointerInside else { return }
        scheduleSettle(after: leaveDelay)
    }

    private func settle() {
        let target = restingState
        if state != target { transition(to: target) }
        if target == .compact && !isPointerInside {
            let remaining = compactUntil.timeIntervalSince(now())
            scheduleSettle(after: isBusy() ? Self.busyRecheck : max(remaining, 0.1))
        }
    }

    private func holdCompact(for duration: TimeInterval) {
        compactUntil = max(compactUntil, now().addingTimeInterval(duration))
    }

    private func scheduleSettle(after delay: TimeInterval) {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isPointerInside else { return }
                self.settle()
            }
        }
        settleWork = work
        schedule(delay, work)
    }

    private func cancelSettle() {
        settleWork?.cancel()
        settleWork = nil
    }

    private func transition(to newState: State) {
        guard newState != state else { return }
        let oldState = state
        state = newState
        onTransition?(oldState, newState)
    }
}
