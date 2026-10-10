import AppKit
import ApplicationServices
import ServiceManagement
import os

/// Starts the hook server and the island, keeps hook health up to date, and runs the install and update flows.
@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    static let tokenKey = "hookToken"
    static let welcomeShownKey = "welcomeShown"
    static let firstUpdateCheckDelay: Duration = .seconds(15)
    static let updateCheckInterval: Duration = .seconds(24 * 60 * 60)

    let store = SessionStore()
    let model = IslandModel()
    let preferences = Preferences()
    let status = AppStatus()
    let port = HookServer.defaultPort
    let token = AppCoordinator.loadOrCreateToken()
    private(set) var island: IslandController?
    private var server: HookServer?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var folderWatchers: [DispatchSourceFileSystemObject] = []
    private let logger = Logger(subsystem: "local.mnotch", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        wireStatus()
        store.shouldHoldRequests = { [preferences] in preferences.answerInNotch }
        island = IslandController(store: store, model: model, preferences: preferences, status: status)
        startServer()
        refreshHookStatus()
        watchSettingsFolders()
        menuBar = MenuBarController(coordinator: self)
        pointLoginItemHere()
        scheduleUpdateChecks()
        offerWelcome()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for request in store.pending { store.replyInTerminal(request.id) }
        server?.stop()
    }

    private func wireStatus() {
        status.installHooks = { [weak self] target in self?.installHooks(for: target) }
        status.uninstallHooks = { [weak self] target in self?.uninstallHooks(for: target) }
        status.setStatusLineRelay = { [weak self] install in self?.setStatusLineRelay(install: install) }
        status.setShellHook = { [weak self] install in self?.setShellHook(install: install) }
        status.openSettingsWindow = { [weak self] in self?.openSettingsWindow() }
        status.checkForUpdates = { [weak self] in self?.checkForUpdates(userInitiated: true) }
        status.installUpdate = { [weak self] in self?.offerAvailableUpdate() }
        status.configFoldersChanged = { [weak self] in
            self?.watchSettingsFolders()
            self?.refreshHookStatus()
        }
        status.requestAccessibility = {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            status.launchAtLoginError = nil
            preferences.launchAtLogin = enabled
        } catch {
            logger.error("Launch at login \(enabled ? "on" : "off", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            status.launchAtLoginError = error.localizedDescription
            preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// macOS keeps the login item at the path it was turned on from, so after the app moves
    /// (say from Downloads into Applications) it would open a missing app at login. Registering again points it here.
    private func pointLoginItemHere() {
        if SMAppService.mainApp.status == .enabled { setLaunchAtLogin(true) }
    }

    func openSettingsWindow(at page: SettingsWindowView.Page? = nil) {
        if let page { status.settingsPage = page }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(preferences: preferences, status: status, store: store, coordinator: self)
        }
        settingsWindow?.show()
    }

    private func startServer() {
        let store = store
        let server = HookServer(
            port: port, token: token,
            onEvent: { event, responder in
                DispatchQueue.main.async { MainActor.assumeIsolated { store.handle(event, responder: responder) } }
            },
            onStatusLine: { info in
                DispatchQueue.main.async { MainActor.assumeIsolated { store.handleStatusLine(info) } }
            },
            onShellCommand: { command in
                DispatchQueue.main.async { MainActor.assumeIsolated { store.handleFinishedCommand(command) } }
            },
            onPeerClosed: { requestId in
                DispatchQueue.main.async { MainActor.assumeIsolated { store.peerClosed(requestId) } }
            },
            onStatus: { [weak self] serverStatus in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.status.serverStatus = serverStatus } }
            })
        server.start()
        self.server = server
    }

    func refreshHookStatus() {
        for target in HookTarget.allCases {
            let current = HookInstaller.status(for: target, port: port, token: token, folder: preferences.configFolder(for: target))
            if status.hookStatuses[target] != current { status.hookStatuses[target] = current }
        }
        let relay = StatusLineRelay.status(port: port, token: token, folder: preferences.configFolder(for: .claude))
        if status.statusLineStatus != relay { status.statusLineStatus = relay }
        let shellHook = ShellHook.status(port: port, token: token)
        if status.shellHookStatus != shellHook { status.shellHookStatus = shellHook }
        menuBar?.refreshIcon()
    }

    /// Watches each agent's settings folder, so hook health updates when the file changes. Called again when a folder setting changes.
    private func watchSettingsFolders() {
        folderWatchers.forEach { $0.cancel() }
        folderWatchers.removeAll()
        for target in HookTarget.allCases {
            let folder = preferences.configFolder(for: target)
            let descriptor = open(folder, O_EVTONLY)
            guard descriptor >= 0 else {
                logger.info("Not watching \(folder, privacy: .public): it does not exist yet")
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                                   queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.refreshHookStatus() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            folderWatchers.append(source)
        }
    }

    func installHooks(for target: HookTarget) {
        let note = target == .codex ? "In Codex, run /hooks once and trust the m_notch hook." : nil
        runPlan(title: "\(target.displayName) hooks", note: note) {
            try HookInstaller.plan(for: target, port: port, token: token, folder: preferences.configFolder(for: target))
        }
    }

    func uninstallHooks(for target: HookTarget) {
        runPlan(title: "\(target.displayName) hooks removal", note: nil) {
            try HookInstaller.uninstallPlan(for: target, folder: preferences.configFolder(for: target))
        }
    }

    func setStatusLineRelay(install: Bool) {
        let note = install ? "Your own status line keeps working: the relay runs it after sending the stats to m_notch." : nil
        runPlan(title: install ? "Status line relay" : "Status line relay removal", note: note) {
            try StatusLineRelay.plan(install: install, port: port, token: token, folder: preferences.configFolder(for: .claude))
        }
    }

    /// Install: writes the script m_notch owns, then adds the line that loads it to ~/.zshrc (preview, backup).
    /// Removal: takes the line out of ~/.zshrc first, then deletes the script.
    func setShellHook(install: Bool) {
        let title = install ? "Terminal hook" : "Terminal hook removal"
        if install {
            do {
                try ShellHook.writeScript(port: port, token: token)
                if try ShellHook.isInZshrc() {
                    refreshHookStatus()
                    showAlert(title: "\(title): done", text: "Updated \(ShellHook.scriptURL().path). Open a new terminal tab to use it.")
                    return
                }
            } catch {
                logger.error("Could not write \(ShellHook.scriptURL().path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                showAlert(title: "\(title): not written", text: "\(ShellHook.scriptURL().path): \(error.localizedDescription)")
                return
            }
        }
        let note = install ? "Open a new terminal tab (or run: source ~/.zshrc) to start using it." : nil
        let wroteZshrc = runPlan(title: title, note: note) { try ShellHook.plan(install: install) }
        guard !install && wroteZshrc else { return }
        do {
            try ShellHook.removeScript()
        } catch {
            logger.error("Could not delete \(ShellHook.scriptURL().path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        refreshHookStatus()
    }

    /// First launch with Claude not connected yet: one question instead of a hunt for the menu bar item.
    private func offerWelcome() {
        guard status.needsHookInstall, !UserDefaults.standard.bool(forKey: Self.welcomeShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.welcomeShownKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSApp.activate()
                let settingsFile = HookTarget.claude.fileURL(folder: self.preferences.configFolder(for: .claude)).path
                let alert = NSAlert()
                alert.messageText = "Welcome to m_notch"
                alert.informativeText = "Connect Claude Code so the island can show your sessions and answer their questions. "
                    + "m_notch adds its hooks to \((settingsFile as NSString).abbreviatingWithTildeInPath). You see the change first, "
                    + "a backup is made, and your own settings stay.\n\nKeep Claude's settings in another folder? Choose Settings."
                alert.addButton(withTitle: "Connect Claude Code…")
                alert.addButton(withTitle: "Settings…")
                alert.addButton(withTitle: "Later")
                switch alert.runModal() {
                case .alertFirstButtonReturn: self.installHooks(for: .claude)
                case .alertSecondButtonReturn: self.openSettingsWindow(at: .agents)
                default: break
                }
            }
        }
    }

    /// 15 s after launch, then once a day, while "Check for updates" is on.
    private func scheduleUpdateChecks() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.firstUpdateCheckDelay)
            while !Task.isCancelled {
                if let self, self.preferences.autoCheckUpdates { self.checkForUpdates(userInitiated: false) }
                try? await Task.sleep(for: Self.updateCheckInterval)
            }
        }
    }

    /// A found update is always offered. "Up to date" and errors only show when the user asked.
    func checkForUpdates(userInitiated: Bool) {
        guard status.updateState != .checking, status.updateState != .installing else { return }
        status.updateState = .checking
        Task {
            do {
                if let update = try await Updater.latest() {
                    status.updateState = .available(update)
                    offerAvailableUpdate()
                } else {
                    status.updateState = .upToDate
                    if userInitiated {
                        NSApp.activate()
                        showAlert(title: "m_notch is up to date", text: "Version \(Updater.currentVersion) is the latest release.")
                    }
                }
            } catch {
                logger.error("Update check at \(Updater.latestReleaseURL.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                status.updateState = .failed(error.localizedDescription)
                if userInitiated {
                    NSApp.activate()
                    showAlert(title: "Could not check for updates", text: error.localizedDescription)
                }
            }
        }
    }

    func offerAvailableUpdate() {
        guard case .available(let update) = status.updateState else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "m_notch \(update.version) is available"
        alert.informativeText = "You have \(Updater.currentVersion). m_notch downloads the new version from GitHub, "
            + "checks it, replaces itself and opens again. macOS may ask for Accessibility and Calendars again afterwards."
            + (update.notes.isEmpty ? "" : "\n\n" + String(update.notes.prefix(600)))
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        status.updateState = .installing
        Task {
            do {
                try await Updater.install(update)
                logger.info("Installed m_notch \(update.version, privacy: .public) over \(Bundle.main.bundlePath, privacy: .public), relaunching")
                try Updater.relaunch()
            } catch {
                logger.error("Update to \(update.version, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                status.updateState = .failed(error.localizedDescription)
                NSApp.activate()
                showAlert(title: "Could not update to \(update.version)", text: error.localizedDescription)
            }
        }
    }

    @discardableResult
    private func runPlan(title: String, note: String?, makePlan: () throws -> HookInstallPlan) -> Bool {
        NSApp.activate()
        let plan: HookInstallPlan
        do {
            plan = try makePlan()
        } catch {
            logger.error("Could not prepare \(title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showAlert(title: "Could not prepare \(title)", text: error.localizedDescription)
            return false
        }
        guard confirm(plan, title: title) else { return false }
        do {
            let backup = try HookInstaller.apply(plan)
            logger.info("Wrote \(title, privacy: .public) to \(plan.url.path, privacy: .public), backup \(backup?.path ?? "none", privacy: .public)")
            refreshHookStatus()
            var text = "Written to \(plan.url.path)."
            if let backup { text += "\nBackup: \(backup.path)" }
            if let note { text += "\n\(note)" }
            showAlert(title: "\(title): done", text: text)
            return true
        } catch {
            logger.error("Could not write \(title, privacy: .public) to \(plan.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showAlert(title: "\(title): not written", text: error.localizedDescription)
            return false
        }
    }

    private func confirm(_ plan: HookInstallPlan, title: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(title): update \(plan.url.path)?"
        alert.informativeText = plan.originalBytes == nil
            ? "The file does not exist yet and will be created with this content:"
            : "A dated backup is made first. Your own settings and hooks are kept. The file after the change:"
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 620, height: 320)
        if let textView = scrollView.documentView as? NSTextView {
            textView.string = plan.preview
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        }
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "Write")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private static func loadOrCreateToken() -> String {
        if let saved = UserDefaults.standard.string(forKey: tokenKey), saved.count == 64 { return saved }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        return token
    }
}
