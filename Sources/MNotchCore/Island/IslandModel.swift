import Foundation
import Observation

/// What the island views draw: its mode, size inputs and the character's mood.
@MainActor
@Observable
final class IslandModel {
    var mode: IslandStateMachine.State = .hidden
    var notchWidth: CGFloat = IslandScreenGeometry.fallbackNotchWidth
    var notchHeight: CGFloat = 32
    var hasNotch = true
    var botState: BotState = .idle
    var botHovered = false
    var openDiff: OpenDiff?
    var showingSettings = false
    var showingCalendar = false
    var showingMusic = false
    /// Back on a request card: the list shows and the island may shrink, but the request keeps waiting.
    var requestsHidden = false
    /// The request picked from the session list; the oldest one shows when nothing is picked or it is gone.
    var focusedRequestId: UUID?
    var rowHeight: CGFloat = IslandLayout.rowHeight
    /// Set while a meeting starts within the hour (Settings > Extras > Calendar).
    var nextMeeting: CalendarEvent?
    /// The day the calendar tab shows (start of day), every event of its week, and which way the last change went.
    var calendarDay = Calendar.current.startOfDay(for: Date())
    var weekEvents: [CalendarEvent] = []
    var calendarMovingForward = true
    /// What macOS reports as playing, while anything is (Settings > Extras > Now playing).
    var nowPlaying: NowPlayingTrack?
    private(set) var pokeCount = 0
    private(set) var emoteCount = 0
    private(set) var lastEmote: BotEmote = .happy
    private(set) var bounceCount = 0
    private(set) var optionPickCount = 0
    private(set) var lastOptionPick = 0

    @ObservationIgnored var look: CGPoint = .zero

    struct OpenDiff: Equatable {
        let sessionId: String
        let diffId: UUID
    }

    init() {}

    func poke() { pokeCount += 1 }

    func emote(_ emote: BotEmote) {
        lastEmote = emote
        emoteCount += 1
    }

    func bounce() { bounceCount += 1 }

    func pickOption(_ index: Int) {
        lastOptionPick = index
        optionPickCount += 1
    }
}

/// Island sizes and character placement, in island coordinates (origin top-left).
enum IslandLayout {
    static let panelSize = CGSize(width: 720, height: 560)
    static let expandedWidth: CGFloat = 640
    static let minExpandedHeight: CGFloat = 160
    static let maxExpandedHeight: CGFloat = 560
    static let compactEarWidth: CGFloat = 80
    static let compactCorner: CGFloat = 14
    static let expandedCorner: CGFloat = 22
    static let contentLeading: CGFloat = 112
    static let rowHeight: CGFloat = 44
    static let rowHeightWithStats: CGFloat = 58
    /// A one-line meeting or terminal command row above the sessions, spacing included.
    static let bannerHeight: CGFloat = 34
    /// Calendar tab: week strip plus day title, one event row, the all-day chips, the now line (spacing included).
    static let calendarHeaderHeight: CGFloat = 74
    static let calendarEventHeight: CGFloat = 42
    static let calendarAllDayHeight: CGFloat = 26
    static let calendarNowLineHeight: CGFloat = 14
    /// Music tab: artwork, title lines, progress and controls.
    static let musicContentHeight: CGFloat = 120
    static let codeLineHeight: CGFloat = 15
    static let maxCodeLines = 16
    static let codeCharactersPerLine = 60

    enum ExpandedContent: Equatable {
        case list(rows: Int, rowHeight: CGFloat, banners: Int = 0)
        case permission(commandLines: Int, hasRisk: Bool)
        case question(estimatedHeight: CGFloat)
        case plan
        case diff
        case settings
        case calendar(timedEvents: Int, hasAllDay: Bool, hasNowLine: Bool)
        case music
    }

    static func headerHeight(notchHeight: CGFloat) -> CGFloat { max(notchHeight, 28) }

    /// Lines a command takes in the card once long lines wrap (about 60 monospaced characters per line).
    static func wrappedLineCount(_ text: String) -> Int {
        text.components(separatedBy: "\n").reduce(0) { total, line in
            total + max(1, (line.count + codeCharactersPerLine - 1) / codeCharactersPerLine)
        }
    }

    static func codeBlockHeight(lines: Int) -> CGFloat { CGFloat(min(max(lines, 1), maxCodeLines)) * codeLineHeight + 10 }

    static func contentTop(notchHeight: CGFloat) -> CGFloat { headerHeight(notchHeight: notchHeight) + 6 }

    static func expandedHeight(for content: ExpandedContent, notchHeight: CGFloat) -> CGFloat {
        let top = contentTop(notchHeight: notchHeight)
        let height: CGFloat
        switch content {
        case .list(let rows, let rowHeight, let banners):
            height = top + CGFloat(max(rows, 1)) * rowHeight + CGFloat(banners) * bannerHeight + 14
        case .permission(let lines, let hasRisk): height = top + 91 + codeBlockHeight(lines: lines) + (hasRisk ? 22 : 0)
        case .question(let estimated): height = estimated + top - 8
        case .plan: height = 420
        case .diff: height = 320
        case .settings: height = top + 260
        case .calendar(let timedEvents, let hasAllDay, let hasNowLine):
            height = top + calendarHeaderHeight + CGFloat(max(timedEvents, 1)) * calendarEventHeight
                + (hasAllDay ? calendarAllDayHeight : 0) + (hasNowLine ? calendarNowLineHeight : 0) + 14
        case .music: height = top + musicContentHeight + 14
        }
        return min(max(height, minExpandedHeight), maxExpandedHeight)
    }

    static func size(mode: IslandStateMachine.State, notchWidth: CGFloat, notchHeight: CGFloat,
                            expandedHeight: CGFloat) -> CGSize {
        switch mode {
        case .hidden: return CGSize(width: notchWidth, height: notchHeight)
        case .compact: return CGSize(width: notchWidth + compactEarWidth * 2, height: notchHeight)
        case .expanded: return CGSize(width: expandedWidth, height: expandedHeight)
        }
    }

    struct BotPlacement: Equatable {
        let center: CGPoint
        let diameter: CGFloat
        let opacity: Double
    }

    static func botPlacement(mode: IslandStateMachine.State, islandSize: CGSize, notchHeight: CGFloat,
                                    hasNotch: Bool) -> BotPlacement {
        let restingDiameter = min(20, max(0, islandSize.height - 6))
        switch mode {
        case .hidden:
            return hasNotch
                ? BotPlacement(center: CGPoint(x: 46, y: 16), diameter: 6, opacity: 0)
                : BotPlacement(center: CGPoint(x: islandSize.width / 2, y: islandSize.height / 2), diameter: restingDiameter, opacity: 0)
        case .compact:
            return BotPlacement(center: CGPoint(x: 40, y: islandSize.height / 2), diameter: restingDiameter, opacity: 1)
        case .expanded:
            let top = contentTop(notchHeight: notchHeight)
            let centerY = min(top + 54, top + (islandSize.height - top) / 2)
            return BotPlacement(center: CGPoint(x: 58, y: centerY), diameter: 54, opacity: 1)
        }
    }

    /// Where the pointer must be, in screen points, for the character to look straight at you. While small it
    /// measures from the screen's center, so a pointer in the middle of the screen gets a straight look.
    /// While open, the big character measures from itself, so hovering it still gets a look straight at you.
    static func lookOrigin(mode: IslandStateMachine.State, botOnScreen: CGPoint, screenFrame: CGRect) -> CGPoint {
        mode == .expanded ? botOnScreen : CGPoint(x: screenFrame.midX, y: screenFrame.midY)
    }
}
