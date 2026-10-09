import AppKit

/// Menu bar icon and its menu: hook health, install/repair, screen choice, keep awake, updates, quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let coordinator: AppCoordinator
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        let healthy = !coordinator.status.needsHookInstall
        let symbol = healthy ? "rectangle.topthird.inset.filled" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "m_notch")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        coordinator.refreshHookStatus()
        menu.removeAllItems()
        for target in HookTarget.allCases {
            let status = coordinator.status.hookStatuses[target] ?? .missing
            menu.addItem(info("\(target.displayName) hooks: \(status.label)"))
            if status != .installed {
                let verb = status == .missing ? "Install" : "Repair"
                menu.addItem(action("\(verb) \(target.displayName) hooks…") { [weak self] in
                    self?.coordinator.status.installHooks(target)
                })
            }
        }
        menu.addItem(info("Server: \(coordinator.status.serverLine)"))
        menu.addItem(info(lastEventLine))
        menu.addItem(.separator())

        let screenItem = NSMenuItem(title: "Screen", action: nil, keyEquivalent: "")
        let screenMenu = NSMenu()
        for choice in IslandDisplayChoice.allCases {
            let item = action(choice.title) { [weak self] in self?.coordinator.preferences.displayChoice = choice }
            item.state = coordinator.preferences.displayChoice == choice ? .on : .off
            screenMenu.addItem(item)
        }
        screenItem.submenu = screenMenu
        menu.addItem(screenItem)

        let awakeItem = action("Keep Mac awake while working") { [weak self] in
            self?.coordinator.preferences.keepAwake.toggle()
        }
        awakeItem.state = coordinator.preferences.keepAwake ? .on : .off
        menu.addItem(awakeItem)
        menu.addItem(.separator())
        menu.addItem(action("Settings…") { [weak self] in self?.coordinator.openSettingsWindow() })
        if case .available(let update) = coordinator.status.updateState {
            menu.addItem(action("Install m_notch \(update.version)…") { [weak self] in self?.coordinator.offerAvailableUpdate() })
        } else {
            menu.addItem(action("Check for Updates…") { [weak self] in self?.coordinator.checkForUpdates(userInitiated: true) })
        }
        menu.addItem(NSMenuItem(title: "Quit m_notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private var lastEventLine: String {
        guard let last = coordinator.store.lastEventAt else { return "No hook events yet" }
        let age = RelativeAge.text(since: last)
        return age == "now" ? "Last event: just now" : "Last event: \(age) ago"
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        return item
    }
}

/// NSMenuItem that runs a closure, so the menu needs no selector per item.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("ClosureMenuItem is never decoded") }

    @objc private func run() { handler() }
}
