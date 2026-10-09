import SwiftUI

/// A live, animated character for settings, drawn by the same engine and passes as the island.
/// When `interactive`, its eyes follow the mouse over it and a click plays a reaction; otherwise it ignores the mouse,
/// so a button around it gets the click.
struct CharacterPreview: View {
    let design: CharacterDesign
    let color: Preferences.CharacterColor
    let outfit: Outfit
    let width: CGFloat
    /// Room above the body for ears, hats and reaction particles, as a fraction of `width`.
    var headroom: CGFloat = 0.45
    var interactive = false
    var framesPerSecond: Double = 60
    @StateObject private var engine = BotEngine()
    @State private var look = CGPoint.zero

    private var height: CGFloat { width * (1 + headroom) }
    private var bodyCenterY: CGFloat { width * (0.5 + headroom) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / framesPerSecond)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                engine.design = design
                engine.bodyTop = Color(hex: color.gradientHex.top)
                engine.bodyBottom = Color(hex: color.gradientHex.bottom)
                engine.particleOverhang = size.height - size.width
                engine.lookX = look.x
                engine.lookY = look.y
                engine.setOutfit(Outfit.resolved(selection: outfit, date: timeline.date, calendar: .current))
                engine.update(dt: min(0.05, now - engine.lastTime))
                engine.render(context: context, size: size)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                look = CGPoint(x: tanh((location.x - width / 2) / (width * 0.8)),
                               y: tanh((bodyCenterY - location.y) / (width * 0.8)))
            case .ended:
                look = .zero
            }
        }
        .onTapGesture { engine.reactToClick() }
        .allowsHitTesting(interactive)
        .onAppear { engine.setState(.idle, force: true) }
    }
}
