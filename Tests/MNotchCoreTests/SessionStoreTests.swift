import Foundation
import Testing
@testable import MNotchCore

final class RecordingResponder: HookResponder, @unchecked Sendable {
    let id = UUID()
    private(set) var replies: [Data?] = []

    func reply(_ body: Data?) { replies.append(body) }

    var lastReplyText: String? { replies.last.flatMap { $0.map { String(decoding: $0, as: UTF8.self) } } }
}

@MainActor
struct SessionStoreTests {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore(clockStart: Date) -> (SessionStore, () -> Void) {
        let store = SessionStore()
        nonisolated(unsafe) var current = clockStart
        store.now = { current }
        store.resolveHost = { cwd, _ in (.pycharm, ProjectRoot.Result(path: cwd, marker: ".idea")) }
        store.readContext = { _ in ContextReading(usedTokens: 84_000, window: 200_000, modelId: "claude-opus-5-5") }
        store.countTools = { _ in 7 }
        store.transcriptCreatedAt = { _ in nil }
        return (store, { current = current.addingTimeInterval(SessionStore.requestLifetime + 1) })
    }

    private func event(_ name: String, session: String = "s1", tool: String? = nil,
                       input: String = "{}", extra: String = "", question: Bool = false) -> HookEvent {
        let toolField = tool.map { #""tool_name":"\#($0)","tool_input":\#(input),"# } ?? ""
        let body = #"{"hook_event_name":"\#(name)","session_id":"\#(session)","cwd":"/work/web-app",\#(toolField)\#(extra)"transcript_path":"/t.jsonl"}"#
        return HookEvent(agent: .claude, body: JSONValue.decode(Data(body.utf8))!, hints: HostHints(), isQuestionHook: question)!
    }

    @Test func twoPermissionRequestsQueueInOrderAndAllowAnswersTheFirst() {
        let (store, _) = makeStore(clockStart: clock)
        let first = RecordingResponder()
        let second = RecordingResponder()
        store.handle(event("PermissionRequest", session: "s1", tool: "Bash", input: #"{"command":"npm test"}"#), responder: first)
        store.handle(event("PermissionRequest", session: "s2", tool: "Bash", input: #"{"command":"ls"}"#), responder: second)
        #expect(store.pending.map(\.id) == [first.id, second.id])
        #expect(store.sessions["s1"]?.state == .needsYou)

        store.decide(first.id, .allow)

        #expect(first.lastReplyText?.contains(#""behavior":"allow""#) == true)
        #expect(second.replies.isEmpty)
        #expect(store.pending.map(\.id) == [second.id])
        #expect(store.sessions["s1"]?.state == .working)
    }

    @Test func matchingPostToolUseDismissesTheCardAnsweredInTheTerminal() {
        let (store, _) = makeStore(clockStart: clock)
        let responder = RecordingResponder()
        store.handle(event("PermissionRequest", tool: "Bash", input: #"{"command":"ls","description":"list"}"#), responder: responder)
        store.handle(event("PostToolUse", tool: "Bash", input: #"{"description":"list","command":"ls"}"#), responder: nil)
        #expect(store.pending.isEmpty)
        #expect(responder.replies == [nil])
    }

    @Test func closedConnectionRemovesTheCardWithoutReplying() {
        let (store, _) = makeStore(clockStart: clock)
        let responder = RecordingResponder()
        store.handle(event("PermissionRequest", tool: "Bash", input: #"{"command":"ls"}"#), responder: responder)
        store.peerClosed(responder.id)
        #expect(store.pending.isEmpty)
        #expect(responder.replies.isEmpty)
    }

    @Test func expiredRequestGetsAnEmptyReply() {
        let (store, advance) = makeStore(clockStart: clock)
        let responder = RecordingResponder()
        store.handle(event("PermissionRequest", tool: "Bash", input: #"{"command":"ls"}"#), responder: responder)
        advance()
        store.tick()
        #expect(store.pending.isEmpty)
        #expect(responder.replies == [nil])
    }

    @Test func alwaysFallsBackToAllowWhenTheCommandIsRisky() {
        let (store, _) = makeStore(clockStart: clock)
        let responder = RecordingResponder()
        let suggestions = #""permission_suggestions":[{"type":"addRules"}],"#
        store.handle(event("PermissionRequest", tool: "Bash", input: #"{"command":"rm -rf build"}"#, extra: suggestions),
                     responder: responder)
        #expect(store.pending.first?.risk == "rm -rf")
        #expect(store.pending.first?.canAlwaysAllow == false)
        store.decide(responder.id, .always)
        #expect(responder.lastReplyText?.contains("updatedPermissions") == false)
    }

    @Test func questionHookIsHeldButTheGenericPreToolUseIsNot() {
        let (store, _) = makeStore(clockStart: clock)
        let input = #"{"questions":[{"question":"Which size?","options":[{"label":"S"},{"label":"L"}]}]}"#
        store.handle(event("PreToolUse", tool: "AskUserQuestion", input: input), responder: nil)
        #expect(store.pending.isEmpty)
        let responder = RecordingResponder()
        store.handle(event("PreToolUse", tool: "AskUserQuestion", input: input, question: true), responder: responder)
        store.answer(responder.id, selections: [["L"]])
        #expect(responder.lastReplyText?.contains(#""answers":{"Which size?":"L"}"#) == true)
    }

    @Test func stopMarksDoneWithFirstLineAndReadsContext() {
        let (store, _) = makeStore(clockStart: clock)
        var signals: [StoreSignal] = []
        store.onSignal = { signals.append($0) }
        store.handle(event("UserPromptSubmit"), responder: nil)
        store.handle(event("Stop", extra: ###""last_assistant_message":"## Done\nAll tests pass.","###), responder: nil)
        #expect(store.sessions["s1"]?.state == .done)
        #expect(store.sessions["s1"]?.finishedLine == "Done")
        #expect(store.sessions["s1"]?.contextPercent == 42)
        #expect(signals.last == .finished(sessionId: "s1"))
    }

    @Test func silentSessionStopsCountingAsBusyAfter30Minutes() {
        let store = SessionStore()
        nonisolated(unsafe) var current = clock
        store.now = { current }
        store.resolveHost = { cwd, _ in (.vscode, ProjectRoot.Result(path: cwd, marker: ".git")) }
        store.handle(event("UserPromptSubmit"), responder: nil)
        #expect(store.isAnySessionBusy)
        current = current.addingTimeInterval(31 * 60)
        #expect(!store.isAnySessionBusy)
    }

    @Test func editRecordsDiffInTheTicker() {
        let (store, _) = makeStore(clockStart: clock)
        let response = #""tool_response":{"filePath":"/work/web-app/demo.py","structuredPatch":[{"oldStart":1,"oldLines":3,"newStart":1,"newLines":3,"lines":[" a = 1","-b = 2","+b = 20"," c = 3"]}]},"#
        store.handle(event("PostToolUse", tool: "Edit", input: #"{"file_path":"/work/web-app/demo.py"}"#, extra: response), responder: nil)
        #expect(store.sessions["s1"]?.diffs.count == 1)
        #expect(store.sessions["s1"]?.stepText == "demo.py +1 -1")
    }
}
