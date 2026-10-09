import Foundation

public enum HookTarget: String, CaseIterable, Sendable {
    case claude, codex

    public var displayName: String { self == .claude ? "Claude" : "Codex" }

    /// The file m_notch merges its hooks into, inside the agent's settings folder.
    public var fileName: String { self == .claude ? "settings.json" : "hooks.json" }

    /// Where the agent keeps its settings unless another folder is chosen in Settings > Agents: the agent's own
    /// variable (CLAUDE_CONFIG_DIR, CODEX_HOME) when m_notch was started from a shell that sets it, else ~/.claude or ~/.codex.
    public func defaultFolder(home: String = NSHomeDirectory(),
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let variable = environment[self == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"] ?? ""
        return variable.isEmpty ? home + (self == .claude ? "/.claude" : "/.codex") : variable
    }

    public func fileURL(folder: String) -> URL {
        URL(fileURLWithPath: folder).appendingPathComponent(fileName)
    }
}

public enum HookStatus: Equatable, Sendable {
    case installed
    case missing
    case outdated
    case unreadable(String)

    public var label: String {
        switch self {
        case .installed: return "OK"
        case .missing: return "not installed"
        case .outdated: return "needs repair"
        case .unreadable(let reason): return reason
        }
    }
}

public struct HookInstallPlan {
    public let url: URL
    public let newData: Data
    public let originalBytes: Data?

    public var preview: String { String(decoding: newData, as: UTF8.self) }
}

/// Merges m_notch's hook entries into Claude's settings.json or Codex's hooks.json, keeping everything else.
public enum HookInstaller {
    static let marker = "/m_notch/"
    static let quickTimeout = 10
    static let heldTimeout = 300
    static let claudeQuickEvents = ["SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop"]
    static let codexEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "PermissionRequest"]

    public static func plan(for target: HookTarget, port: UInt16, token: String, folder: String) throws -> HookInstallPlan {
        let url = target.fileURL(folder: folder)
        let (settings, bytes) = try SettingsFileWriter.read(at: url)
        let merged = try merge(settings: settings, entries: entries(for: target, port: port, token: token), path: url.path)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return HookInstallPlan(url: url, newData: data + Data("\n".utf8), originalBytes: bytes)
    }

    public static func uninstallPlan(for target: HookTarget, folder: String) throws -> HookInstallPlan {
        let url = target.fileURL(folder: folder)
        let (settings, bytes) = try SettingsFileWriter.read(at: url)
        let cleaned = try merge(settings: settings, entries: [:], path: url.path)
        let data = try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return HookInstallPlan(url: url, newData: data + Data("\n".utf8), originalBytes: bytes)
    }

    @discardableResult
    public static func apply(_ plan: HookInstallPlan) throws -> URL? {
        try SettingsFileWriter.write(plan.newData, to: plan.url, expecting: plan.originalBytes)
    }

    public static func status(for target: HookTarget, port: UInt16, token: String, folder: String) -> HookStatus {
        let url = target.fileURL(folder: folder)
        do {
            let (settings, _) = try SettingsFileWriter.read(at: url)
            let hooks = try SettingsFileWriter.hooks(in: settings, path: url.path)
            let wanted = entries(for: target, port: port, token: token)
            var foundAny = false
            var allCurrent = true
            for (event, groups) in wanted {
                let existing = try SettingsFileWriter.hookGroups(in: hooks, event: event, path: url.path)
                let ours = existing.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.filter(isOurs)
                foundAny = foundAny || !ours.isEmpty
                let wantedHooks = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
                let current = wantedHooks.allSatisfy { wantedHook in ours.contains { NSDictionary(dictionary: $0).isEqual(to: wantedHook) } }
                allCurrent = allCurrent && current
            }
            if allCurrent { return .installed }
            return foundAny ? .outdated : .missing
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    static func merge(settings: [String: Any], entries: [String: [[String: Any]]], path: String) throws -> [String: Any] {
        var settings = settings
        var hooks = try SettingsFileWriter.hooks(in: settings, path: path)
        for event in Set(hooks.keys).union(entries.keys) {
            var groups: [[String: Any]] = []
            for var group in try SettingsFileWriter.hookGroups(in: hooks, event: event, path: path) {
                guard let groupHooks = group["hooks"] as? [[String: Any]] else {
                    groups.append(group)
                    continue
                }
                let theirs = groupHooks.filter { !isOurs($0) }
                guard !theirs.isEmpty else { continue }
                group["hooks"] = theirs
                groups.append(group)
            }
            groups += entries[event] ?? []
            hooks[event] = groups.isEmpty ? nil : groups
        }
        settings["hooks"] = hooks
        return settings
    }

    static func isOurs(_ hook: [String: Any]) -> Bool {
        ((hook["url"] as? String) ?? (hook["command"] as? String) ?? "").contains(marker)
    }

    static func entries(for target: HookTarget, port: UInt16, token: String) -> [String: [[String: Any]]] {
        switch target {
        case .claude: return claudeEntries(port: port, token: token)
        case .codex: return codexEntries(port: port, token: token)
        }
    }

    static func claudeEntries(port: UInt16, token: String) -> [String: [[String: Any]]] {
        func httpHook(path: String, timeout: Int) -> [String: Any] {
            [
                "type": "http",
                "url": "http://127.0.0.1:\(port)\(path)",
                "timeout": timeout,
                "headers": [
                    "Authorization": "Bearer \(token)",
                    "X-Term": "$TERM_PROGRAM",
                    "X-Emulator": "$TERMINAL_EMULATOR",
                    "X-Entry": "$CLAUDE_CODE_ENTRYPOINT",
                ],
                "allowedEnvVars": ["TERM_PROGRAM", "TERMINAL_EMULATOR", "CLAUDE_CODE_ENTRYPOINT"],
            ]
        }
        var entries: [String: [[String: Any]]] = [:]
        for event in claudeQuickEvents {
            entries[event] = [["hooks": [httpHook(path: HookServer.claudePath, timeout: quickTimeout)]]]
        }
        entries["PermissionRequest"] = [["hooks": [httpHook(path: HookServer.claudePath, timeout: heldTimeout)]]]
        entries["PreToolUse", default: []].append([
            "matcher": "AskUserQuestion",
            "hooks": [httpHook(path: HookServer.claudeQuestionPath, timeout: heldTimeout)],
        ])
        return entries
    }

    static func codexEntries(port: UInt16, token: String) -> [String: [[String: Any]]] {
        let command = "curl -s -m \(heldTimeout) --data-binary @- -H 'Authorization: Bearer \(token)' "
            + "-H \"X-Host: $__CFBundleIdentifier\" -H \"X-Term: $TERM_PROGRAM\" -H \"X-Emulator: $TERMINAL_EMULATOR\" "
            + "http://127.0.0.1:\(port)\(HookServer.codexPath) || true"
        var entries: [String: [[String: Any]]] = [:]
        for event in codexEvents {
            entries[event] = [["hooks": [["type": "command", "command": command, "timeout": heldTimeout]]]]
        }
        return entries
    }
}
