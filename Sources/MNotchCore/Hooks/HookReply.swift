import Foundation

public enum PermissionDecision: Sendable, Equatable {
    case allow
    case always
    case deny(message: String)
}

/// JSON bodies the app sends back to a held hook request. Claude Code and Codex share the shape.
public enum HookReply {
    public static let deniedMessage = "Denied from m_notch"
    public static let keepPlanningMessage = "Keep planning, the user wants changes."

    public static func permission(_ decision: PermissionDecision, suggestions: JSONValue?) -> Data {
        var decisionFields: [String: JSONValue]
        switch decision {
        case .allow:
            decisionFields = ["behavior": .string("allow")]
        case .always:
            decisionFields = ["behavior": .string("allow")]
            if let suggestions, case .array(let items) = suggestions, !items.isEmpty {
                decisionFields["updatedPermissions"] = suggestions
            }
        case .deny(let message):
            decisionFields = ["behavior": .string("deny"), "message": .string(message)]
        }
        let reply: JSONValue = .object(["hookSpecificOutput": .object([
            "hookEventName": .string("PermissionRequest"),
            "decision": .object(decisionFields),
        ])])
        return reply.encoded(sortedKeys: true)
    }

    public static func answers(questions: JSONValue, answers: [String: JSONValue]) -> Data {
        let reply: JSONValue = .object(["hookSpecificOutput": .object([
            "hookEventName": .string("PreToolUse"),
            "permissionDecision": .string("allow"),
            "updatedInput": .object(["questions": questions, "answers": .object(answers)]),
        ])])
        return reply.encoded(sortedKeys: true)
    }
}
