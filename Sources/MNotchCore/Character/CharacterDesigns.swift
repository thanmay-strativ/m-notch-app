import QuartzCore
import SwiftUI

/// m_notch's own characters on top of the shared engine. Each one changes the body outline and adds head and
/// face parts; the parts sit on the same 3D head as the eyes and hats, so they turn, tilt and squash with it.
enum CharacterDesign: String, CaseIterable, Sendable {
    case pip, neko, bun, boo, beep, momo

    var title: String {
        switch self {
        case .pip: return "Pip"
        case .neko: return "Neko"
        case .bun: return "Bun"
        case .boo: return "Boo"
        case .beep: return "Beep"
        case .momo: return "Momo"
        }
    }

    var tagline: String {
        switch self {
        case .pip: return "bean with a sprout"
        case .neko: return "little cat"
        case .bun: return "floppy bunny"
        case .boo: return "friendly ghost"
        case .beep: return "tiny robot"
        case .momo: return "steamed dumpling"
        }
    }

    /// Superellipse exponent of the body outline: 2 is an ellipse, higher is boxier.
    var bodyExponent: CGFloat {
        switch self {
        case .pip, .bun, .boo: return 2.3
        case .neko: return 2.4
        case .beep: return 3.6
        case .momo: return 2.5
        }
    }

    /// How much wider the bottom is than the top, like a dumpling.
    var bottomFlare: CGFloat {
        switch self {
        case .pip, .bun: return 0.07
        case .momo: return 0.14
        case .neko, .boo, .beep: return 0
        }
    }

    /// Big eyes for every character; Beep's screen eyes are a little smaller to fit its visor.
    var eyeScale: CGFloat { self == .beep ? 1.9 : 2.2 }

    var hasSparkleEyes: Bool { self != .beep }

    var restingBlush: CGFloat {
        switch self {
        case .pip, .neko, .bun: return 0.4
        case .boo: return 0.25
        case .momo: return 0.5
        case .beep: return 0
        }
    }

    /// Sprout, ears, antenna or knot: these turn with the body during a roll and hide under hats that cover the head.
    var hasHeadPart: Bool { self != .boo }

    var floats: Bool { self == .boo }

    var eyeInk: Color { self == .beep ? DesignPalette.screenGlow : Color(cgColor: MochiConst.ink) }

    /// Reads a saved choice. "classic" was the design Momo replaced.
    static func saved(_ rawValue: String) -> CharacterDesign? {
        rawValue == "classic" ? .momo : CharacterDesign(rawValue: rawValue)
    }
}

enum DesignPalette {
    static let screenGlow = Color(hex: "#8BF3FF")
    static let leafLight = Color(hex: "#A6E89A")
    static let leafDark = Color(hex: "#43A859")
    static let stem = Color(hex: "#5DBB63")
    static let innerEar = Color(hex: "#FFB0C4")
    static let nose = Color(hex: "#FF8FAB")
    static let visorTop = Color(hex: "#202838")
    static let visorBottom = Color(hex: "#0D121B")
    static let antenna = Color(hex: "#9AA3AF")
}

extension BotEngine {
    /// Every draw pass in order. With an outfit or a head part, a roll turns the whole character together.
    func render(context: GraphicsContext, size: CGSize) {
        var bodyContext = context
        if rollsRigidly && abs(roll) > 0.001 {
            let center = bodyCenter(size: size)
            bodyContext.translateBy(x: center.x, y: center.y)
            bodyContext.rotate(by: .radians(roll))
            bodyContext.translateBy(x: -center.x, y: -center.y)
        }
        drawHandsBehind(context: bodyContext, size: size)
        drawDesignBehind(context: bodyContext, size: size)
        drawOutfitBehind(context: bodyContext, size: size)
        draw(context: bodyContext, size: size)
        drawOutfitFront(context: bodyContext, size: size)
        drawHandsAndExtras(context: context, size: size)
    }

    /// True while a roll should turn the whole character instead of rolling the eyes around a still body.
    var rollsRigidly: Bool { (outfit != .none && outfitPresence > 0.05) || design.hasHeadPart }

    private var outfitCoversHead: Bool {
        guard outfitPresence > 0.3 else { return false }
        return outfit.hidesHeadPart
    }

    private enum MouthMood { case calm, happy, surprised }

    private var mouthMood: MouthMood {
        switch state {
        case .approval, .question, .error, .dizzy: return .surprised
        case .finished: return .happy
        default: return .calm
        }
    }

