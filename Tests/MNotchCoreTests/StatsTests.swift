import Foundation
import Testing
@testable import MNotchCore

struct StatusLineTests {
    private let resetsAt = Int(Date().timeIntervalSince1970) + 9_000
    private var payload: String { #"""
    {"session_id":"s1","transcript_path":"/t.jsonl","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
     "context_window":{"total_input_tokens":460000,"total_output_tokens":5000,"context_window_size":1000000},
     "rate_limits":{"five_hour":{"used_percentage":39,"resets_at":\#(resetsAt)},"seven_day":{"used_percentage":37.4,"resets_at":\#(resetsAt)}}}
    """# }

    @Test func readsTheSameNumbersAsTheUsersStatusLine() throws {
        let info = StatusLineInfo(body: try #require(JSONValue.decode(Data(payload.utf8))))
        #expect(info.sessionId == "s1")
        #expect(info.modelName == "Opus 5.5")
        #expect(info.contextUsed == 465_000)
        #expect(info.contextWindow == 1_000_000)
        #expect(info.plan?.fiveHour?.usedPercent == 39)
        #expect(info.plan?.sevenDay?.usedPercent == 37.4)
    }

    @Test func millisecondTimestampsAreRejected() {
        let window = StatusLineInfo.window(.object(["used_percentage": .number(10), "resets_at": .number(4_102_444_800_000)]))
        #expect(window == nil)
    }

    @Test func formatsLikeTheStatusLine() {
        #expect(StatsFormat.tokens(465_000) == "465k")
        #expect(StatsFormat.tokens(1_000_000) == "1000k")
        #expect(StatsFormat.duration(65 * 60) == "1h 05m")
        #expect(StatsFormat.duration(4 * 86_400 + 12 * 3600) == "4d 12h")
        #expect(StatsFormat.duration(33 * 60) == "33m")
        #expect(StatsFormat.modelName(fromId: "claude-opus-5-5") == "Opus 5.5")
        #expect(StatsFormat.modelName(fromId: "claude-sonnet-4-5-20250929") == "Sonnet 4.5")
    }
}

struct StatusLineRelayTests {
    private func makeHome(statusLine: String?) throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("m_notch-relay-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        let settings = statusLine.map { #"{"statusLine":{"type":"command","command":"\#($0)","padding":0}}"# } ?? "{}"
        try settings.write(toFile: home + "/.claude/settings.json", atomically: true, encoding: .utf8)
        return home
    }

    private func statusLine(_ home: String) throws -> [String: Any]? {
        let data = try Data(contentsOf: URL(fileURLWithPath: home + "/.claude/settings.json"))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["statusLine"] as? [String: Any]
    }

    @Test func installWrapsTheUsersCommandAndRemoveRestoresItExactly() throws {
        let home = try makeHome(statusLine: "bash ~/.claude/statusline-command.sh")
        #expect(StatusLineRelay.status(port: 47823, token: "t", folder: home + "/.claude") == .missing)
        try HookInstaller.apply(try StatusLineRelay.plan(install: true, port: 47823, token: "t", folder: home + "/.claude"))
        let installed = try #require(try statusLine(home)?["command"] as? String)
        #expect(installed.hasSuffix(#"| bash ~/.claude/statusline-command.sh"#))
        #expect(installed.contains("http://127.0.0.1:47823/m_notch/statusline"))
        #expect(try statusLine(home)?["padding"] as? Int == 0)
        #expect(StatusLineRelay.status(port: 47823, token: "t", folder: home + "/.claude") == .installed)

        try HookInstaller.apply(try StatusLineRelay.plan(install: true, port: 47823, token: "t2", folder: home + "/.claude"))
        let reinstalled = try #require(try statusLine(home)?["command"] as? String)
        #expect(reinstalled.components(separatedBy: "/m_notch/statusline").count == 2)

        try HookInstaller.apply(try StatusLineRelay.plan(install: false, port: 47823, token: "t2", folder: home + "/.claude"))
        #expect(try statusLine(home)?["command"] as? String == "bash ~/.claude/statusline-command.sh")
    }

    @Test func removeWithoutAPreviousStatusLineDropsTheKey() throws {
        let home = try makeHome(statusLine: nil)
        try HookInstaller.apply(try StatusLineRelay.plan(install: true, port: 47823, token: "t", folder: home + "/.claude"))
        try HookInstaller.apply(try StatusLineRelay.plan(install: false, port: 47823, token: "t", folder: home + "/.claude"))
        #expect(try statusLine(home) == nil)
    }
}

@MainActor
struct SessionStatsTests {
    private func makeStore() -> SessionStore {
        let store = SessionStore()
        store.resolveHost = { cwd, _ in (.pycharm, ProjectRoot.Result(path: cwd, marker: ".idea")) }
        store.readContext = { _ in ContextReading(usedTokens: 50_000, window: 200_000, modelId: "claude-haiku-5-5") }
        store.countTools = { _ in 10 }
        store.transcriptCreatedAt = { _ in Date(timeIntervalSince1970: 0) }
        return store
    }

    private func event(_ name: String, tool: String? = nil, question: Bool = false) -> HookEvent {
        let toolField = tool.map { #""tool_name":"\#($0)","tool_input":{"command":"ls","questions":[{"question":"Q?","options":[{"label":"A"},{"label":"B"}]}]},"# } ?? ""
        let body = #"{"hook_event_name":"\#(name)","session_id":"s1","cwd":"/w/app",\#(toolField)"transcript_path":"/t.jsonl"}"#
        return HookEvent(agent: .claude, body: JSONValue.decode(Data(body.utf8))!, hints: HostHints(), isQuestionHook: question)!
    }

    @Test func newSessionStartsFromTheTranscriptAndCountsEachTool() {
        let store = makeStore()
        store.handle(event("UserPromptSubmit"), responder: nil)
        #expect(store.sessions["s1"]?.toolCount == 10)
        #expect(store.sessions["s1"]?.modelName == "Haiku 5.5")
        #expect(store.sessions["s1"]?.contextPercent == 25)
        #expect(store.sessions["s1"]?.startedAt == Date(timeIntervalSince1970: 0))
        store.handle(event("PreToolUse", tool: "Bash"), responder: nil)
        store.handle(event("PreToolUse", tool: "AskUserQuestion"), responder: nil)
        store.handle(event("PreToolUse", tool: "AskUserQuestion", question: true), responder: RecordingResponder())
        #expect(store.sessions["s1"]?.toolCount == 12)
    }

    @Test func statusLineNumbersWinOverTheTranscriptEstimate() throws {
        let store = makeStore()
        store.handle(event("UserPromptSubmit"), responder: nil)
        let resetsAt = Int(Date().timeIntervalSince1970) + 3_600
        let body = #"{"session_id":"s1","model":{"display_name":"Opus 5.5"},"context_window":{"total_input_tokens":400000,"total_output_tokens":65000,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":39,"resets_at":\#(resetsAt)}}}"#
        store.handleStatusLine(StatusLineInfo(body: try #require(JSONValue.decode(Data(body.utf8)))))
        #expect(store.sessions["s1"]?.modelName == "Opus 5.5")
        #expect(store.sessions["s1"]?.contextUsed == 465_000)
        #expect(store.planUsage?.fiveHour?.usedPercent == 39)
        store.handle(event("Stop"), responder: nil)
        #expect(store.sessions["s1"]?.contextUsed == 465_000)
    }

    @Test func requestsGoStraightToTheTerminalWhenAnsweringInTheNotchIsOff() {
        let store = makeStore()
        store.shouldHoldRequests = { false }
        let responder = RecordingResponder()
        store.handle(event("PermissionRequest", tool: "Bash"), responder: responder)
        #expect(store.pending.isEmpty)
        #expect(responder.replies == [nil])
    }
}

struct WindowTitleTests {
    @Test func splitsPyCharmAndVSCodeTitles() {
        #expect(IDEJump.splitTitle("m_notch \u{2013} IslandController.swift").contains("m_notch"))
        #expect(IDEJump.splitTitle("views.py \u{2014} web-app").contains("web-app"))
    }
}
