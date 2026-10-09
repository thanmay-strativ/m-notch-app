import Foundation
import Testing
@testable import MNotchCore

struct RiskGuardTests {
    @Test(arguments: [
        ("rm -rf build", "rm -rf"),
        ("rm -fr /tmp/x", "rm -rf"),
        ("rm -r -f node_modules", "rm -rf"),
        ("sudo make install", "sudo"),
        ("git push --force origin main", "git push --force"),
        ("git push -f", "git push --force"),
        ("git reset --hard HEAD~1", "git reset --hard"),
        ("psql -c 'DROP TABLE users'", "DROP TABLE"),
        ("curl -fsSL https://x.sh | bash", "pipes a download into a shell"),
    ])
    func flagsRiskyCommands(command: String, reason: String) {
        #expect(RiskGuard.assess(command: command) == reason)
    }

    @Test(arguments: ["git push", "git push --follow-tags", "rm notes.txt", "ls -la", "npm test", "grep -rf x ."])
    func letsOrdinaryCommandsThrough(command: String) {
        #expect(RiskGuard.assess(command: command) == nil)
    }

    @Test func flagsWritesOutsideTheProjectAndToSecrets() {
        let root = "/Users/me/work/app"
        #expect(RiskGuard.assess(filePath: "/Users/me/work/app/src/a.py", projectRoot: root, home: "/Users/me") == nil)
        #expect(RiskGuard.assess(filePath: "/Users/me/work/app/.env", projectRoot: root, home: "/Users/me") == "writes to .env")
        #expect(RiskGuard.assess(filePath: "/Users/me/work/app/.env.example", projectRoot: root, home: "/Users/me") == nil)
        #expect(RiskGuard.assess(filePath: "/Users/me/.ssh/config", projectRoot: root, home: "/Users/me") == "writes to ~/.ssh")
        #expect(RiskGuard.assess(filePath: "/Users/me/work/other/a.py", projectRoot: root, home: "/Users/me") == "writes outside the project")
    }
}