    /// Eye size for this frame: the design's scale, plus a boost in the small island so the eyes stay readable.
    func eyeSizeScale(radius: CGFloat) -> CGFloat {
        design.eyeScale * (radius < 14 ? 1.1 : 1)
    }

    /// Gentle hover for floating characters, added to the bounce offset in `update`.
    func designFloat(time: CGFloat) -> CGFloat { design.floats ? sin(time * 2.1) * 0.05 : 0 }

    /// Body outline for the current design; nil means the engine's own superellipse.
    func designBodyPath(rx: CGFloat, ry: CGFloat) -> Path? {
        guard design == .boo else { return nil }
        let exponent = 2 / design.bodyExponent
        let time = CGFloat(CACurrentMediaTime())
        let width = rx * 0.92
        let domeHeight = ry * 1.12
        let hemTop = ry * 0.74
        var path = Path()
        let domeSteps = 48
        for step in 0...domeSteps {
            let angle = .pi + CGFloat(step) / CGFloat(domeSteps) * .pi
            let point = CGPoint(x: width * signedPower(cos(angle), exponent), y: domeHeight * signedPower(sin(angle), exponent))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.addLine(to: CGPoint(x: width, y: hemTop))
        let hemSteps = 72
        for step in 1...hemSteps {
            let progress = CGFloat(step) / CGFloat(hemSteps)
            let scallop = abs(sin(progress * 3 * .pi)) * ry * 0.18
            let ripple = sin(time * 3 + progress * 6) * sin(progress * .pi) * ry * 0.03
            path.addLine(to: CGPoint(x: width * (1 - 2 * progress), y: hemTop + scallop + ripple))
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Behind the body: sprout, ears, tail, antenna, knot and steam

    func drawDesignBehind(context: GraphicsContext, size: CGSize) {
        guard !isMini, design != .boo else { return }
        let radius = size.width * 0.3
        let center = bodyCenter(size: size)
        let head = MochiH(R: radius, yaw: yaw, pitch: pitch, physDx: physDx, physDy: physDy)
        var bodyContext = outfitBodyTransform(context: context, cx: center.x, cy: center.y, tilt: tilt, sx: sx, sy: sy)
        let time = CGFloat(CACurrentMediaTime())
        if design == .neko { drawCatTail(&bodyContext, head: head, time: time) }
        guard design.hasHeadPart, !outfitCoversHead else { return }
        switch design {
        case .pip: drawSprout(&bodyContext, head: head, time: time)
        case .neko: drawCatEars(&bodyContext, head: head, time: time)
        case .bun: drawBunnyEars(&bodyContext, head: head, time: time)
        case .beep: drawAntenna(&bodyContext, head: head, time: time)
        case .momo:
            drawDumplingKnot(&bodyContext, head: head, time: time)
            if state == .working || state == .thinking { drawSteam(&bodyContext, head: head, time: time) }
        case .boo: break
        }
    }

    /// Momo's pinched top: a small twisted peak that pokes out above the head.
    private func drawDumplingKnot(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let root = mProj(head, (0, 0.93, 0.05))
        var knot = context
        knot.translateBy(x: root.x, y: root.y)
        knot.rotate(by: .radians(sin(time * 1.3) * 0.05 - head.physDx * 0.4))
        var peak = Path()
        peak.move(to: CGPoint(x: -radius * 0.22, y: radius * 0.1))
        peak.addQuadCurve(to: CGPoint(x: radius * 0.03, y: -radius * 0.3), control: CGPoint(x: -radius * 0.16, y: -radius * 0.16))
        peak.addQuadCurve(to: CGPoint(x: radius * 0.22, y: radius * 0.1), control: CGPoint(x: radius * 0.17, y: -radius * 0.14))
        peak.closeSubpath()
        knot.fill(peak, with: bodyShading(from: -radius * 0.3, radius: radius))
        var twist = Path()
        twist.move(to: CGPoint(x: -radius * 0.04, y: -radius * 0.16))
        twist.addQuadCurve(to: CGPoint(x: radius * 0.08, y: radius * 0.06), control: CGPoint(x: radius * 0.08, y: -radius * 0.08))
        knot.stroke(twist, with: .color(.black.opacity(0.14)), style: StrokeStyle(lineWidth: max(0.7, radius * 0.035), lineCap: .round))
    }

    /// Three wisps of steam that rise and fade above Momo while it works.
    private func drawSteam(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let top = mProj(head, (0, 1, 0))
        for wisp in 0..<3 {
            let phase = (time * 0.5 + CGFloat(wisp) / 3).truncatingRemainder(dividingBy: 1)
            let side = CGFloat(wisp - 1) * radius * 0.3
            var path = Path()
            for step in 0...12 {
                let progress = CGFloat(step) / 12
                let point = CGPoint(x: top.x + side + sin(progress * 5 + time * 3 + CGFloat(wisp)) * radius * 0.07,
                                    y: top.y - radius * 0.32 - phase * radius * 0.45 - progress * radius * 0.5)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.white.opacity(0.5 * sin(phase * .pi))),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.06), lineCap: .round))
        }
    }

