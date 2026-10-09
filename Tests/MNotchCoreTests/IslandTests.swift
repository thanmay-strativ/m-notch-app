import Foundation
import Testing
@testable import MNotchCore

struct IslandGeometryTests {
    @Test func notchWidthIsTheGapBetweenTheTwoMenuBarAreas() {
        let geometry = IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: 664,
                                            auxiliaryRightWidth: 664, menuBarHeight: 32)
        #expect(geometry == IslandScreenGeometry(screenWidth: 1, safeAreaTop: 32, auxiliaryLeftWidth: nil,
                                                 auxiliaryRightWidth: nil, menuBarHeight: 0))
        #expect(geometry.width == 184 && geometry.height == 32 && geometry.hasNotch)
    }

    @Test func screenWithoutNotchGetsTheSmallBar() {
        let geometry = IslandScreenGeometry(screenWidth: 1920, safeAreaTop: 0, auxiliaryLeftWidth: nil,
                                            auxiliaryRightWidth: nil, menuBarHeight: 37)
        #expect(!geometry.hasNotch)
        #expect(geometry.width == 80 && geometry.height == 24)
    }

    @Test func expandedHeightStaysBetween160And560() {
        #expect(IslandLayout.expandedHeight(for: .list(rows: 1, rowHeight: 44), notchHeight: 32) == 160)
        #expect(IslandLayout.expandedHeight(for: .list(rows: 20, rowHeight: 58), notchHeight: 32) == 560)
        #expect(IslandLayout.size(mode: .compact, notchWidth: 184, notchHeight: 32, expandedHeight: 300)
                == CGSize(width: 344, height: 32))
    }

    @Test func smallIslandLooksStraightWhenThePointerIsInTheScreenCenter() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let botOnScreen = CGPoint(x: 704, y: 966)
        #expect(IslandLayout.lookOrigin(mode: .compact, botOnScreen: botOnScreen, screenFrame: screenFrame)
                == CGPoint(x: 756, y: 491))
        #expect(IslandLayout.lookOrigin(mode: .expanded, botOnScreen: botOnScreen, screenFrame: screenFrame) == botOnScreen)
    }
}

@MainActor
final class ManualScheduler {
    private(set) var delays: [TimeInterval] = []
    private var work: [DispatchWorkItem] = []

    var schedule: (TimeInterval, DispatchWorkItem) -> Void {
        { [unowned self] delay, item in
            delays.append(delay)
            work.append(item)
        }
    }

    func fireAll() {
        let pending = work
        work.removeAll()
        pending.filter { !$0.isCancelled }.forEach { $0.perform() }
    }
}

@MainActor
struct PermissionCardSizeTests {
    @Test func longCommandsCountTheirWrappedLinesAndScrollPastSixteen() {
        #expect(IslandLayout.wrappedLineCount("ls -la") == 1)
        #expect(IslandLayout.wrappedLineCount(String(repeating: "x", count: 400)) == 7)
        #expect(IslandLayout.wrappedLineCount("a\n\nb") == 3)
        let shortCard = IslandLayout.expandedHeight(for: .permission(commandLines: 2, hasRisk: false), notchHeight: 32)
        let wrappedCard = IslandLayout.expandedHeight(for: .permission(commandLines: 8, hasRisk: false), notchHeight: 32)
        #expect(wrappedCard - shortCard == 6 * IslandLayout.codeLineHeight)
        #expect(IslandLayout.codeBlockHeight(lines: 200) == IslandLayout.codeBlockHeight(lines: IslandLayout.maxCodeLines))
        #expect(IslandLayout.expandedHeight(for: .permission(commandLines: 200, hasRisk: true), notchHeight: 32) < IslandLayout.maxExpandedHeight)
    }
}

@MainActor
struct IslandStateMachineTests {
    private func makeMachine() -> (IslandStateMachine, ManualScheduler, () -> [IslandStateMachine.State]) {
        let scheduler = ManualScheduler()
        let machine = IslandStateMachine(schedule: scheduler.schedule)
        var transitions: [IslandStateMachine.State] = []
        machine.onTransition = { _, newState in transitions.append(newState) }
        return (machine, scheduler, { transitions })
    }

