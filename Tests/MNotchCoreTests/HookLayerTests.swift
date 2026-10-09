import Foundation
import Testing
@testable import MNotchCore

struct HTTPMessageTests {
    @Test func parsesCompleteRequestWithLowercasedHeaders() {
        let raw = "POST /m_notch/claude HTTP/1.1\r\nAuthorization: Bearer abc\r\nContent-Length: 2\r\n\r\n{}"
        guard case .complete(let request) = HTTPMessage.parse(Data(raw.utf8)) else {
            Issue.record("expected a complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/m_notch/claude")
        #expect(request.headers["authorization"] == "Bearer abc")
        #expect(request.body == Data("{}".utf8))
    }

    @Test func waitsForTheRestOfTheBody() {
        let raw = "POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\""
        #expect(HTTPMessage.parse(Data(raw.utf8)) == .incomplete)
    }

    @Test func rejectsBodiesOverOneMegabyte() {
        let raw = "POST / HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n"
        #expect(HTTPMessage.parse(Data(raw.utf8)) == .tooLarge(2_000_000))
    }
}

struct HookReplyTests {
    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func denyHasTheExactShapeClaudeExpects() {
        let reply = text(HookReply.permission(.deny(message: HookReply.deniedMessage), suggestions: nil))
        #expect(reply == #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Denied from m_notch"},"hookEventName":"PermissionRequest"}}"#)
    }

    @Test func alwaysPassesClaudesOwnSuggestionsBack() {
        let suggestions: JSONValue = .array([.object(["type": .string("addRules")])])
        let reply = text(HookReply.permission(.always, suggestions: suggestions))
        #expect(reply.contains(#""updatedPermissions":[{"type":"addRules"}]"#))
        #expect(reply.contains(#""behavior":"allow""#))
    }

    @Test func multiSelectAnswersAreAListAndSingleSelectAString() throws {
        let toolInput = try #require(JSONValue.decode(Data(#"""
        {"questions":[
          {"question":"Which colors?","header":"Colors","multiSelect":true,"options":[{"label":"Red"},{"label":"Blue"},{"label":"Green"}]},
          {"question":"Which size?","header":"Size","multiSelect":false,"options":[{"label":"Small"},{"label":"Large"}]}
        ]}
        """#.utf8)))
        let question = try #require(AskQuestion.parse(toolInput: toolInput))
        let answers = AskQuestion.buildAnswers(questions: question.questions, selections: [["Red", "Green"], ["Large"]])
        #expect(answers["Which colors?"] == .array([.string("Red"), .string("Green")]))
        #expect(answers["Which size?"] == .string("Large"))
        let reply = text(HookReply.answers(questions: toolInput["questions"]!, answers: answers))
        #expect(reply.contains(#""permissionDecision":"allow""#))
        #expect(reply.contains(#""hookEventName":"PreToolUse""#))
    }

    @Test func questionWithOneOptionIsRejected() {
        let toolInput = JSONValue.decode(Data(#"{"questions":[{"question":"Q?","options":[{"label":"Only"}]}]}"#.utf8))
        #expect(AskQuestion.parse(toolInput: toolInput) == nil)
    }

    @Test func uninterpolatedHeaderValuesAreIgnored() {
        let hints = HostHints(headers: ["x-emulator": "JetBrains-JediTerm", "x-term": "", "x-entry": "$CLAUDE_CODE_ENTRYPOINT"])
        #expect(hints == HostHints(emulator: "JetBrains-JediTerm"))
    }
}
