import Foundation

public enum SessionState: Sendable, Equatable {
    case thinking, working, needsYou, done

    var sortRank: Int {
        switch self {
        case .needsYou: return 0
        case .working: return 1
        case .thinking: return 2
        case .done: return 3
        }
    }
}

public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public let agent: AgentKind
    public var name: String
    public var cwd: String
    public var projectRoot: String
    public var host: HostApp
    public var state: SessionState = .thinking
    public var stepText = ""
    public var finishedLine = ""
    public var lastChange: Date
    public var diffs: [FileDiff] = []
    public var transcriptPath: String?
    public var startedAt: Date
    public var toolCount = 0
    public var modelName: String?
    public var contextUsed: Int?
    public var contextWindow: Int?
    var hasStatusLineStats = false
    var contextCheckedAt: Date?
    var waitingNudged = false

    public var isBusy: Bool { state == .thinking || state == .working }

    public var contextPercent: Int? {
        guard let contextUsed, let contextWindow, contextWindow > 0 else { return nil }
        return min(100, Int((Double(contextUsed) / Double(contextWindow) * 100).rounded()))
    }
}

public enum PendingKind: Equatable, Sendable {
    case permission
    case question(AskQuestion)
    case plan(String)
}

public struct PendingRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let agent: AgentKind
    public let toolName: String
    public let toolInput: JSONValue?
    public let inputKey: String
    public let summary: String
    public let suggestions: JSONValue?
    public let risk: String?
    public let kind: PendingKind
    public let createdAt: Date
    var nudged = false

    public var canAlwaysAllow: Bool {
        guard agent == .claude, risk == nil, kind == .permission else { return false }
        return suggestions?.arrayValue?.isEmpty == false
    }

    static func summary(toolName: String, toolInput: JSONValue?) -> String {
        if let command = toolInput?["command"]?.stringValue { return command }
        if let path = toolInput?["file_path"]?.stringValue ?? toolInput?["notebook_path"]?.stringValue { return path }
        if let url = toolInput?["url"]?.stringValue { return url }
        return toolName
    }
}

public enum StoreSignal: Equatable, Sendable {
    case activity(sessionId: String)
    case finished(sessionId: String)
    case requestsChanged
    case nudge
    case commandFinished
}