    @Test func hoverPeeksAndClickOpens() {
        let (machine, _, transitions) = makeMachine()
        machine.mouseEntered()
        machine.click()
        #expect(transitions() == [.compact, .expanded])
    }

    @Test func leavingShrinksAfterTheCloseDelayAndStaysCompactLonger() {
        let (machine, scheduler, transitions) = makeMachine()
        var current = Date(timeIntervalSince1970: 0)
        machine.now = { current }
        machine.mouseEntered()
        machine.click()
        machine.mouseLeft()
        #expect(scheduler.delays.last == 0.5)
        current = current.addingTimeInterval(0.5)
        scheduler.fireAll()
        #expect(transitions() == [.compact, .expanded, .compact])
        #expect(scheduler.delays.last == 5)
        current = current.addingTimeInterval(5)
        scheduler.fireAll()
        #expect(transitions() == [.compact, .expanded, .compact, .hidden])
    }

    @Test func leavingGoesBackToCompactWhileAnAgentWorks() {
        let (machine, scheduler, _) = makeMachine()
        var current = Date(timeIntervalSince1970: 0)
        machine.now = { current }
        var isBusy = true
        machine.isBusy = { isBusy }
        machine.mouseEntered()
        machine.click()
        machine.mouseLeft()
        current = current.addingTimeInterval(60)
        scheduler.fireAll()
        #expect(machine.state == .compact)
        isBusy = false
        scheduler.fireAll()
        #expect(machine.state == .hidden)
    }

    @Test func pendingRequestKeepsTheIslandOpen() {
        let (machine, scheduler, _) = makeMachine()
        var isHeld = true
        machine.isHeldOpen = { isHeld }
        machine.expand()
        scheduler.fireAll()
        #expect(machine.state == .expanded)
        isHeld = false
        machine.settleSoon()
        scheduler.fireAll()
        #expect(machine.state == .hidden)
    }

    @Test func openOnHoverSkipsThePeek() {
        let (machine, _, transitions) = makeMachine()
        machine.openOnHover = true
        machine.mouseEntered()
        #expect(transitions() == [.expanded])
    }

    @Test func pointerInsideNeverAutoCloses() {
        let (machine, scheduler, _) = makeMachine()
        machine.mouseEntered()
        machine.click()
        machine.settleSoon()
        scheduler.fireAll()
        #expect(machine.state == .expanded)
    }
}

@MainActor
struct CompactHoldPreferenceTests {
    @Test func compactHoldStaysLongerThanTheCloseDelay() throws {
        let suiteName = "m_notch-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.compactHold == 5)
        preferences.closeDelay = 15
        #expect(preferences.compactHold == 30)
        #expect(preferences.compactHoldOptions == [30, 60])
        preferences.closeDelay = 0.5
        #expect(preferences.compactHold == 30)
        #expect(preferences.compactHoldOptions.first == 3)
    }
}

@MainActor
struct CharacterPreferenceTests {
    @Test func newInstallsStartWithPipAndAPickIsSaved() throws {
        let suiteName = "m_notch-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(Preferences(defaults: defaults).character == .pip)
        Preferences(defaults: defaults).character = .neko
        #expect(Preferences(defaults: defaults).character == .neko)
        defaults.set("dragon", forKey: "character")
        #expect(Preferences(defaults: defaults).character == .pip)
    }

    @Test func everyCharacterIsOurOwnDesignAndClassicBecameMomo() {
        #expect(CharacterDesign.allCases.map(\.rawValue) == ["pip", "neko", "bun", "boo", "beep", "momo"])
        #expect(CharacterDesign.saved("classic") == .momo)
        #expect(CharacterDesign.saved("neko") == .neko && CharacterDesign.saved("mochi") == nil)
        #expect(CharacterDesign.momo.hasHeadPart && CharacterDesign.momo.hasSparkleEyes)
    }

