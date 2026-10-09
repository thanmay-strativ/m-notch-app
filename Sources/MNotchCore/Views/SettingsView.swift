// Header and quick-settings layout ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import AppKit
import SwiftUI

/// Top band of the open island: sessions and calendar tabs and plan usage on the left, settings gear always on the right.
struct IslandHeader: View {
    let model: IslandModel
    let store: SessionStore
    let preferences: Preferences
    let status: AppStatus
    let actions: IslandActions

    private var isShowingRequest: Bool { IslandLayout.shownRequest(model: model, store: store) != nil }

    private var isShowingPanel: Bool { model.showingSettings || isShowingRequest }

    private var showsMusicTab: Bool { preferences.showNowPlaying && model.nowPlaying != nil }

    private var leftZoneWidth: CGFloat {
        let extraTabsWidth = CGFloat((preferences.showCalendar ? 1 : 0) + (showsMusicTab ? 1 : 0)) * 38
        return model.hasNotch ? (IslandLayout.expandedWidth - model.notchWidth) / 2 - 58 - extraTabsWidth : 300
    }

    var body: some View {
        HStack(spacing: 8) {
            HeaderTab(icon: "house.fill", isOn: !isShowingPanel && !model.showingCalendar && !model.showingMusic) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    model.showingSettings = false
                    model.showingCalendar = false
                    model.showingMusic = false
                    model.openDiff = nil
                    if !store.pending.isEmpty { model.requestsHidden = true }
                }
            }
            .padding(.leading, 14)
            if preferences.showCalendar {
                HeaderTab(icon: "calendar", isOn: !isShowingPanel && model.showingCalendar) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { actions.showCalendar() }
                }
            }
            if showsMusicTab {
                HeaderTab(icon: "music.note", isOn: !isShowingPanel && model.showingMusic) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { actions.showMusic() }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if (model.showingSettings || model.requestsHidden) && !store.pending.isEmpty {
                HeaderPill(title: "\(store.pending.count) waiting", color: Palette.needsYou) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.showingSettings = false
                        model.requestsHidden = false
                    }
                }
            } else if preferences.showPlanUsage, let plan = store.planUsage {
                PlanPills(plan: plan).frame(maxWidth: leftZoneWidth, alignment: .leading)
            }
            Spacer(minLength: 0)
            if status.needsHookInstall && !model.showingSettings {
                HeaderPill(title: "Install hooks", color: Palette.needsYou) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.showingSettings = true }
                }
            }
            HeaderTab(icon: model.showingSettings ? "gearshape.fill" : "gearshape", isOn: model.showingSettings) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.showingSettings.toggle() }
            }
            .padding(.trailing, 12)
        }
    }
}

/// "5h 39% · 2h 33m" and "7d 37% · 4d 12h", green, then yellow at 50%, red at 80%.
struct PlanPills: View {
    let plan: PlanUsage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ViewThatFits(in: .horizontal) {
                pills(now: context.date, withCountdown: true)
                pills(now: context.date, withCountdown: false)
            }
        }
    }

    private func pills(now: Date, withCountdown: Bool) -> some View {
        HStack(spacing: 5) {
            if let fiveHour = plan.fiveHour { pill("5h", fiveHour, now: now, withCountdown: withCountdown) }
            if let sevenDay = plan.sevenDay { pill("7d", sevenDay, now: now, withCountdown: withCountdown) }
        }
    }

    private func pill(_ label: String, _ window: PlanWindow, now: Date, withCountdown: Bool) -> some View {
        let isExpired = window.resetsAt <= now
        let percent = isExpired ? 0 : Int(window.usedPercent.rounded())
        let color = StatsStyle.color(forPercent: percent, otherwise: Palette.done)
        let countdown = withCountdown && !isExpired ? " · \(StatsFormat.duration(window.resetsAt.timeIntervalSince(now)))" : ""
        return Text(verbatim: "\(label) \(percent)%\(countdown)")
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
            .fixedSize()
    }
}

