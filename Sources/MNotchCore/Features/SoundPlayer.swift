import AppKit

/// Plays a macOS system sound for island events. Off by default; coucou's own sounds are not ours to ship.
@MainActor
enum SoundPlayer {
    static func play(_ choice: Preferences.SoundChoice, volume: Double) {
        guard choice != .none, let sound = NSSound(named: NSSound.Name(choice.rawValue))?.copy() as? NSSound else { return }
        sound.volume = Float(volume)
        sound.play()
    }
}