    @Test func charactersHaveTheirOwnFaceNotMochis() {
        let withIris = CharacterDesign.allCases.filter { $0.iris != nil }
        #expect(withIris == [.pip, .neko, .bun, .boo, .momo])
        #expect(CharacterDesign.allCases.filter { $0.restingBlush > 0 } == [.bun])
        #expect(Set(CharacterDesign.allCases.map { "\($0.bodyScale.width)x\($0.bodyScale.height)" }).count >= 5)
    }

    @MainActor
    @Test func theOldMochiColorIsNowPearl() {
        let defaults = UserDefaults(suiteName: "m_notch-pearl-test")!
        defaults.set("mochi", forKey: "characterColor")
        #expect(Preferences(defaults: defaults).characterColor == .pearl)
        #expect(Preferences.CharacterColor.allCases.map(\.title).contains("Pearl"))
        #expect(!Preferences.CharacterColor.allCases.map(\.title).contains("Mochi"))
        defaults.removePersistentDomain(forName: "m_notch-pearl-test")
    }
}

struct ConfigFolderTests {
    @Test func defaultsToTheAgentsOwnVariableThenTheHomeFolder() {
        #expect(HookTarget.claude.defaultFolder(home: "/Users/me", environment: [:]) == "/Users/me/.claude")
        #expect(HookTarget.codex.defaultFolder(home: "/Users/me", environment: [:]) == "/Users/me/.codex")
        #expect(HookTarget.claude.defaultFolder(home: "/Users/me", environment: ["CLAUDE_CONFIG_DIR": "/work/claude"]) == "/work/claude")
        #expect(HookTarget.codex.defaultFolder(home: "/Users/me", environment: ["CODEX_HOME": ""]) == "/Users/me/.codex")
        #expect(HookTarget.codex.fileURL(folder: "/work/codex").path == "/work/codex/hooks.json")
    }

    @MainActor
    @Test func aTypedFolderWinsAndTildeIsExpanded() {
        let defaults = UserDefaults(suiteName: "m_notch-folder-test")!
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.configFolder(for: .claude) == HookTarget.claude.defaultFolder())
        preferences.claudeFolder = "  ~/work/claude-config "
        #expect(preferences.configFolder(for: .claude) == NSHomeDirectory() + "/work/claude-config")
        #expect(preferences.configFolder(for: .codex) == HookTarget.codex.defaultFolder())
        #expect(Preferences(defaults: defaults).claudeFolder == "  ~/work/claude-config ")
        defaults.removePersistentDomain(forName: "m_notch-folder-test")
    }
}

@MainActor
struct HiddenRequestTests {
    @Test func clickingAWaitingSessionShowsItsOwnRequest() throws {
        let store = SessionStore()
        store.resolveHost = { cwd, _ in (.pycharm, ProjectRoot.Result(path: cwd, marker: ".idea")) }
        store.readContext = { _ in nil }
        store.countTools = { _ in 0 }
        store.transcriptCreatedAt = { _ in nil }
        for sessionId in ["s1", "s2"] {
            let body = #"{"hook_event_name":"PermissionRequest","session_id":"\#(sessionId)","cwd":"/w/\#(sessionId)","tool_name":"Bash","tool_input":{"command":"ls"},"transcript_path":"/t.jsonl"}"#
            store.handle(HookEvent(agent: .claude, body: JSONValue.decode(Data(body.utf8))!, hints: HostHints())!, responder: RecordingResponder())
        }
        let suiteName = "m_notch-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = IslandModel()
        model.requestsHidden = true
        let actions = IslandActions(store: store, model: model, preferences: Preferences(defaults: defaults))

        actions.showRequestOrJump(to: try #require(store.sessions["s2"]))

        #expect(!model.requestsHidden)
        #expect(IslandLayout.shownRequest(model: model, store: store)?.sessionId == "s2")
        #expect(store.pending.count == 2)
    }

    @Test func backShowsTheSessionListWhileTheRequestKeepsWaiting() {
        let store = SessionStore()
        store.resolveHost = { cwd, _ in (.pycharm, ProjectRoot.Result(path: cwd, marker: ".idea")) }
        store.readContext = { _ in nil }
        store.countTools = { _ in 0 }
        store.transcriptCreatedAt = { _ in nil }
        let body = #"{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/w/app","tool_name":"Bash","tool_input":{"command":"ls"},"transcript_path":"/t.jsonl"}"#
        let responder = RecordingResponder()
        store.handle(HookEvent(agent: .claude, body: JSONValue.decode(Data(body.utf8))!, hints: HostHints())!, responder: responder)
        let model = IslandModel()
        #expect(IslandLayout.expandedContent(model: model, store: store) == .permission(commandLines: 1, hasRisk: false))

        model.requestsHidden = true

        #expect(IslandLayout.expandedContent(model: model, store: store) == .list(rows: 1, rowHeight: IslandLayout.rowHeight))
        #expect(IslandLayout.shownRequest(model: model, store: store) == nil)
        #expect(store.pending.count == 1)
        #expect(responder.replies.isEmpty)
    }
}

struct HookInstallerTests {
    private func makeHome(settings: String?) throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("m_notch-tests-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        if let settings { try settings.write(toFile: home + "/.claude/settings.json", atomically: true, encoding: .utf8) }
        return home
    }

