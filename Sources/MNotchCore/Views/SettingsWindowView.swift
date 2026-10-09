// Sidebar layout ported from coucou's Settings window (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import AppKit
import ApplicationServices
import SwiftUI

struct SettingsWindowView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General", appearance = "Appearance", agents = "Agents", extras = "Extras"
        case sounds = "Sounds", shortcuts = "Shortcuts", about = "About"

        var id: String { rawValue }

        var icon: (name: String, color: String) {
            switch self {
            case .general: return ("gearshape.fill", "#8E939C")
            case .appearance: return ("paintpalette.fill", "#E07950")
            case .agents: return ("terminal.fill", "#3B9EFF")
            case .extras: return ("calendar", "#F5A524")
            case .sounds: return ("speaker.wave.2.fill", "#34D399")
            case .shortcuts: return ("keyboard.fill", "#6366F1")
            case .about: return ("info.circle.fill", "#A78BFA")
            }
        }
    }

    let preferences: Preferences
    let status: AppStatus
    let store: SessionStore
    let setLaunchAtLogin: (Bool) -> Void
    @State var selection: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            List(Section.allCases, selection: $selection) { section in
                Label {
                    Text(verbatim: section.rawValue)
                } icon: {
                    Image(systemName: section.icon.name)
                        .foregroundColor(.white)
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: section.icon.color)))
                }
                .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: selection.rawValue).font(.title2).fontWeight(.semibold)
                    page
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder private var page: some View {
        @Bindable var preferences = preferences
        switch selection {
        case .general: generalPage(preferences: $preferences)
        case .appearance: appearancePage(preferences: $preferences)
        case .agents: agentsPage(preferences: $preferences)
        case .extras: extrasPage(preferences: $preferences)
        case .sounds: soundsPage(preferences: $preferences)
        case .shortcuts: shortcutsPage(preferences: $preferences)
        case .about: aboutPage(preferences: $preferences)
        }
    }

    private func generalPage(preferences: Bindable<Preferences>) -> some View {
        Group {
            GroupBox("Behavior") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Open the island on hover (not just peek)", isOn: preferences.openOnHover)
                    Picker("Go back to the previous size after the mouse leaves", selection: preferences.closeDelay) {
                        ForEach(Preferences.closeDelayChoices, id: \.self) { delay in
                            Text(verbatim: delay < 1 ? "0.5 seconds" : "\(Int(delay)) seconds").tag(delay)
                        }
                    }
                    Picker("Then keep the compact island for", selection: preferences.compactHold) {
                        ForEach(preferences.wrappedValue.compactHoldOptions, id: \.self) { seconds in
                            Text(verbatim: "\(Int(seconds)) seconds").tag(seconds)
                        }
                    }
                    Picker("Keep the compact island visible after activity", selection: preferences.activityHold) {
                        ForEach([15.0, 30, 60, 120, 300], id: \.self) { seconds in
                            Text(verbatim: seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) min").tag(seconds)
                        }
                    }
                    Toggle("Peek when a session starts working", isOn: preferences.revealOnActivity)
                    Toggle("Peek when a session finishes", isOn: preferences.revealOnFinish)
                    Toggle("Stay quiet when the session's IDE is already in front", isOn: preferences.quietWhenLooking)
                    Toggle("Nudge once when something waits for 2 minutes", isOn: preferences.nudgeEnabled)
                }
                .padding(6)
            }
            GroupBox("Display") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Show the island on", selection: preferences.displayChoice) {
                        ForEach(IslandDisplayChoice.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                    .frame(maxWidth: 380)
                    hint("On a screen without a notch the island sits in a small bar at the top. Follow mouse moves it to your cursor's screen while it is closed.")
                }
                .padding(6)
            }
            GroupBox("System") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Keep the Mac awake while an agent works", isOn: preferences.keepAwake)
                    Toggle("Launch at login", isOn: Binding(get: { self.preferences.launchAtLogin }, set: { setLaunchAtLogin($0) }))
                    if let error = status.launchAtLoginError { hint("Launch at login failed: \(error)") }
                }
                .padding(6)
            }
        }
    }

    private func appearancePage(preferences: Bindable<Preferences>) -> some View {
        Group {
            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    CharacterHero(design: self.preferences.character, color: self.preferences.characterColor,
                                  outfit: self.preferences.outfit)
                    PreviewGrid {
                        ForEach(CharacterDesign.allCases, id: \.self) { design in
                            PreviewCard(title: design.title, help: design.tagline, design: design,
                                        color: self.preferences.characterColor, outfit: self.preferences.outfit,
                                        isOn: self.preferences.character == design) {
                                self.preferences.character = design
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(Preferences.CharacterColor.allCases, id: \.self) { color in
                            VStack(spacing: 5) {
                                ColorSwatch(color: color, isOn: self.preferences.characterColor == color, size: 22) {
                                    self.preferences.characterColor = color
                                }
                                Text(verbatim: color.title).font(.system(size: 10))
                                    .foregroundColor(self.preferences.characterColor == color ? .primary : .secondary)
                            }
                            .frame(width: 60)
                        }
                    }
                }
                .padding(10)
            } label: {
                Label("Character", systemImage: "face.smiling")
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    PreviewGrid {
                        ForEach(Outfit.allCases, id: \.self) { outfit in
                            PreviewCard(title: outfit == .auto ? "Auto" : outfit.displayName, help: outfit.displayName,
                                        design: self.preferences.character, color: self.preferences.characterColor,
                                        outfit: outfit, isOn: self.preferences.outfit == outfit) {
                                self.preferences.outfit = outfit
                            }
                        }
                    }
                    hint("Auto changes with the season: devil horns in October, antlers in December, a propeller cap at New Year, a flower crown at Easter, heart glasses in summer.")
                }
                .padding(10)
            } label: {
                Label("Outfit", systemImage: "tshirt")
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show the character in the island", isOn: preferences.showCharacter)
                    Toggle("Glow behind the character", isOn: preferences.showGlow)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Display", systemImage: "sparkles")
            }
            GroupBox("Island content") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Session stats (model, context, tools, uptime)", isOn: preferences.showSessionStats)
                    Toggle("Plan usage in the header (5-hour and 7-day)", isOn: preferences.showPlanUsage)
                    Toggle("Diff chips (views.py +12 -3)", isOn: preferences.showDiffChips)
                    hint("Model, context and plan usage come from the status line relay (Agents page). Without it, context is estimated from the transcript and plan usage is hidden.")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func agentsPage(preferences: Bindable<Preferences>) -> some View {
        Group {
            GroupBox("Claude Code") {
                VStack(alignment: .leading, spacing: 10) {
                    integrationRow(title: "Hooks", detail: "sessions, approvals, questions",
                                   hookStatus: status.hookStatuses[.claude] ?? .missing,
                                   install: { status.installHooks(.claude) }, remove: { status.uninstallHooks(.claude) })
                    integrationRow(title: "Status line relay", detail: "model, context, 5h and 7d plan usage",
                                   hookStatus: status.statusLineStatus,
                                   install: { status.setStatusLineRelay(true) }, remove: { status.setStatusLineRelay(false) })
                    hint("The relay sends Claude's status line data to m_notch, then runs your own status line command, so your terminal looks the same.")
                }
                .padding(6)
            }
            GroupBox("Codex") {
                VStack(alignment: .leading, spacing: 8) {
                    integrationRow(title: "Hooks", detail: "sessions and approvals",
                                   hookStatus: status.hookStatuses[.codex] ?? .missing,
                                   install: { status.installHooks(.codex) }, remove: { status.uninstallHooks(.codex) })
                    hint("After installing, run /hooks once in Codex and trust the m_notch hook.")
                }
                .padding(6)
            }
            GroupBox("Approvals") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Answer permissions and questions in the notch", isOn: preferences.answerInNotch)
                    Toggle("Ask for Touch ID before allowing risky commands", isOn: preferences.touchIdForRisky)
                    hint("Off: requests go straight to the terminal prompt. Risky means rm -rf, sudo, git push --force, DROP TABLE, writes to .env or outside the project, and similar.")
                }
                .padding(6)
            }
            GroupBox("Jump to window") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Raise the exact project window, not just the app", isOn: preferences.raiseExactWindow)
                    HStack {
                        Text(verbatim: AXIsProcessTrusted() ? "Accessibility: allowed" : "Accessibility: not allowed")
                            .foregroundColor(.secondary)
                        if !AXIsProcessTrusted() { Button("Allow…") { status.requestAccessibility() } }
                    }
                    hint("Needs the Accessibility permission. A locally built app gets a new signature on every rebuild, so macOS may ask again after an update.")
                }
                .padding(6)
            }
            GroupBox("Server") {
                Text(verbatim: status.serverLine).foregroundColor(.secondary).padding(6)
            }
        }
    }

    private func extrasPage(preferences: Bindable<Preferences>) -> some View {
        Group {
            GroupBox("Calendar") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show your calendar in the island", isOn: preferences.showCalendar)
                    HStack {
                        Text(verbatim: status.calendarAccess.label).foregroundColor(.secondary)
                        if status.calendarAccess == .denied {
                            Button("Open System Settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                        }
                    }
                    hint("Adds a calendar tab next to the house in the island: a week strip, then the day's events with a now line and a Join button for Zoom, Google Meet, Teams and Webex links. A meeting that starts within the hour also shows above your sessions. It reads the calendars of the macOS Calendar app, so add your Google or Outlook account there. A locally built app gets a new signature on every rebuild, so macOS may ask again after an update.")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Now playing") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show what's playing in the island", isOn: preferences.showNowPlaying)
                    hint("Music, Spotify, YouTube and other sites in your browser, podcasts: whatever shows in Control Center's Now Playing. A music tab appears next to the house with the artwork, progress and play, pause, next and previous, and the track shows above your sessions. macOS only shares this with Apple's own programs, so m_notch reads it through the system's /usr/bin/perl with a small helper built into the app. Nothing leaves your Mac.")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Terminal commands") {
                VStack(alignment: .leading, spacing: 10) {
                    integrationRow(title: "zsh hook", detail: "commands that run 30 seconds or more",
                                   hookStatus: status.shellHookStatus,
                                   install: { status.setShellHook(true) }, remove: { status.setShellHook(false) })
                    hint("When a long command ends (tests, builds, installs), the island shows it passed or failed and how long it took. It adds one line to ~/.zshrc that loads a small script m_notch keeps in Application Support, so the token stays out of your dotfiles. Editors, ssh, REPLs and commands you stop with Ctrl-C are skipped.")
                }
                .padding(6)
            }
        }
    }

    private func soundsPage(preferences: Bindable<Preferences>) -> some View {
        GroupBox("Sounds") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Play sounds", isOn: preferences.soundsEnabled)
                HStack {
                    Text(verbatim: "Volume")
                    Slider(value: preferences.soundVolume, in: 0...1).frame(width: 200)
                }
                .disabled(!self.preferences.soundsEnabled)
                soundPicker("When something needs you", selection: preferences.needsYouSound)
                soundPicker("When a session finishes", selection: preferences.finishedSound)
                hint("macOS system sounds. coucou's own sounds are not licensed for reuse.")
            }
            .padding(6)
        }
    }

    private func shortcutsPage(preferences: Bindable<Preferences>) -> some View {
        Group {
            GroupBox("While a request waits") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable approval shortcuts", isOn: preferences.shortcutsEnabled)
                    shortcutLine("⌥⌘Y", "Allow, or Approve plan")
                    shortcutLine("⌥⌘N", "Deny, or Keep planning")
                    shortcutLine("⌥⌘A", "Always allow")
                    shortcutLine("⌥⌘1 to ⌥⌘4", "Pick a question option")
                }
                .padding(6)
            }
            GroupBox("Any time") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("⌥⌘M opens or closes the island", isOn: preferences.toggleIslandShortcut)
                }
                .padding(6)
            }
        }
    }

    private func aboutPage(preferences: Bindable<Preferences>) -> some View {
        Group {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "m_notch \(Updater.currentVersion)").font(.headline)
                    Text(verbatim: "A notch island for Claude Code and Codex sessions in PyCharm and VS Code.")
                    Text(verbatim: "\(store.sessions.count) live session(s). Last hook event: \(store.lastEventAt.map { RelativeAge.text(since: $0) } ?? "none").")
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Check for updates once a day", isOn: preferences.autoCheckUpdates)
                    HStack {
                        Text(verbatim: status.updateState.label).foregroundColor(.secondary)
                        Spacer()
                        if case .available = status.updateState {
                            Button("Install…") { status.installUpdate() }
                        }
                        Button("Check Now") { status.checkForUpdates() }
                            .disabled(status.updateState == .checking || status.updateState == .installing)
                    }
                    hint("Updates come from the releases of github.com/\(Updater.repository). m_notch checks the download's SHA-256, replaces itself and opens again. The app has no paid Apple signature, so macOS may ask for Accessibility and Calendars again after an update.")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Credits") {
                hint("The island, its animations and the character engine are ported from coucou by Louis Raillé (MIT License, see LICENSES/coucou-MIT.txt). Now playing reads macOS through /usr/bin/perl, a technique from mediaremote-adapter by ungive. The music and calendar tabs are inspired by boring.notch. The six characters are m_notch's own designs.")
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func integrationRow(title: String, detail: String, hookStatus: HookStatus,
                                install: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle().fill(hookStatus == .installed ? Palette.done : Palette.needsYou).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).fontWeight(.medium)
                Text(verbatim: "\(detail) · \(hookStatus.label)").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            if hookStatus != .installed {
                Button(hookStatus == .missing ? "Install…" : "Repair…", action: install)
            }
            if hookStatus == .installed || hookStatus == .outdated {
                Button("Remove…", action: remove)
            }
        }
    }

    private func soundPicker(_ title: String, selection: Binding<Preferences.SoundChoice>) -> some View {
        HStack {
            Picker(title, selection: selection) {
                ForEach(Preferences.SoundChoice.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
            }
            .frame(maxWidth: 340)
            Button {
                SoundPlayer.play(selection.wrappedValue, volume: preferences.soundVolume)
            } label: {
                Image(systemName: "play.fill")
            }
        }
        .disabled(!preferences.soundsEnabled)
    }

    private func shortcutLine(_ keys: String, _ meaning: String) -> some View {
        HStack {
            Text(verbatim: keys).font(.system(size: 12, design: .monospaced)).frame(width: 110, alignment: .leading)
            Text(verbatim: meaning).foregroundColor(.secondary)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
