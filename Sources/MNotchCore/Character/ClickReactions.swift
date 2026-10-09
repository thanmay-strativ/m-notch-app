import QuartzCore

/// What the character does when clicked: one of these at random, never the same twice in a row.
/// Three quick clicks still make it dizzy.
enum ClickReaction: CaseIterable {
    case spin, hearts, wave, starJump
}

extension BotEngine {
    func reactToClick() {
        interruptGreet()
        guard state != .dizzy else { return }
        let now = CACurrentMediaTime()
        slapTimes = slapTimes.filter { now - $0 < 1.7 }
        slapTimes.append(now)
        if slapTimes.count >= 3 {
            slapTimes = []
            squash()
            onDizzy?()
            return
        }
        let reaction = ClickReaction.allCases.filter { $0 != lastClickReaction }.randomElement() ?? .hearts
        lastClickReaction = reaction
        play(reaction)
    }

    private func play(_ reaction: ClickReaction) {
        let now = CACurrentMediaTime()
        switch reaction {
        case .spin:
            eyeOverride = .happy
            eyeOverrideUntil = now + 1.1
            doRoll(duration: 700, turns: 1)
        case .hearts:
            triggerEmote(.love, duration: 1.6)
        case .wave:
            greet()
        case .starJump:
            eyeOverride = .star
            eyeOverrideUntil = now + 1.2
            squash()
            emit(.star, count: 5)
            anim("oy", keys: [
                TweenKey(target: -0.4, duration: 180, ease: Ease.out),
                TweenKey(target: 0, duration: 420, ease: Ease.back),
            ])
        }
    }
}
