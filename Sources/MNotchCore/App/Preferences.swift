import Foundation
import Observation

/// Every user setting, saved to UserDefaults on change. Read by the island, the settings window and the menu.
@MainActor
@Observable
final class Preferences {
    enum CharacterColor: String, CaseIterable {
        case terracotta, mochi, sky, mint, lilac, rose, sunny, graphite

        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        var gradientHex: (top: String, bottom: String) {
            switch self {
            case .terracotta: return ("#F0A88C", "#C9653F")
            case .mochi: return ("#EDEDEF", "#C4C5CA")
            case .sky: return ("#9CCBFF", "#3B82F6")
            case .mint: return ("#A7F3D0", "#10B981")
            case .lilac: return ("#D8C7FF", "#8B5CF6")
            case .rose: return ("#FBCFE8", "#EC4899")
            case .sunny: return ("#FDE68A", "#F59E0B")
            case .graphite: return ("#9CA3AF", "#4B5563")
            }
        }
    }

    enum SoundChoice: String, CaseIterable {
        case none = "None"
        case glass = "Glass", ping = "Ping", pop = "Pop", purr = "Purr", tink = "Tink"
        case hero = "Hero", submarine = "Submarine", funk = "Funk", bottle = "Bottle", morse = "Morse"
    }

    static let closeDelayChoices: [TimeInterval] = [0.5, 1, 2, 5, 15]
    static let compactHoldChoices: [TimeInterval] = [3, 5, 10, 30, 60]

    @ObservationIgnored private let defaults: UserDefaults

    var openOnHover: Bool { didSet { save(openOnHover, "openOnHover") } }
    var closeDelay: TimeInterval {
        didSet {
            save(closeDelay, "closeDelay")
            keepCompactHoldLongerThanCloseDelay()
        }
    }
    var compactHold: TimeInterval { didSet { save(compactHold, "compactHold") } }
    var activityHold: TimeInterval { didSet { save(activityHold, "activityHold") } }
    var displayChoice: IslandDisplayChoice { didSet { save(displayChoice.rawValue, "displayChoice") } }
    var launchAtLogin: Bool { didSet { save(launchAtLogin, "launchAtLogin") } }

    var showCharacter: Bool { didSet { save(showCharacter, "showCharacter") } }
    var character: CharacterDesign { didSet { save(character.rawValue, "character") } }
    var characterColor: CharacterColor { didSet { save(characterColor.rawValue, "characterColor") } }
    var outfit: Outfit { didSet { save(outfit.rawValue, "outfit") } }
    var showGlow: Bool { didSet { save(showGlow, "showGlow") } }
    var showSessionStats: Bool { didSet { save(showSessionStats, "showSessionStats") } }
    var showPlanUsage: Bool { didSet { save(showPlanUsage, "showPlanUsage") } }
    var showDiffChips: Bool { didSet { save(showDiffChips, "showDiffChips") } }

    var revealOnActivity: Bool { didSet { save(revealOnActivity, "revealOnActivity") } }
    var revealOnFinish: Bool { didSet { save(revealOnFinish, "revealOnFinish") } }
    var quietWhenLooking: Bool { didSet { save(quietWhenLooking, "quietWhenLooking") } }
    var answerInNotch: Bool { didSet { save(answerInNotch, "answerInNotch") } }
    var touchIdForRisky: Bool { didSet { save(touchIdForRisky, "touchIdForRisky") } }
    var raiseExactWindow: Bool { didSet { save(raiseExactWindow, "raiseExactWindow") } }
    var keepAwake: Bool { didSet { save(keepAwake, "keepAwake") } }
    var nudgeEnabled: Bool { didSet { save(nudgeEnabled, "nudgeEnabled") } }
    var showCalendar: Bool { didSet { save(showCalendar, "showCalendar") } }
    var showNowPlaying: Bool { didSet { save(showNowPlaying, "showNowPlaying") } }
    var autoCheckUpdates: Bool { didSet { save(autoCheckUpdates, "autoCheckUpdates") } }

    var soundsEnabled: Bool { didSet { save(soundsEnabled, "soundsEnabled") } }
    var needsYouSound: SoundChoice { didSet { save(needsYouSound.rawValue, "needsYouSound") } }
    var finishedSound: SoundChoice { didSet { save(finishedSound.rawValue, "finishedSound") } }
    var soundVolume: Double { didSet { save(soundVolume, "soundVolume") } }

    var shortcutsEnabled: Bool { didSet { save(shortcutsEnabled, "shortcutsEnabled") } }
    var toggleIslandShortcut: Bool { didSet { save(toggleIslandShortcut, "toggleIslandShortcut") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }
        func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
        openOnHover = bool("openOnHover", false)
        closeDelay = double("closeDelay", 0.5)
        compactHold = double("compactHold", 5)
        activityHold = double("activityHold", 60)
        displayChoice = IslandDisplayChoice(rawValue: string("displayChoice")) ?? .followMouse
        launchAtLogin = bool("launchAtLogin", false)
        showCharacter = bool("showCharacter", true)
        character = CharacterDesign.saved(string("character")) ?? .pip
        characterColor = CharacterColor(rawValue: string("characterColor")) ?? .terracotta
        outfit = Outfit(rawValue: string("outfit")) ?? .auto
        showGlow = bool("showGlow", true)
        showSessionStats = bool("showSessionStats", true)
        showPlanUsage = bool("showPlanUsage", true)
        showDiffChips = bool("showDiffChips", true)
        revealOnActivity = bool("revealOnActivity", true)
        revealOnFinish = bool("revealOnFinish", true)
        quietWhenLooking = bool("quietWhenLooking", true)
        answerInNotch = bool("answerInNotch", true)
        touchIdForRisky = bool("touchIdForRisky", true)
        raiseExactWindow = bool("raiseExactWindow", false)
        keepAwake = bool("keepAwake", true)
        nudgeEnabled = bool("nudgeEnabled", true)
        showCalendar = bool("showCalendar", false)
        showNowPlaying = bool("showNowPlaying", true)
        autoCheckUpdates = bool("autoCheckUpdates", true)
        soundsEnabled = bool("soundsEnabled", false)
        needsYouSound = SoundChoice(rawValue: string("needsYouSound")) ?? .glass
        finishedSound = SoundChoice(rawValue: string("finishedSound")) ?? .pop
        soundVolume = double("soundVolume", 0.6)
        shortcutsEnabled = bool("shortcutsEnabled", true)
        toggleIslandShortcut = bool("toggleIslandShortcut", true)
    }

    /// The compact island always stays longer than the close delay, so it never just blinks.
    var compactHoldOptions: [TimeInterval] { Self.compactHoldChoices.filter { $0 > closeDelay } }

    private func keepCompactHoldLongerThanCloseDelay() {
        guard compactHold <= closeDelay, let longer = compactHoldOptions.first else { return }
        compactHold = longer
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
