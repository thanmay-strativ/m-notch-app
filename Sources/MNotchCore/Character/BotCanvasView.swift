// Ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import SwiftUI

/// TimelineView drives a Canvas that asks BotEngine for the next frame. Paused while the island is hidden.
struct BotCanvasView: View {
    let model: IslandModel
    let preferences: Preferences
    var particleOverhang: CGFloat = 0
    @StateObject private var engine = BotEngine()

    var body: some View {
        TimelineView(.animation(paused: model.mode == .hidden)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                engine.lookX = model.look.x
                engine.lookY = model.look.y
                engine.tgEs = model.botHovered ? 1.08 : 1
                engine.particleOverhang = particleOverhang
                let gradient = preferences.characterColor.gradientHex
                engine.bodyTop = Color(hex: gradient.top)
                engine.bodyBottom = Color(hex: gradient.bottom)
                engine.design = preferences.character
                engine.setOutfit(Outfit.resolved(selection: preferences.outfit, date: timeline.date, calendar: .current))
                engine.update(dt: min(0.05, now - engine.lastTime))
                engine.render(context: context, size: size)
            }
        }
        .onChange(of: model.botState) { _, newState in engine.setState(newState) }
        .onChange(of: model.pokeCount) { _, _ in engine.reactToClick() }
        .onChange(of: model.emoteCount) { _, _ in engine.triggerEmote(model.lastEmote) }
        .onAppear {
            engine.setState(model.botState, force: true)
            engine.onDizzy = { [engine] in
                engine.setState(.dizzy)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
                    MainActor.assumeIsolated { engine.setState(model.botState) }
                }
            }
        }
    }
}
