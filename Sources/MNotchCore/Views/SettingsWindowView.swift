// Sidebar layout ported from coucou's Settings window (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import AppKit
import ApplicationServices
import SwiftUI

/// The settings window: a sidebar of pages, each one a grouped form like System Settings.
struct SettingsWindowView: View {
    enum Page: String, CaseIterable, Identifiable {
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

        var subtitle: String {
            switch self {
            case .general: return "How the island opens, closes and peeks"
            case .appearance: return "Your character, its color and outfit"
            case .agents: return "Connect Claude Code and Codex"
            case .extras: return "Calendar, music and terminal commands"
            case .sounds: return "Sounds for requests and finished sessions"
            case .shortcuts: return "Answer from the keyboard"
            case .about: return "Version, updates and credits"
            }
        }
    }

    let preferences: Preferences
    let status: AppStatus
    let store: SessionStore
    let setLaunchAtLogin: (Bool) -> Void
    @State private var isAccessibilityAllowed = AXIsProcessTrusted()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                page.id(status.settingsPage).transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(.easeInOut(duration: 0.18), value: status.settingsPage)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityAllowed = AXIsProcessTrusted()
            status.configFoldersChanged()
        }
    }

    /// Solid sidebar, drawn by hand so it looks the same in screenshots as on screen. Leaves room for the window buttons.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Page.allCases) { page in
                SidebarRow(page: page, isSelected: status.settingsPage == page) { status.settingsPage = page }
            }
            Spacer()
            Text(verbatim: "m_notch \(Updater.currentVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 12)
        }
        .padding(.horizontal, 10)
        .padding(.top, 52)
        .padding(.bottom, 14)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(ZStack {
            Color(nsColor: .windowBackgroundColor)
            Color.primary.opacity(0.04)
        })
    }

    private var pageHeader: some View {
        HStack(spacing: 12) {
            PageIcon(page: status.settingsPage, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: status.settingsPage.rawValue).font(.system(size: 20, weight: .bold))
                Text(verbatim: status.settingsPage.subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 2)
    }

    @ViewBuilder private var page: some View {
        @Bindable var preferences = preferences
        Group {
            switch status.settingsPage {
            case .general: generalPage(preferences: $preferences)
            case .appearance: appearancePage(preferences: $preferences)
            case .agents: agentsPage(preferences: $preferences)
            case .extras: extrasPage(preferences: $preferences)
            case .sounds: soundsPage(preferences: $preferences)
            case .shortcuts: shortcutsPage(preferences: $preferences)
            case .about: aboutPage(preferences: $preferences)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
    }

    // MARK: - Pages

    private func generalPage(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section("Island") {
                toggle("Open on hover", "Hovering the notch opens the island fully, not just a peek", isOn: preferences.openOnHover)
                Picker("Shrink after the pointer leaves", selection: preferences.closeDelay) {
                    ForEach(Preferences.closeDelayChoices, id: \.self) { delay in
                        Text(verbatim: delay < 1 ? "0.5 seconds" : "\(Int(delay)) seconds").tag(delay)
                    }
                }
                Picker("Then stay small for", selection: preferences.compactHold) {
                    ForEach(preferences.wrappedValue.compactHoldOptions, id: \.self) { seconds in
                        Text(verbatim: "\(Int(seconds)) seconds").tag(seconds)
                    }
                }
                Picker("Stay visible after activity", selection: preferences.activityHold) {
                    ForEach([15.0, 30, 60, 120, 300], id: \.self) { seconds in
                        Text(verbatim: seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) min").tag(seconds)
                    }
                }
            }
            Section("Peek out") {
                toggle("When a session starts working", isOn: preferences.revealOnActivity)
                toggle("When a session finishes", isOn: preferences.revealOnFinish)
                toggle("Stay quiet when its IDE is in front", "No peeking while you are already looking at that window", isOn: preferences.quietWhenLooking)
                toggle("Nudge once after 2 minutes of waiting", isOn: preferences.nudgeEnabled)
            }
            Section {
                Picker("Show the island on", selection: preferences.displayChoice) {
                    ForEach(IslandDisplayChoice.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
            } header: {
                Text("Screen")
            } footer: {
                footnote("On a screen without a notch the island sits in a small bar at the top. Follow mouse moves it to your pointer's screen while it is closed.")
            }
            Section("System") {
                toggle("Keep the Mac awake while an agent works", isOn: preferences.keepAwake)
                toggle("Launch at login", status.launchAtLoginError.map { "Failed: \($0)" },
                       isOn: Binding(get: { self.preferences.launchAtLogin }, set: { setLaunchAtLogin($0) }))
            }
        }
    }

    private func appearancePage(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                CharacterHero(design: self.preferences.character, color: self.preferences.characterColor, outfit: self.preferences.outfit)
            }
            Section("Character") {
                ChoiceGrid {
                    ForEach(CharacterDesign.allCases, id: \.self) { design in
                        ChoiceTile(title: design.title, help: design.tagline, design: design,
                                   color: self.preferences.characterColor, outfit: self.preferences.outfit,
                                   isOn: self.preferences.character == design) {
                            self.preferences.character = design
                        }
                    }
                }
                LabeledContent {
                    HStack(spacing: 4) {
                        ForEach(Preferences.CharacterColor.allCases, id: \.self) { color in
                            SettingsSwatch(color: color, isOn: self.preferences.characterColor == color) {
                                self.preferences.characterColor = color
                            }
                        }
                    }
                } label: {
                    Text("Color")
                    Text(verbatim: self.preferences.characterColor.title)
                }
            }
            Section {
                ChoiceGrid {
                    ForEach(Outfit.allCases, id: \.self) { outfit in
                        ChoiceTile(title: outfit == .auto ? "Auto" : outfit.displayName, help: outfit.displayName,
                                   design: self.preferences.character, color: self.preferences.characterColor,
                                   outfit: outfit, isOn: self.preferences.outfit == outfit) {
                            self.preferences.outfit = outfit
                        }
                    }
                }
            } header: {
                Text("Outfit")
            } footer: {
                footnote("Auto follows the season: devil horns in October, antlers in December, a propeller cap at New Year, a flower crown at Easter, heart glasses in summer.")
            }
            Section {
                toggle("Show the character", isOn: preferences.showCharacter)
                toggle("Glow behind it", isOn: preferences.showGlow)
                toggle("Session stats", "Model, context, tool calls and uptime under each session", isOn: preferences.showSessionStats)
                toggle("Plan usage", "Your 5-hour and 7-day usage in the header", isOn: preferences.showPlanUsage)
                toggle("Diff chips", "Changed files like views.py +12 -3", isOn: preferences.showDiffChips)
            } header: {
                Text("In the island")
            } footer: {
                footnote("Model, context and plan usage come from the status line relay (Agents). Without it, context is estimated and plan usage is hidden.")
            }
        }
    }

    private func agentsPage(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                folderRow(for: .claude, text: preferences.claudeFolder)
                integrationRow(title: "Hooks", detail: "Sessions, approvals and questions",
                               hookStatus: status.hookStatuses[.claude] ?? .missing,
                               install: { status.installHooks(.claude) }, remove: { status.uninstallHooks(.claude) })
                integrationRow(title: "Status line relay", detail: "Model, context and plan usage",
                               hookStatus: status.statusLineStatus,
                               install: { status.setStatusLineRelay(true) }, remove: { status.setStatusLineRelay(false) })
            } header: {
                Text("Claude Code")
            } footer: {
                footnote("Most people keep ~/.claude. If you start Claude with CLAUDE_CONFIG_DIR, put that folder here. The relay runs your own status line after sending the stats, so your terminal looks the same.")
            }
            Section {
                folderRow(for: .codex, text: preferences.codexFolder)
                integrationRow(title: "Hooks", detail: "Sessions and approvals",
                               hookStatus: status.hookStatuses[.codex] ?? .missing,
                               install: { status.installHooks(.codex) }, remove: { status.uninstallHooks(.codex) })
            } header: {
                Text("Codex")
            } footer: {
                footnote("Most people keep ~/.codex, or CODEX_HOME if set. After installing, run /hooks once in Codex and trust the m_notch hook.")
            }
            Section {
                toggle("Answer in the notch", "Permissions, questions and plans show as cards", isOn: preferences.answerInNotch)
                toggle("Touch ID for risky commands", "rm -rf, sudo, git push --force, DROP TABLE, writes to .env or outside the project",
                       isOn: preferences.touchIdForRisky)
            } header: {
                Text("Approvals")
            } footer: {
                footnote("Off: requests go straight to the terminal prompt.")
            }
            Section {
                toggle("Raise the exact project window", "Not just the app, when it has several windows open", isOn: preferences.raiseExactWindow)
                LabeledContent {
                    HStack(spacing: 8) {
                        StatusPill(text: isAccessibilityAllowed ? "Allowed" : "Not allowed", tone: isAccessibilityAllowed ? .good : .warning)
                        if !isAccessibilityAllowed { Button("Allow…") { status.requestAccessibility() } }
                    }
                } label: {
                    Text("Accessibility")
                    Text("Needed to find a window by its title")
                }
            } header: {
                Text("Jump to window")
            } footer: {
                footnote("macOS may ask again after an update, because the app has no paid Apple signature.")
            }
            Section("Server") {
                LabeledContent("Hook server") { StatusPill(text: status.serverLine, tone: serverTone) }
            }
        }
    }

    private func extrasPage(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                toggle("Show your calendar", "A calendar tab next to the house, with Join buttons for video calls", isOn: preferences.showCalendar)
                LabeledContent {
                    HStack(spacing: 8) {
                        StatusPill(text: calendarAccessText, tone: calendarAccessTone)
                        if status.calendarAccess == .denied {
                            Button("Open System Settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                        }
                    }
                } label: {
                    Text("Calendars")
                }
            } header: {
                Text("Calendar")
            } footer: {
                footnote("Reads the calendars of the macOS Calendar app, so add your Google or Outlook account there. A meeting that starts within the hour also shows above your sessions.")
            }
            Section {
                toggle("Show what's playing", "Music, Spotify, YouTube in your browser, podcasts", isOn: preferences.showNowPlaying)
            } header: {
                Text("Now playing")
            } footer: {
                footnote("A music tab with the artwork, a progress bar you can drag, and play controls. macOS only shares this with Apple's own programs, so m_notch reads it through /usr/bin/perl with a small helper built into the app. Nothing leaves your Mac.")
            }
            Section {
                integrationRow(title: "zsh hook", detail: "Commands that run 30 seconds or more",
                               hookStatus: status.shellHookStatus,
                               install: { status.setShellHook(true) }, remove: { status.setShellHook(false) })
            } header: {
                Text("Terminal commands")
            } footer: {
                footnote("When a long command ends (tests, builds, installs), the island shows if it passed and how long it took. It adds one line to ~/.zshrc. Editors, ssh, REPLs and Ctrl-C are skipped.")
            }
        }
    }

    private func soundsPage(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                toggle("Play sounds", isOn: preferences.soundsEnabled)
                LabeledContent("Volume") {
                    Slider(value: preferences.soundVolume, in: 0...1).frame(width: 200)
                }
                .disabled(!self.preferences.soundsEnabled)
                soundPicker("When something needs you", selection: preferences.needsYouSound)
                soundPicker("When a session finishes", selection: preferences.finishedSound)
            } footer: {
                footnote("macOS system sounds. Press ▶ to hear one.")
            }
        }
    }

    private func shortcutsPage(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                toggle("Approval shortcuts", "Only active while a request waits, so they never clash with your IDE", isOn: preferences.shortcutsEnabled)
                shortcutLine("⌥⌘Y", "Allow, or Approve plan")
                shortcutLine("⌥⌘N", "Deny, or Keep planning")
                shortcutLine("⌥⌘A", "Always allow")
                shortcutLine("⌥⌘1 to ⌥⌘4", "Pick a question option")
            } header: {
                Text("While a request waits")
            }
            Section("Any time") {
                toggle("⌥⌘M opens or closes the island", isOn: preferences.toggleIslandShortcut)
            }
        }
    }

    private func aboutPage(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    CharacterPreview(design: self.preferences.character, color: self.preferences.characterColor,
                                     outfit: self.preferences.outfit, width: 40, headroom: 0.4, interactive: true)
                        .frame(width: 60, height: 60)
                        .background(CharacterTileBackground(glow: Color(hex: self.preferences.characterColor.gradientHex.top), cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "m_notch").font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(verbatim: "Version \(Updater.currentVersion)").foregroundStyle(.secondary)
                        Text(verbatim: "A notch island for Claude Code and Codex in PyCharm and VS Code.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Link("GitHub", destination: URL(string: "https://github.com/\(Updater.repository)")!)
                }
                LabeledContent("Live sessions", value: "\(store.sessions.count)")
                LabeledContent("Last hook event", value: store.lastEventAt.map { RelativeAge.text(since: $0) == "now" ? "just now" : RelativeAge.text(since: $0) + " ago" } ?? "none yet")
            }
            Section {
                toggle("Check for updates once a day", isOn: preferences.autoCheckUpdates)
                LabeledContent {
                    HStack(spacing: 8) {
                        if case .available = status.updateState {
                            Button("Install…") { status.installUpdate() }.buttonStyle(.borderedProminent)
                        }
                        Button("Check Now") { status.checkForUpdates() }
                            .disabled(status.updateState == .checking || status.updateState == .installing)
                    }
                } label: {
                    Text("Status")
                    Text(verbatim: status.updateState.label)
                }
            } header: {
                Text("Updates")
            } footer: {
                footnote("New versions come from the GitHub releases. m_notch checks the download's SHA-256, replaces itself and opens again.")
            }
            Section {
                creditRow("coucou", "The island, its animations and the character engine (MIT License)", url: "https://github.com/Louis-CFM/coucou")
                creditRow("mediaremote-adapter", "The idea of reading Now Playing through /usr/bin/perl", url: "https://github.com/ungive/mediaremote-adapter")
                creditRow("boring.notch", "Inspiration for music and a calendar in the notch", url: "https://github.com/TheBoredTeam/boring.notch")
            } header: {
                Text("Thanks to")
            } footer: {
                footnote("coucou's code is used under the MIT License (LICENSES/coucou-MIT.txt, also inside the app). The six characters are m_notch's own designs.")
            }
        }
    }

    // MARK: - Rows

    /// A switch with a title and an optional second line, like System Settings.
    private func toggle(_ title: String, _ detail: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(verbatim: title)
            if let detail { Text(verbatim: detail) }
        }
    }

    /// Where the agent's settings live. Empty uses the default, shown as the placeholder.
    private func folderRow(for target: HookTarget, text: Binding<String>) -> some View {
        let folder = preferences.configFolder(for: target)
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder) && isFolder.boolValue
        return LabeledContent {
            HStack(spacing: 6) {
                TextField("", text: text, prompt: Text(verbatim: Self.tilde(target.defaultFolder())))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 230)
                    .onChange(of: text.wrappedValue) { status.configFoldersChanged() }
                Button { chooseFolder(for: target, text: text) } label: { Image(systemName: "folder") }
                    .help("Choose the folder")
                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = "" } label: { Image(systemName: "arrow.uturn.backward") }
                        .help("Use the default, \(Self.tilde(target.defaultFolder()))")
                }
            }
        } label: {
            Text("Settings folder")
            Text(verbatim: exists ? "Uses \(Self.tilde(target.fileURL(folder: folder).path))" : "No folder at \(Self.tilde(folder)) yet")
                .foregroundStyle(exists ? Color.secondary : Palette.needsYou)
        }
    }

    private func chooseFolder(for target: HookTarget, text: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: preferences.configFolder(for: target))
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder that holds \(target.displayName)'s \(target.fileName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text.wrappedValue = Self.tilde(url.path)
    }

    private func integrationRow(title: String, detail: String, hookStatus: HookStatus,
                                install: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                StatusPill(text: hookStatus.label, tone: hookStatus == .installed ? .good : .warning)
                if hookStatus != .installed {
                    Button(hookStatus == .missing ? "Install…" : "Repair…", action: install).buttonStyle(.borderedProminent)
                }
                if hookStatus == .installed || hookStatus == .outdated {
                    Button("Remove…", action: remove)
                }
            }
        } label: {
            Text(verbatim: title)
            Text(verbatim: detail)
        }
    }

    private func soundPicker(_ title: String, selection: Binding<Preferences.SoundChoice>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Picker(title, selection: selection) {
                    ForEach(Preferences.SoundChoice.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
                Button {
                    SoundPlayer.play(selection.wrappedValue, volume: preferences.soundVolume)
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Play \(selection.wrappedValue.rawValue)")
            }
        }
        .disabled(!preferences.soundsEnabled)
    }

    private func shortcutLine(_ keys: String, _ meaning: String) -> some View {
        LabeledContent(meaning) {
            Text(verbatim: keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
        }
        .disabled(!preferences.shortcutsEnabled)
    }

    private func creditRow(_ name: String, _ detail: String, url: String) -> some View {
        LabeledContent {
            Link(destination: URL(string: url)!) { Image(systemName: "arrow.up.right.square") }
                .help(url)
        } label: {
            Text(verbatim: name)
            Text(verbatim: detail)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(verbatim: text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Status values

    private var serverTone: StatusPill.Tone {
        switch status.serverStatus {
        case .ready: return .good
        case .starting: return .neutral
        case .failed: return .bad
        }
    }

    private var calendarAccessText: String {
        switch status.calendarAccess {
        case .notAsked: return "Asked when you turn it on"
        case .allowed: return "Allowed"
        case .denied: return "Not allowed"
        }
    }

    private var calendarAccessTone: StatusPill.Tone {
        switch status.calendarAccess {
        case .notAsked: return .neutral
        case .allowed: return .good
        case .denied: return .warning
        }
    }

    /// "/Users/me/.claude" as "~/.claude".
    private static func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}

/// One sidebar entry: icon and name, filled with the accent color when selected, tinted on hover.
struct SidebarRow: View {
    let page: SettingsWindowView.Page
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                PageIcon(page: page, size: 22)
                Text(verbatim: page.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// The colored rounded square with a white symbol, used in the sidebar and the page header.
struct PageIcon: View {
    let page: SettingsWindowView.Page
    let size: CGFloat

    var body: some View {
        Image(systemName: page.icon.name)
            .foregroundStyle(.white)
            .font(.system(size: size * 0.55, weight: .semibold))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: page.icon.color).opacity(0.85), Color(hex: page.icon.color)],
                                     startPoint: .top, endPoint: .bottom)))
    }
}