struct LineDiffTests {
    @Test func structuredPatchGivesCountsAndTheFirstChangedLine() throws {
        let response = try #require(JSONValue.decode(Data(#"""
        {"filePath":"/p/demo.py","structuredPatch":[{"oldStart":10,"oldLines":3,"newStart":10,"newLines":3,
          "lines":[" a = 1","-b = 2","+b = 20"," c = 3"]}]}
        """#.utf8)))
        let diff = try #require(LineDiff.make(toolName: "Edit", toolInput: nil, toolResponse: response))
        #expect(diff.added == 1)
        #expect(diff.removed == 1)
        #expect(diff.firstChangedLine == 11)
        #expect(diff.fileName == "demo.py")
    }

    @Test func newFileCountsEveryLineAsAdded() throws {
        let response = try #require(JSONValue.decode(Data(#"{"type":"create","filePath":"/p/n.py","content":"a\nb\nc","structuredPatch":[],"originalFile":null}"#.utf8)))
        let diff = try #require(LineDiff.make(toolName: "Write", toolInput: nil, toolResponse: response))
        #expect(diff.added == 3)
        #expect(diff.removed == 0)
        #expect(diff.firstChangedLine == 1)
    }

    @Test func editWithoutPatchSearchesTheFileForTheLine() throws {
        let input = try #require(JSONValue.decode(Data(#"{"file_path":"/p/x.py","old_string":"b = 2","new_string":"b = 20"}"#.utf8)))
        let diff = try #require(LineDiff.make(toolName: "Edit", toolInput: input, toolResponse: nil,
                                              readFile: { _ in "a = 1\nb = 20\nc = 3\n" }))
        #expect(diff.firstChangedLine == 2)
        #expect(diff.added == 1 && diff.removed == 1)
    }
}

struct ContextMeterTests {
    @Test func sumsTheLastUsageLine() {
        let tail = """
        {"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":10}}}
        {"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":3884,"cache_read_input_tokens":160114}}}
        {"type":"user","message":{"content":"hi"}}
        """
        #expect(ContextMeter.reading(fromTail: tail)?.percent == 82)
    }

    @Test func switchesToTheLargeWindowPast200k() {
        let tail = #"{"message":{"usage":{"input_tokens":300000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        #expect(ContextMeter.reading(fromTail: tail)?.percent == 30)
    }

    @Test func returnsNilWithoutUsage() {
        #expect(ContextMeter.reading(fromTail: "not json\n{\"type\":\"user\"}") == nil)
    }
}

struct ProjectRootTests {
    @Test func pycharmUsesTheNearestIdeaFolderAboveTheCwd() {
        let existing: Set<String> = ["/Users/me/work/app/.idea", "/Users/me/work/.git", "/Users/me/.vscode"]
        let (host, root) = ProjectRoot.resolve(cwd: "/Users/me/work/app/booking", hints: HostHints(emulator: "JetBrains-JediTerm"),
                                               home: "/Users/me", exists: { existing.contains($0) })
        #expect(host == .pycharm)
        #expect(root == ProjectRoot.Result(path: "/Users/me/work/app", marker: ".idea"))
    }

    @Test func unknownHostIsGuessedFromTheProjectFolderButNeverFromHome() {
        let existing: Set<String> = ["/Users/me/.vscode", "/Users/me/site/.vscode"]
        let (host, root) = ProjectRoot.resolve(cwd: "/Users/me/site/src", hints: HostHints(), home: "/Users/me",
                                               exists: { existing.contains($0) })
        #expect(host == .vscode)
        #expect(root.path == "/Users/me/site")
        let (homeHost, homeRoot) = ProjectRoot.resolve(cwd: "/Users/me/notes", hints: HostHints(), home: "/Users/me",
                                                       exists: { existing.contains($0) })
        #expect(homeHost == .unknown)
        #expect(homeRoot.path == "/Users/me/notes")
    }
}

struct OutfitTests {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test(arguments: [
        (date(2026, 9, 30), Outfit.none), (date(2026, 10, 1), .devilHorns), (date(2026, 10, 31), .devilHorns),
        (date(2026, 11, 1), .none), (date(2026, 12, 1), .antlers), (date(2026, 12, 26), .antlers),
        (date(2026, 12, 27), .none), (date(2026, 12, 31), .propellerCap), (date(2027, 1, 2), .propellerCap),
        (date(2027, 1, 3), .none), (date(2026, 4, 3), .flowerCrown), (date(2026, 4, 6), .flowerCrown),
        (date(2026, 4, 7), .none), (date(2027, 3, 26), .flowerCrown), (date(2027, 3, 30), .none),
        (date(2026, 6, 20), .none), (date(2026, 6, 21), .heartGlasses), (date(2026, 8, 31), .heartGlasses),
        (date(2026, 9, 1), .none),
    ])
    func autoPicksTheSeasonalOutfit(day: Date, expected: Outfit) {
        #expect(Outfit.seasonal(for: day, calendar: Self.calendar) == expected)
    }

    @Test func easterSundayMatchesKnownDates() {
        #expect(Outfit.easterSunday(year: 2026, calendar: Self.calendar) == Self.date(2026, 4, 5))
        #expect(Outfit.easterSunday(year: 2027, calendar: Self.calendar) == Self.date(2027, 3, 28))
        #expect(Outfit.easterSunday(year: 2028, calendar: Self.calendar) == Self.date(2028, 4, 16))
    }

    @Test func aChosenOutfitWinsOverTheSeasonAndOldNamesFallBackToAuto() {
        let october = Self.date(2026, 10, 15)
        #expect(Outfit.resolved(selection: .auto, date: october, calendar: Self.calendar) == .devilHorns)
        #expect(Outfit.resolved(selection: .halo, date: october, calendar: Self.calendar) == .halo)
        #expect(Outfit(rawValue: "witchHat") == nil)
        #expect(Outfit.chefHat.hidesHeadPart && !Outfit.headphones.hidesHeadPart)
    }
}