struct HeaderTab: View {
    let icon: String
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? Palette.text : (isHovered ? Color(hex: "#B0B5BE") : Palette.secondary))
                .frame(width: 30, height: 22)
                .background(isOn ? Color(hex: "#1D1F23") : (isHovered ? Color.white.opacity(0.07) : Color.clear))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct HeaderPill: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.16))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The card behind the gear: the settings you change most, plus a door to the full settings window.
struct QuickSettingsView: View {
    let preferences: Preferences
    let status: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickRow(icon: "timer", label: "Close after") {
                ForEach(Preferences.closeDelayChoices, id: \.self) { delay in
                    ChoiceChip(title: delay < 1 ? "0.5s" : "\(Int(delay))s", isOn: preferences.closeDelay == delay) {
                        preferences.closeDelay = delay
                    }
                }
            }
            QuickRow(icon: "capsule", label: "Stay small") {
                ForEach(preferences.compactHoldOptions, id: \.self) { seconds in
                    ChoiceChip(title: "\(Int(seconds))s", isOn: preferences.compactHold == seconds) {
                        preferences.compactHold = seconds
                    }
                }
            }
            QuickRow(icon: "switch.2", label: "Behavior") {
                ChoiceChip(title: "Open on hover", isOn: preferences.openOnHover) { preferences.openOnHover.toggle() }
                ChoiceChip(title: "Keep awake", isOn: preferences.keepAwake) { preferences.keepAwake.toggle() }
                ChoiceChip(title: "Sounds", isOn: preferences.soundsEnabled) { preferences.soundsEnabled.toggle() }
                ChoiceChip(title: "Stats", isOn: preferences.showSessionStats) { preferences.showSessionStats.toggle() }
            }
            QuickRow(icon: "face.smiling", label: "Character") {
                ForEach(CharacterDesign.allCases, id: \.self) { design in
                    ChoiceChip(title: design.title, isOn: preferences.character == design) { preferences.character = design }
                }
            }
            QuickRow(icon: "paintpalette", label: "Color") {
                ForEach(Preferences.CharacterColor.allCases, id: \.self) { color in
                    ColorSwatch(color: color, isOn: preferences.characterColor == color) { preferences.characterColor = color }
                }
            }
            QuickRow(icon: "checkmark.seal", label: "Status") {
                StatusBadge(label: "Claude", isOk: status.hookStatuses[.claude] == .installed)
                StatusBadge(label: "Stats relay", isOk: status.statusLineStatus == .installed)
                StatusBadge(label: "Codex", isOk: status.hookStatuses[.codex] == .installed)
                if status.needsHookInstall {
                    PillButton(title: "Install hooks…", style: .primary) { status.installHooks(.claude) }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                PillButton(title: "Settings…") { status.openSettingsWindow() }
                PillButton(title: "Quit") { NSApp.terminate(nil) }
            }
        }
        .font(.system(size: 11.5))
    }
}

struct QuickRow<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(Palette.secondary).frame(width: 16)
            Text(verbatim: label).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Palette.text)
                .frame(width: 72, alignment: .leading)
            content()
        }
        .frame(height: 24)
    }
}

struct ChoiceChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isOn ? Color(hex: "#0B0C0E") : Palette.text)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(isOn ? Palette.text : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ColorSwatch: View {
    let color: Preferences.CharacterColor
    let isOn: Bool
    var size: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: color.gradientHex.top), Color(hex: color.gradientHex.bottom)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Palette.text, lineWidth: isOn ? 2 : 0).padding(-size * 0.19))
        }
        .buttonStyle(.plain)
        .help(color.title)
    }
}

struct StatusBadge: View {
    let label: String
    let isOk: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(isOk ? Palette.done : Palette.danger).frame(width: 6, height: 6)
            Text(verbatim: label).font(.system(size: 11)).foregroundColor(Palette.secondary)
        }
    }
}
