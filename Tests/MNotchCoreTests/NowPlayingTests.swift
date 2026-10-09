import Foundation
import Testing
@testable import MNotchCore

struct NowPlayingTests {
    private let reportedAt = Date(timeIntervalSince1970: 1_791_549_494)

    private func line(title: String = "Bye Kartos", playing: Any = 1, rate: Double = 1, artwork: String? = nil,
                      duration: String = "189.06") -> Data {
        let artworkField = artwork.map { #","artwork":"\#($0)""# } ?? ""
        let json = #"{"title":"\#(title)","artist":"KaanPhod Music","album":"","duration":\#(duration),"elapsed":10,"#
            + #""elapsedAt":\#(reportedAt.timeIntervalSince1970),"rate":\#(rate),"playing":\#(playing),"app":"com.google.Chrome"\#(artworkField)}"#
        return Data(json.utf8)
    }

    @Test func readsAHelperLine() throws {
        let artwork = Data([0xFF, 0xD8, 0xFF]).base64EncodedString()
        let track = try #require(try NowPlayingTrack.parse(line: line(artwork: artwork), previous: nil))
        #expect(track.title == "Bye Kartos" && track.artist == "KaanPhod Music")
        #expect(track.isPlaying && track.appBundleId == "com.google.Chrome")
        #expect(track.duration == 189.06)
        #expect(track.artwork == Data([0xFF, 0xD8, 0xFF]))
        #expect(try NowPlayingTrack.parse(line: line(playing: "true"), previous: nil)?.isPlaying == true)
    }

    @Test func artworkCarriesOverUntilTheHelperSendsANewOne() throws {
        let first = try NowPlayingTrack.parse(line: line(artwork: Data([1, 2]).base64EncodedString()), previous: nil)
        let unchanged = try NowPlayingTrack.parse(line: line(title: "Next song"), previous: first)
        #expect(unchanged?.artwork == Data([1, 2]))
        let cleared = try NowPlayingTrack.parse(line: line(title: "No cover", artwork: ""), previous: unchanged)
        #expect(cleared?.artwork == nil)
    }

    @Test func emptyTitleMeansNothingPlaysAndBrokenLinesThrow() throws {
        #expect(try NowPlayingTrack.parse(line: line(title: " "), previous: nil) == nil)
        #expect(throws: NowPlayingTrack.ParseError.self) { try NowPlayingTrack.parse(line: Data("not json".utf8), previous: nil) }
    }

    @Test func positionMovesWhilePlayingAndStopsAtTheEnd() throws {
        let track = try #require(try NowPlayingTrack.parse(line: line(), previous: nil))
        #expect(track.position(at: reportedAt.addingTimeInterval(5)) == 15)
        #expect(track.position(at: reportedAt.addingTimeInterval(500)) == 189.06)
        let paused = try #require(try NowPlayingTrack.parse(line: line(playing: 0, rate: 0), previous: nil))
        #expect(paused.position(at: reportedAt.addingTimeInterval(60)) == 10)
        let live = try #require(try NowPlayingTrack.parse(line: line(duration: "null"), previous: nil))
        #expect(live.duration == nil && live.position(at: reportedAt.addingTimeInterval(500)) == 510)
    }

    @Test func playPauseKeepsThePosition() throws {
        let playing = try #require(try NowPlayingTrack.parse(line: line(), previous: nil))
        let paused = playing.toggled(now: reportedAt.addingTimeInterval(20))
        #expect(!paused.isPlaying && paused.position(at: reportedAt.addingTimeInterval(90)) == 30)
        let resumed = try #require(try NowPlayingTrack.parse(line: line(playing: 0, rate: 0), previous: nil))
            .toggled(now: reportedAt.addingTimeInterval(60))
        #expect(resumed.isPlaying && resumed.rate == 1)
        #expect(resumed.position(at: reportedAt.addingTimeInterval(64)) == 14)
    }

    @Test func seekingMovesThePositionWithinTheTrack() throws {
        let track = try #require(try NowPlayingTrack.parse(line: line(), previous: nil))
        let seekTime = reportedAt.addingTimeInterval(3)
        #expect(track.seeked(to: 120, now: seekTime).position(at: seekTime.addingTimeInterval(2)) == 122)
        #expect(track.seeked(to: 999, now: seekTime).position(at: seekTime) == 189.06)
        #expect(track.seeked(to: -5, now: seekTime).position(at: seekTime) == 0)
        #expect(NowPlayingCommand.seek(83.456).line == "seek 83.46")
        #expect(NowPlayingCommand.seek(-2).line == "seek 0.00")
        #expect(NowPlayingCommand.toggle.line == "toggle")
    }

    @MainActor
    @Test func seekingFromTheIslandMovesTheBarAtOnceAndTellsTheHelper() throws {
        let model = IslandModel()
        let actions = IslandActions(store: SessionStore(), model: model, preferences: Preferences(defaults: UserDefaults(suiteName: "m_notch-seek-test")!))
        var sentCommands: [NowPlayingCommand] = []
        actions.onMediaCommand = { sentCommands.append($0) }
        model.nowPlaying = try NowPlayingTrack.parse(line: line(), previous: nil)
        actions.sendMediaCommand(.seek(150))
        #expect(sentCommands == [.seek(150)])
        #expect(try #require(model.nowPlaying).position(at: Date()) >= 150)
    }

    @Test func clockReadsLikeAPlayer() {
        #expect(NowPlayingTrack.clock(83.7) == "1:23")
        #expect(NowPlayingTrack.clock(5) == "0:05")
        #expect(NowPlayingTrack.clock(3723) == "1:02:03")
        #expect(NowPlayingTrack.clock(-4) == "0:00")
    }

    @Test func musicTabHasAFixedHeight() {
        let top = IslandLayout.contentTop(notchHeight: 32)
        #expect(IslandLayout.expandedHeight(for: .music, notchHeight: 32)
                == max(IslandLayout.minExpandedHeight, top + IslandLayout.musicContentHeight + 14))
    }
}
