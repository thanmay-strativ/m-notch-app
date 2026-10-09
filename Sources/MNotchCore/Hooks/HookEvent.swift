import Foundation

public enum AgentKind: String, Sendable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// Env values the hook forwards as headers, used to tell which IDE runs the session.
public struct HostHints: Sendable, Equatable {
    public var bundleId: String?
    public var termProgram: String?
    public var emulator: String?
    public var entrypoint: String?

    public init(bundleId: String? = nil, termProgram: String? = nil, emulator: String? = nil, entrypoint: String? = nil) {
        self.bundleId = bundleId
        self.termProgram = termProgram
        self.emulator = emulator
        self.entrypoint = entrypoint
    }

    init(headers: [String: String]) {
        func value(_ name: String) -> String? {
            guard let raw = headers[name]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty, !raw.hasPrefix("$") else {
                return nil
            }
            return raw
        }
        self.init(bundleId: value("x-host"), termProgram: value("x-term"),
                  emulator: value("x-emulator"), entrypoint: value("x-entry"))
    }
}

/// One hook call from Claude Code or Codex, decoded from its JSON body.
public struct HookEvent: Sendable {
    public let agent: AgentKind
    public let name: String
    public let sessionId: String
    public let cwd: String
    public let transcriptPath: String?
    public let toolName: String?
    public let toolInput: JSONValue?
    public let toolResponse: JSONValue?
    public let permissionSuggestions: JSONValue?
    public let notificationType: String?
    public let lastAssistantMessage: String?
    public let hints: HostHints
    public let isQuestionHook: Bool

    public init?(agent: AgentKind, body: JSONValue, hints: HostHints, isQuestionHook: Bool = false) {
        guard let name = body["hook_event_name"]?.stringValue,
              let sessionId = body["session_id"]?.stringValue, !sessionId.isEmpty else {
            return nil
        }
        self.agent = agent
        self.name = name
        self.sessionId = sessionId
        self.cwd = body["cwd"]?.stringValue ?? NSHomeDirectory()
        self.transcriptPath = body["transcript_path"]?.stringValue
        self.toolName = body["tool_name"]?.stringValue
        self.toolInput = body["tool_input"]
        self.toolResponse = body["tool_response"]
        self.permissionSuggestions = body["permission_suggestions"]
        self.notificationType = body["notification_type"]?.stringValue
        self.lastAssistantMessage = body["last_assistant_message"]?.stringValue
        self.hints = hints
        self.isQuestionHook = isQuestionHook
    }

    public var holdsConnection: Bool {
        if name == "PermissionRequest" { return true }
        return isQuestionHook && name == "PreToolUse" && toolName == "AskUserQuestion"
    }

    public var stepText: String {
        guard let toolName else { return "" }
        let input = toolInput
        func fileName(_ key: String) -> String? {
            input?[key]?.stringValue.map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        switch toolName {
        case "Bash":
            return "Bash: " + (input?["command"]?.stringValue ?? "")
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
            return "\(toolName) \(fileName("file_path") ?? fileName("notebook_path") ?? "")"
        case "Grep", "Glob":
            return "\(toolName) \(input?["pattern"]?.stringValue ?? "")"
        case "WebFetch":
            return "Fetch \(input?["url"]?.stringValue ?? "")"
        case "WebSearch":
            return "Search \(input?["query"]?.stringValue ?? "")"
        case "Task", "Agent":
            return "Agent: \(input?["description"]?.stringValue ?? "")"
        default:
            return toolName
        }
    }
}