    private func hooks(_ home: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: home + "/.claude/settings.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["hooks"] as? [String: Any])
    }

    @Test func keepsUserSettingsAndHooksAndBacksUp() throws {
        let home = try makeHome(settings: #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        #expect(HookInstaller.status(for: .claude, port: 47823, token: "t1", folder: home + "/.claude") == .missing)
        let plan = try HookInstaller.plan(for: .claude, port: 47823, token: "t1", folder: home + "/.claude")
        let backup = try #require(try HookInstaller.apply(plan))
        #expect(FileManager.default.fileExists(atPath: backup.path))
        let stopGroups = try #require(try hooks(home)["Stop"] as? [[String: Any]])
        #expect(stopGroups.count == 2)
        #expect(plan.preview.contains(#""model" : "opus""#))
        #expect(HookInstaller.status(for: .claude, port: 47823, token: "t1", folder: home + "/.claude") == .installed)
    }

    @Test func reinstallReplacesOurEntriesInsteadOfDuplicating() throws {
        let home = try makeHome(settings: nil)
        try HookInstaller.apply(try HookInstaller.plan(for: .claude, port: 47823, token: "old", folder: home + "/.claude"))
        #expect(HookInstaller.status(for: .claude, port: 47823, token: "new", folder: home + "/.claude") == .outdated)
        try HookInstaller.apply(try HookInstaller.plan(for: .claude, port: 47823, token: "new", folder: home + "/.claude"))
        let preToolUse = try #require(try hooks(home)["PreToolUse"] as? [[String: Any]])
        #expect(preToolUse.count == 2)
        #expect(HookInstaller.status(for: .claude, port: 47823, token: "new", folder: home + "/.claude") == .installed)
    }

    @Test func refusesInvalidJsonAndAFileChangedAfterThePreview() throws {
        let brokenHome = try makeHome(settings: "{ not json")
        #expect(throws: SettingsFileWriter.Failure.self) {
            try HookInstaller.plan(for: .claude, port: 47823, token: "t", folder: brokenHome + "/.claude")
        }
        let home = try makeHome(settings: "{}")
        let plan = try HookInstaller.plan(for: .claude, port: 47823, token: "t", folder: home + "/.claude")
        try #"{"edited":true}"#.write(toFile: home + "/.claude/settings.json", atomically: true, encoding: .utf8)
        #expect(throws: SettingsFileWriter.Failure.changed(home + "/.claude/settings.json")) {
            try HookInstaller.apply(plan)
        }
    }

    @Test func codexHookIsACurlCommandThatNeverFails() throws {
        let command = try #require(HookInstaller.codexEntries(port: 47823, token: "t")["PermissionRequest"]?
            .first?["hooks"] as? [[String: Any]]).first?["command"] as? String
        #expect(command?.hasSuffix("http://127.0.0.1:47823/m_notch/codex || true") == true)
        #expect(command?.contains("X-Host: $__CFBundleIdentifier") == true)
    }
}
