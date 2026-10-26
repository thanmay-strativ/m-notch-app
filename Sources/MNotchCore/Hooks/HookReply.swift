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
    public static let skippedQuestionMessage = "The user skipped this question. Continue without the answer, using your best judgment."

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

    /// Skip on a question card: the question tool is refused with a reason Claude reads, so it carries on without an answer.
    public static func skippedQuestion() -> Data {
        let reply: JSONValue = .object(["hookSpecificOutput": .object([
            "hookEventName": .string("PreToolUse"),
            "permissionDecision": .string("deny"),
            "permissionDecisionReason": .string(skippedQuestionMessage),
        ])])
        return reply.encoded(sortedKeys: true)
    }
}