    private func drawSprout(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let root = mProj(head, (0, 0.9, 0.12))
        var sprout = context
        sprout.translateBy(x: root.x, y: root.y)
        sprout.rotate(by: .radians(sin(time * 1.6) * 0.1 - head.physDx * 0.45))
        let stemTop = CGPoint(x: radius * 0.02, y: -radius * 0.34)
        var stem = Path()
        stem.move(to: CGPoint(x: 0, y: radius * 0.1))
        stem.addQuadCurve(to: stemTop, control: CGPoint(x: -radius * 0.06, y: -radius * 0.12))
        sprout.stroke(stem, with: .color(DesignPalette.stem), style: StrokeStyle(lineWidth: max(1, radius * 0.07), lineCap: .round))
        for side: CGFloat in [-1, 1] {
            var leafContext = sprout
            leafContext.translateBy(x: stemTop.x, y: stemTop.y)
            leafContext.rotate(by: .radians(sin(time * 2.3 + side) * 0.08))
            let tip = CGPoint(x: side * radius * 0.36, y: -radius * 0.17)
            var leaf = Path()
            leaf.move(to: .zero)
            leaf.addQuadCurve(to: tip, control: CGPoint(x: side * radius * 0.1, y: -radius * 0.3))
            leaf.addQuadCurve(to: .zero, control: CGPoint(x: side * radius * 0.26, y: radius * 0.04))
            leaf.closeSubpath()
            leafContext.fill(leaf, with: .linearGradient(Gradient(colors: [DesignPalette.leafLight, DesignPalette.leafDark]),
                                                         startPoint: CGPoint(x: 0, y: -radius * 0.25), endPoint: tip))
            var midrib = Path()
            midrib.move(to: .zero)
            midrib.addQuadCurve(to: CGPoint(x: tip.x * 0.8, y: tip.y * 0.8), control: CGPoint(x: side * radius * 0.16, y: -radius * 0.12))
            leafContext.stroke(midrib, with: .color(.white.opacity(0.35)), lineWidth: max(0.5, radius * 0.02))
        }
    }

    private func drawCatEars(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let twitchPhase = time.truncatingRemainder(dividingBy: 4.2)
        for side: CGFloat in [-1, 1] {
            let root = mProj(head, (side * 0.52, 0.8, 0.15))
            var earTilt = side * 0.32 - head.physDx * 0.25
            if side > 0 && twitchPhase < 0.22 { earTilt += sin(twitchPhase / 0.22 * .pi) * 0.3 }
            var ear = context
            ear.translateBy(x: root.x, y: root.y)
            ear.rotate(by: .radians(earTilt))
            ear.fill(catEarPath(radius: radius, scale: 1), with: bodyShading(from: -radius * 0.42, radius: radius))
            ear.stroke(catEarPath(radius: radius, scale: 1), with: .color(.black.opacity(0.06)), lineWidth: 0.8)
            var inner = ear
            inner.translateBy(x: 0, y: radius * 0.04)
            inner.fill(catEarPath(radius: radius, scale: 0.55), with: .color(DesignPalette.innerEar.opacity(0.85)))
        }
    }

    private func catEarPath(radius: CGFloat, scale: CGFloat) -> Path {
        let width = radius * 0.26 * scale
        let height = radius * 0.42 * scale
        var path = Path()
        path.move(to: CGPoint(x: -width, y: radius * 0.12))
        path.addQuadCurve(to: CGPoint(x: -width * 0.15, y: -height * 0.95), control: CGPoint(x: -width * 0.8, y: -height * 0.5))
        path.addQuadCurve(to: CGPoint(x: width * 0.15, y: -height * 0.95), control: CGPoint(x: 0, y: -height * 1.12))
        path.addQuadCurve(to: CGPoint(x: width, y: radius * 0.12), control: CGPoint(x: width * 0.8, y: -height * 0.5))
        path.closeSubpath()
        return path
    }

    private func drawCatTail(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let base = CGPoint(x: head.rx * 0.7 - sin(yaw) * head.rx * 0.3, y: head.ry * 0.6)
        let swish = sin(time * 2.1)
        let tip = CGPoint(x: base.x + radius * (0.62 + swish * 0.1), y: base.y - radius * 0.5)
        var tail = Path()
        tail.move(to: base)
        tail.addCurve(to: tip, control1: CGPoint(x: base.x + radius * 0.5, y: base.y + radius * 0.15),
                      control2: CGPoint(x: tip.x + radius * 0.12 * swish, y: tip.y + radius * 0.35))
        context.stroke(tail, with: .linearGradient(Gradient(colors: [bodyBottom, bodyTop]), startPoint: base, endPoint: tip),
                       style: StrokeStyle(lineWidth: radius * 0.15, lineCap: .round))
    }

    private func drawBunnyEars(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let stretch = 1 - head.physDy * 0.18
        for side: CGFloat in [-1, 1] {
            let root = mProj(head, (side * 0.36, 0.86, 0.1))
            let droop: CGFloat = side > 0 ? 0.42 : -0.1
            var ear = context
            ear.translateBy(x: root.x, y: root.y)
            ear.rotate(by: .radians(droop + sin(time * 1.3 + side) * 0.04 - head.physDx * 0.5))
            ear.scaleBy(x: 1, y: stretch)
            var outer = Path()
            outer.addEllipse(in: CGRect(x: -radius * 0.17, y: -radius * 0.98, width: radius * 0.34, height: radius * 1.1))
            ear.fill(outer, with: bodyShading(from: -radius * 0.98, radius: radius))
            ear.stroke(outer, with: .color(.black.opacity(0.06)), lineWidth: 0.8)
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -radius * 0.08, y: -radius * 0.84, width: radius * 0.16, height: radius * 0.72))
            ear.fill(inner, with: .color(DesignPalette.innerEar.opacity(0.75)))
        }
    }

    private func drawAntenna(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let root = mProj(head, (0, 0.92, 0.05))
        var antenna = context
        antenna.translateBy(x: root.x, y: root.y)
        antenna.rotate(by: .radians(-head.physDx * 0.5 + sin(time * 1.8) * 0.05))
        var stem = Path()
        stem.move(to: CGPoint(x: 0, y: radius * 0.1))
        stem.addLine(to: CGPoint(x: 0, y: -radius * 0.36))
        antenna.stroke(stem, with: .color(DesignPalette.antenna), style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        let bulbCenter = CGPoint(x: 0, y: -radius * 0.44)
        let bulbRadius = radius * 0.11
        let light = state == .idle || state == .sleeping ? DesignPalette.screenGlow : Color(red: col.0, green: col.1, blue: col.2)
        let glowRadius = radius * 0.32
        antenna.fill(Path(ellipseIn: CGRect(x: -glowRadius, y: bulbCenter.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                     with: .radialGradient(Gradient(colors: [light.opacity(0.45 + 0.2 * Double(sin(time * 3))), .clear]),
                                           center: bulbCenter, startRadius: 0, endRadius: glowRadius))
        antenna.fill(Path(ellipseIn: CGRect(x: -bulbRadius, y: bulbCenter.y - bulbRadius, width: bulbRadius * 2, height: bulbRadius * 2)),
                     with: .color(light))
        let shine = bulbRadius * 0.4
        antenna.fill(Path(ellipseIn: CGRect(x: -bulbRadius * 0.45, y: bulbCenter.y - bulbRadius * 0.6, width: shine, height: shine)),
                     with: .color(.white.opacity(0.8)))
    }

    /// Body gradient for parts attached to the head, starting at `top` so their color matches the top of the body.
    private func bodyShading(from top: CGFloat, radius: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [bodyTop, bodyBottom]),
                        startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + radius * 2.6))
    }

    // MARK: - On the face: visor, mouth, nose, whiskers

    /// Where a point on the face lands, using the same math as the eyes. `lift` is negative below the eyes.
    func faceSpot(lift: CGFloat, rx: CGFloat, ry: CGFloat) -> (point: CGPoint, squash: CGFloat, isVisible: Bool) {
        var facePitch = MochiConst.eyeP + pitch + lift + (rollsRigidly ? 0 : roll)
        facePitch = atan2(sin(facePitch), cos(facePitch))
        let pitchCos = cos(facePitch)
        return (CGPoint(x: sin(yaw) * pitchCos * rx, y: -sin(facePitch) * ry), max(0.2, cos(yaw)), cos(yaw) * pitchCos > 0.15)
    }

    /// Drawn after the body and before the eyes, inside the body outline.
    func drawDesignUnderlay(context: GraphicsContext, bodyPath: Path, R radius: CGFloat, rx: CGFloat, ry: CGFloat) {
        guard !isMini, morph < 0.5 else { return }
        var context = context
        context.clip(to: bodyPath)
        switch design {
        case .beep: drawVisor(context, R: radius, rx: rx, ry: ry)
        case .momo where !outfitCoversHead: drawPleats(context, radius: radius)
        default: break
        }
    }

    /// Momo's folds: seven lines that run up the top of the head and gather at the knot. Folds on the far side hide.
    private func drawPleats(_ context: GraphicsContext, radius: CGFloat) {
        let head = MochiH(R: radius, yaw: yaw, pitch: pitch)
        let lineWidth = max(0.7, radius * 0.035)
        for index in 0..<7 {
            let longitude = (CGFloat(index) - 3) * 0.45
            var fold = Path()
            var isDrawing = false
            for step in 0...10 {
                let progress = CGFloat(step) / 10
                let point = mProj(head, mSurf(0.56 + progress * 0.41, longitude * (1 - progress * 0.8)))
                if point.z > 0.05 {
                    let location = CGPoint(x: point.x, y: point.y)
                    if isDrawing { fold.addLine(to: location) } else { fold.move(to: location) }
                    isDrawing = true
                } else {
                    isDrawing = false
                }
            }
            context.stroke(fold, with: .color(.black.opacity(0.12)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            var highlight = context
            highlight.translateBy(x: lineWidth, y: 0)
            highlight.stroke(fold, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round))
        }
    }

    private func drawVisor(_ context: GraphicsContext, R radius: CGFloat, rx: CGFloat, ry: CGFloat) {
        let spot = faceSpot(lift: -0.04, rx: rx, ry: ry)
        guard spot.isVisible else { return }
        let width = radius * 1.36 * spot.squash
        let visor = Path(roundedRect: CGRect(x: spot.point.x - width / 2, y: spot.point.y - radius * 0.42, width: width, height: radius * 0.84),
                         cornerRadius: radius * 0.24)
        context.fill(visor, with: .linearGradient(Gradient(colors: [DesignPalette.visorTop, DesignPalette.visorBottom]),
                                                  startPoint: CGPoint(x: 0, y: spot.point.y - radius * 0.42),
                                                  endPoint: CGPoint(x: 0, y: spot.point.y + radius * 0.42)))
        context.stroke(visor, with: .color(.white.opacity(0.1)), lineWidth: 0.8)
    }

    /// Drawn after the eyes. The context is not clipped, so whiskers can reach past the body edge.
    func drawDesignFace(context: GraphicsContext, R radius: CGFloat, rx: CGFloat, ry: CGFloat) {
        guard !isMini, morph < 0.5 else { return }
        let lineWidth = max(0.8, radius * 0.035)
        if design == .neko && radius > 12 { drawWhiskers(context, radius: radius, rx: rx, lineWidth: lineWidth) }
        if design == .neko || design == .bun {
            let nose = faceSpot(lift: -0.4, rx: rx, ry: ry)
            if nose.isVisible { drawNose(context, at: nose.point, squash: nose.squash, radius: radius) }
        }
        let mouth = faceSpot(lift: design == .pip || design == .beep ? -0.46 : -0.5, rx: rx, ry: ry)
        guard mouth.isVisible else { return }
        var mouthContext = context
        mouthContext.translateBy(x: mouth.point.x, y: mouth.point.y)
        mouthContext.scaleBy(x: mouth.squash, y: 1)
        drawMouth(&mouthContext, radius: radius, lineWidth: lineWidth)
    }

    private func drawMouth(_ context: inout GraphicsContext, radius: CGFloat, lineWidth: CGFloat) {
        let ink = design.eyeInk
        switch mouthMood {
        case .surprised:
            context.fill(Path(ellipseIn: CGRect(x: -radius * 0.05, y: -radius * 0.06, width: radius * 0.1, height: radius * 0.12)),
                         with: .color(ink))
        case .happy:
            var grin = Path()
            grin.move(to: CGPoint(x: -radius * 0.1, y: 0))
            grin.addLine(to: CGPoint(x: radius * 0.1, y: 0))
            grin.addQuadCurve(to: CGPoint(x: -radius * 0.1, y: 0), control: CGPoint(x: 0, y: radius * 0.17))
            context.fill(grin, with: .color(ink))
        case .calm:
            switch design {
            case .neko, .bun:
                let scale: CGFloat = design == .bun ? 0.8 : 1
                var smile = Path()
                smile.move(to: CGPoint(x: -radius * 0.11 * scale, y: 0))
                smile.addQuadCurve(to: .zero, control: CGPoint(x: -radius * 0.055 * scale, y: radius * 0.08 * scale))
                smile.addQuadCurve(to: CGPoint(x: radius * 0.11 * scale, y: 0), control: CGPoint(x: radius * 0.055 * scale, y: radius * 0.08 * scale))
                context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            case .boo:
                context.fill(Path(ellipseIn: CGRect(x: -radius * 0.05, y: -radius * 0.06, width: radius * 0.1, height: radius * 0.12)),
                             with: .color(ink))
            case .momo:
                var smile = Path()
                smile.move(to: CGPoint(x: -radius * 0.08, y: -radius * 0.01))
                smile.addQuadCurve(to: CGPoint(x: radius * 0.08, y: -radius * 0.01), control: CGPoint(x: 0, y: radius * 0.15))
                smile.closeSubpath()
                context.fill(smile, with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: -radius * 0.035, y: radius * 0.035, width: radius * 0.07, height: radius * 0.035)),
                             with: .color(DesignPalette.nose))
            case .pip, .beep:
                var smile = Path()
                smile.move(to: CGPoint(x: -radius * 0.07, y: 0))
                smile.addQuadCurve(to: CGPoint(x: radius * 0.07, y: 0), control: CGPoint(x: 0, y: radius * 0.08))
                context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }

    private func drawNose(_ context: GraphicsContext, at point: CGPoint, squash: CGFloat, radius: CGFloat) {
        let width = radius * (design == .neko ? 0.09 : 0.08) * squash
        let height = radius * 0.055
        var nose = Path()
        if design == .neko {
            nose.move(to: CGPoint(x: point.x - width / 2, y: point.y - height / 2))
            nose.addLine(to: CGPoint(x: point.x + width / 2, y: point.y - height / 2))
            nose.addLine(to: CGPoint(x: point.x, y: point.y + height / 2))
            nose.closeSubpath()
        } else {
            nose.addEllipse(in: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height))
        }
        context.fill(nose, with: .color(DesignPalette.nose))
    }

    private func drawWhiskers(_ context: GraphicsContext, radius: CGFloat, rx: CGFloat, lineWidth: CGFloat) {
        let turn = sin(yaw) * rx * 0.8
        for side: CGFloat in [-1, 1] {
            for slant: CGFloat in [-1, 1] {
                let start = CGPoint(x: side * rx * 0.66 + turn, y: radius * (0.5 + slant * 0.05))
                var whisker = Path()
                whisker.move(to: start)
                whisker.addLine(to: CGPoint(x: start.x + side * radius * 0.36, y: start.y + slant * radius * 0.08))
                context.stroke(whisker, with: .color(design.eyeInk.opacity(0.5)),
                               style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round))
            }
        }
    }

    /// Two white glints that make the eyes look glossy. Skipped when the eye is nearly closed or tiny.
    func drawEyeSparkle(_ context: inout GraphicsContext, width: CGFloat, height: CGFloat, radius: CGFloat) {
        guard design.hasSparkleEyes, height > width * 0.7, radius > 9 else { return }
        let big = width * 0.2
        let small = width * 0.09
        context.fill(Path(ellipseIn: CGRect(x: -width * 0.16 - big, y: -height * 0.24 - big, width: big * 2, height: big * 2)),
                     with: .color(.white.opacity(0.95)))
        context.fill(Path(ellipseIn: CGRect(x: width * 0.14 - small, y: height * 0.18 - small, width: small * 2, height: small * 2)),
                     with: .color(.white.opacity(0.85)))
    }
}

private func signedPower(_ value: CGFloat, _ exponent: CGFloat) -> CGFloat {
    value >= 0 ? pow(value, exponent) : -pow(-value, exponent)
}
