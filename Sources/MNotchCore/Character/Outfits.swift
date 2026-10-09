import QuartzCore
import SwiftUI

/// m_notch's own outfits. Each one sits on the shared 3D head, so it turns, tilts and squashes with the character,
/// and each has a small animation of its own.
enum Outfit: String, CaseIterable, Sendable {
    case auto, none, propellerCap, headphones, flowerCrown, gradCap, halo, devilHorns, antlers, heartGlasses, chefHat, headband

    var displayName: String {
        switch self {
        case .auto: return "Auto (seasons)"
        case .none: return "None"
        case .propellerCap: return "Propeller cap"
        case .headphones: return "Headphones"
        case .flowerCrown: return "Flower crown"
        case .gradCap: return "Graduation cap"
        case .halo: return "Halo"
        case .devilHorns: return "Devil horns"
        case .antlers: return "Antlers"
        case .heartGlasses: return "Heart glasses"
        case .chefHat: return "Chef hat"
        case .headband: return "Ninja headband"
        }
    }

    /// Caps, horns and antlers take the spot of a sprout, ears or antenna, so those hide while it is worn.
    var hidesHeadPart: Bool {
        switch self {
        case .propellerCap, .gradCap, .chefHat, .devilHorns, .antlers: return true
        default: return false
        }
    }

    /// Devil horns in October, antlers in December, a propeller cap around New Year,
    /// a flower crown around Easter and heart glasses in summer.
    static func seasonal(for date: Date, calendar: Calendar) -> Outfit {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if (month == 12 && day == 31) || (month == 1 && day <= 2) { return .propellerCap }
        if month == 12 && day <= 26 { return .antlers }
        if month == 10 { return .devilHorns }
        if let easter = easterSunday(year: calendar.component(.year, from: date), calendar: calendar),
           let daysFromEaster = calendar.dateComponents([.day], from: calendar.startOfDay(for: easter),
                                                        to: calendar.startOfDay(for: date)).day,
           (-2...1).contains(daysFromEaster) {
            return .flowerCrown
        }
        if (month == 6 && day >= 21) || month == 7 || month == 8 { return .heartGlasses }
        return .none
    }

    static func resolved(selection: Outfit, date: Date, calendar: Calendar) -> Outfit {
        selection == .auto ? seasonal(for: date, calendar: calendar) : selection
    }

    /// Gregorian Easter Sunday (the anonymous Gregorian computus).
    static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let goldenNumber = year % 19
        let century = year / 100
        let yearInCentury = year % 100
        let skippedLeapDays = century / 4
        let centuryRemainder = century % 4
        let moonCorrection = (century + 8) / 25
        let solarCorrection = (century - moonCorrection + 1) / 3
        let epact = (19 * goldenNumber + century - skippedLeapDays - solarCorrection + 15) % 30
        let leapYears = yearInCentury / 4
        let yearRemainder = yearInCentury % 4
        let weekdayOffset = (32 + 2 * centuryRemainder + 2 * leapYears - epact - yearRemainder) % 7
        let lateShift = (goldenNumber + 11 * epact + 22 * weekdayOffset) / 451
        let monthAndDay = epact + weekdayOffset - 7 * lateShift + 114
        return calendar.date(from: DateComponents(year: year, month: monthAndDay / 31, day: monthAndDay % 31 + 1))
    }
}

private enum OutfitPalette {
    static let capRed = Color(hex: "#FF6B6B")
    static let capRedDark = Color(hex: "#D64545")
    static let capYellow = Color(hex: "#FFD166")
    static let capBlue = Color(hex: "#4CC9F0")
    static let capGreen = Color(hex: "#06D6A0")
    static let navy = Color(hex: "#2B2D42")
    static let gear = Color(hex: "#2E3440")
    static let gearLight = Color(hex: "#4C566A")
    static let cushion = Color(hex: "#FF8FAB")
    static let vine = Color(hex: "#5BAF5E")
    static let petals = [Color.white, Color(hex: "#FFB3C7"), Color(hex: "#CDB4FF")]
    static let gradTop = Color(hex: "#2C3E66")
    static let gradSide = Color(hex: "#141C30")
    static let gold = Color(hex: "#F5C451")
    static let haloLight = Color(hex: "#FFE58A")
    static let haloDeep = Color(hex: "#F5B700")
    static let hornLight = Color(hex: "#FF6B6B")
    static let hornDeep = Color(hex: "#C1121F")
    static let antler = Color(hex: "#9C6B43")
    static let lens = Color(hex: "#FF5C8A")
    static let lensFrame = Color(hex: "#E11D74")
    static let chefShade = Color(hex: "#E3E7EE")
    static let chefLine = Color(hex: "#CDD3DC")
    static let headband = Color(hex: "#E63946")
    static let headbandDark = Color(hex: "#A4161A")
}

extension BotEngine {
    // MARK: - Passes

    func drawOutfitBehind(context: GraphicsContext, size: CGSize) {
        guard let stage = outfitStage(context: context, size: size) else { return }
        var outfitContext = stage.context
        let head = stage.head
        let time = CGFloat(CACurrentMediaTime())
        switch outfit {
        case .headphones: drawHeadphoneCups(&outfitContext, head: head, front: false)
        case .flowerCrown: drawFlowerCrown(&outfitContext, head: head, time: time, front: false)
        case .antlers: drawAntlers(&outfitContext, head: head, time: time)
        case .headband: drawHeadbandTails(&outfitContext, head: head, time: time)
        default: break
        }
    }

    func drawOutfitFront(context: GraphicsContext, size: CGSize) {
        guard let stage = outfitStage(context: context, size: size) else { return }
        var outfitContext = stage.context
        let head = stage.head
        let time = CGFloat(CACurrentMediaTime())
        switch outfit {
        case .propellerCap: drawPropellerCap(&outfitContext, head: head, time: time)
        case .headphones:
            drawHeadphoneBand(&outfitContext, head: head)
            drawHeadphoneCups(&outfitContext, head: head, front: true)
            drawMusicNotes(&outfitContext, head: head, time: time)
        case .flowerCrown: drawFlowerCrown(&outfitContext, head: head, time: time, front: true)
        case .gradCap: drawGradCap(&outfitContext, head: head, time: time)
        case .halo: drawHalo(&outfitContext, head: head, time: time)
        case .devilHorns: drawDevilHorns(&outfitContext, head: head)
        case .antlers: drawRedNose(&outfitContext, head: head, time: time)
        case .heartGlasses: drawHeartGlasses(&outfitContext, head: head, time: time)
        case .chefHat: drawChefHat(&outfitContext, head: head)
        case .headband: drawHeadband(&outfitContext, head: head)
        case .auto, .none: break
        }
    }

    /// Body-space context for the outfit, fading and dropping in from above while it arrives.
    private func outfitStage(context: GraphicsContext, size: CGSize) -> (context: GraphicsContext, head: MochiH)? {
        guard outfit != .none, outfit != .auto, !isMini, outfitPresence > 0.01, morph < 0.5 else { return nil }
        let radius = size.width * 0.3
        let center = bodyCenter(size: size)
        let head = MochiH(R: radius, yaw: yaw, pitch: pitch, physDx: physDx, physDy: physDy)
        var outfitContext = outfitBodyTransform(context: context, cx: center.x, cy: center.y, tilt: tilt, sx: sx, sy: sy)
        outfitContext.opacity = Double(min(1, outfitPresence * 2.5))
        outfitContext.translateBy(x: 0, y: -(1 - Ease.back(outfitPresence)) * head.ry)
        return (context: outfitContext, head: head)
    }

    private var isBusy: Bool { state == .working || state == .thinking || state == .searching }

    // MARK: - Head geometry helpers

    /// A horizontal ring around the head at height `y`, `scale` times the head's width there. Point 0 faces the viewer.
    private func ring(_ head: MochiH, y: CGFloat, scale: CGFloat, steps: Int = 48) -> [P3] {
        (0...steps).map { step in mProj(head, mSurf(y, CGFloat(step) / CGFloat(steps) * 2 * .pi - .pi, scale)) }
    }

    /// The part of a ring facing the viewer, left to right.
    private func frontArc(_ points: [P3]) -> [P3] { points.filter { $0.z >= 0 }.sorted { $0.x < $1.x } }

    /// Everything above the front edge of a ring: what a cap covers.
    private func regionAbove(_ arc: [P3], head: MochiH) -> Path {
        guard let first = arc.first, let last = arc.last else { return Path() }
        var region = Path()
        region.move(to: CGPoint(x: first.x - head.rx, y: first.y))
        for point in arc { region.addLine(to: CGPoint(x: point.x, y: point.y)) }
        region.addLine(to: CGPoint(x: last.x + head.rx, y: last.y))
        region.addLine(to: CGPoint(x: last.x + head.rx, y: -head.ry * 4))
        region.addLine(to: CGPoint(x: first.x - head.rx, y: -head.ry * 4))
        region.closeSubpath()
        return region
    }

    private func polyline(_ points: [P3]) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            if index == 0 { path.move(to: CGPoint(x: point.x, y: point.y)) } else { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        }
        return path
    }

    /// The character's own head outline, a little larger, clipped above a ring: a cap that hugs any character.
    private func fillCap(_ context: GraphicsContext, head: MochiH, bandHeight: CGFloat, shading: GraphicsContext.Shading) -> Path {
        var capContext = context
        let edge = frontArc(ring(head, y: bandHeight, scale: 1.05))
        capContext.clip(to: regionAbove(edge, head: head))
        let outline = mochiPath(rx: head.rx * 1.05, ry: head.ry * 1.05, morph: 0, R: head.R)
        capContext.fill(outline, with: shading)
        capContext.fill(outline, with: .radialGradient(Gradient(colors: [.white.opacity(0.35), .clear]),
                                                       center: CGPoint(x: head.rx * 0.3, y: -head.ry * 0.8),
                                                       startRadius: 0, endRadius: head.R * 0.6))
        return polyline(edge)
    }

    // MARK: - Propeller cap

    private func drawPropellerCap(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let band = fillCap(context, head: head, bandHeight: 0.45,
                           shading: .linearGradient(Gradient(colors: [OutfitPalette.capRed, OutfitPalette.capRedDark]),
                                                    startPoint: CGPoint(x: 0, y: -head.ry), endPoint: CGPoint(x: 0, y: 0)))
        var panelContext = context
        panelContext.clip(to: regionAbove(frontArc(ring(head, y: 0.45, scale: 1.05)), head: head))
        panelContext.clip(to: mochiPath(rx: head.rx * 1.05, ry: head.ry * 1.05, morph: 0, R: head.R))
        for (center, color) in [(CGFloat(0), OutfitPalette.capYellow), (.pi / 2, OutfitPalette.capBlue), (-.pi / 2, OutfitPalette.capGreen)] {
            let left = (0...10).map { step in mProj(head, mSurf(0.45 + CGFloat(step) * 0.055, center - 0.4, 1.06)) }
            let right = (0...10).map { step in mProj(head, mSurf(0.45 + CGFloat(step) * 0.055, center + 0.4, 1.06)) }
            let panel = (left + right.reversed()).filter { $0.z > -0.05 }
            guard panel.count > 4 else { continue }
            var panelPath = polyline(panel)
            panelPath.closeSubpath()
            panelContext.fill(panelPath, with: .color(color))
        }
        context.stroke(band, with: .color(OutfitPalette.navy), style: StrokeStyle(lineWidth: radius * 0.1, lineCap: .round))

        let top = mProj(head, (0, 1.02, 0))
        let hub = CGPoint(x: top.x, y: top.y - radius * 0.16)
        var stem = Path()
        stem.move(to: CGPoint(x: top.x, y: top.y))
        stem.addLine(to: hub)
        context.stroke(stem, with: .color(OutfitPalette.navy), style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        let spin = time * (isBusy ? 18 : 5) + yaw
        let blades = [(spin, OutfitPalette.capYellow), (spin + .pi, OutfitPalette.capBlue)].sorted { sin($0.0) < sin($1.0) }
        for (angle, color) in blades {
            var blade = Path()
            blade.move(to: hub)
            blade.addLine(to: CGPoint(x: hub.x + cos(angle) * radius * 0.42, y: hub.y + sin(angle) * radius * 0.13))
            context.stroke(blade, with: .color(color), style: StrokeStyle(lineWidth: radius * 0.11, lineCap: .round))
        }
        let hubRadius = radius * 0.05
        context.fill(Path(ellipseIn: CGRect(x: hub.x - hubRadius, y: hub.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)),
                     with: .color(OutfitPalette.capRed))
    }

    // MARK: - Headphones

    private func drawHeadphoneBand(_ context: inout GraphicsContext, head: MochiH) {
        let heights = stride(from: 0.15, through: 1.08, by: 0.06).map { CGFloat($0) }
        let leftSide = heights.map { height in mProj(head, (-mRingR(height) * 1.1, height, 0)) }
        let rightSide = heights.reversed().map { height in mProj(head, (mRingR(height) * 1.1, height, 0)) }
        let band = polyline(leftSide + rightSide)
        context.stroke(band, with: .color(OutfitPalette.gear), style: StrokeStyle(lineWidth: head.R * 0.11, lineCap: .round, lineJoin: .round))
        context.stroke(band, with: .color(OutfitPalette.gearLight), style: StrokeStyle(lineWidth: head.R * 0.035, lineCap: .round, lineJoin: .round))
    }

    private func drawHeadphoneCups(_ context: inout GraphicsContext, head: MochiH, front: Bool) {
        let radius = head.R
        for side: CGFloat in [-1, 1] {
            let cup = mProj(head, (side * 1.0, 0.12, 0))
            guard (cup.z >= 0) == front else { continue }
            let width = radius * 0.3
            let height = radius * 0.5
            let shell = Path(roundedRect: CGRect(x: cup.x - width / 2, y: cup.y - height / 2, width: width, height: height),
                             cornerRadius: width * 0.45)
            context.fill(shell, with: .linearGradient(Gradient(colors: [OutfitPalette.gearLight, OutfitPalette.gear]),
                                                      startPoint: CGPoint(x: cup.x, y: cup.y - height / 2),
                                                      endPoint: CGPoint(x: cup.x, y: cup.y + height / 2)))
            let cushionWidth = width * 0.5
            let cushion = Path(roundedRect: CGRect(x: cup.x - cushionWidth / 2, y: cup.y - height * 0.32, width: cushionWidth, height: height * 0.64),
                               cornerRadius: cushionWidth * 0.45)
            context.fill(cushion, with: .color(OutfitPalette.cushion))
        }
    }

    private func drawMusicNotes(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        guard isBusy, head.R > 12 else { return }
        let radius = head.R
        let cup = mProj(head, (1.0, 0.12, 0))
        for index in 0..<2 {
            let progress = (time * 0.7 + CGFloat(index) * 0.5).truncatingRemainder(dividingBy: 1)
            let noteHead = CGPoint(x: cup.x + radius * (0.2 + progress * 0.25), y: cup.y - radius * (0.3 + progress * 0.75))
            var note = context
            note.opacity = Double(sin(progress * .pi))
            note.translateBy(x: noteHead.x, y: noteHead.y)
            note.rotate(by: .radians(-0.4))
            note.fill(Path(ellipseIn: CGRect(x: -radius * 0.07, y: -radius * 0.05, width: radius * 0.14, height: radius * 0.1)),
                      with: .color(.white))
            note.rotate(by: .radians(0.4))
            var stem = Path()
            stem.move(to: CGPoint(x: radius * 0.06, y: -radius * 0.02))
            stem.addLine(to: CGPoint(x: radius * 0.06, y: -radius * 0.26))
            stem.addQuadCurve(to: CGPoint(x: radius * 0.16, y: -radius * 0.12), control: CGPoint(x: radius * 0.16, y: -radius * 0.24))
            note.stroke(stem, with: .color(.white), style: StrokeStyle(lineWidth: max(0.8, radius * 0.035), lineCap: .round))
        }
    }

    // MARK: - Flower crown

    private func drawFlowerCrown(_ context: inout GraphicsContext, head: MochiH, time: CGFloat, front: Bool) {
        let radius = head.R
        let vine = ring(head, y: 0.58, scale: 1.04)
        let side = vine.filter { ($0.z >= 0) == front }.sorted { $0.x < $1.x }
        context.stroke(polyline(side), with: .color(OutfitPalette.vine), style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        let flowerCount = 9
        for index in 0..<flowerCount {
            let longitude = CGFloat(index) / CGFloat(flowerCount) * 2 * .pi
            let spot = mProj(head, mSurf(0.58, longitude, 1.06))
            guard (spot.z >= 0) == front else { continue }
            let depth = 0.8 + 0.2 * max(0, spot.z)
            var flower = context
            flower.translateBy(x: spot.x, y: spot.y)
            flower.rotate(by: .radians(sin(time * 1.4 + CGFloat(index)) * 0.25))
            flower.scaleBy(x: depth, y: depth)
            let petalColor = OutfitPalette.petals[index % OutfitPalette.petals.count]
            for petal in 0..<5 {
                var petalContext = flower
                petalContext.rotate(by: .radians(Double(petal) * 2 * .pi / 5))
                petalContext.fill(Path(ellipseIn: CGRect(x: -radius * 0.04, y: -radius * 0.13, width: radius * 0.08, height: radius * 0.1)),
                                  with: .color(petalColor))
            }
            flower.fill(Path(ellipseIn: CGRect(x: -radius * 0.04, y: -radius * 0.04, width: radius * 0.08, height: radius * 0.08)),
                        with: .color(OutfitPalette.capYellow))
        }
    }

    // MARK: - Graduation cap

    private func drawGradCap(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        _ = fillCap(context, head: head, bandHeight: 0.5,
                    shading: .linearGradient(Gradient(colors: [OutfitPalette.gradTop, OutfitPalette.gradSide]),
                                             startPoint: CGPoint(x: 0, y: -head.ry), endPoint: CGPoint(x: 0, y: 0)))
        let boardHeight: CGFloat = 1.06
        let corners = [(0, 1.25), (1.25, 0), (0, -1.25), (-1.25, 0)].map { corner in
            mProj(head, (CGFloat(corner.0), boardHeight, CGFloat(corner.1)))
        }
        var board = polyline(corners)
        board.closeSubpath()
        var edge = context
        edge.translateBy(x: 0, y: radius * 0.07)
        edge.fill(board, with: .color(OutfitPalette.gradSide))
        context.fill(board, with: .linearGradient(Gradient(colors: [OutfitPalette.gradTop, OutfitPalette.gradSide]),
                                                  startPoint: CGPoint(x: 0, y: corners[2].y), endPoint: CGPoint(x: 0, y: corners[0].y)))
        let button = mProj(head, (0, boardHeight, 0))
        let buttonRadius = radius * 0.05
        context.fill(Path(ellipseIn: CGRect(x: button.x - buttonRadius, y: button.y - buttonRadius, width: buttonRadius * 2, height: buttonRadius * 2)),
                     with: .color(OutfitPalette.gold))
        let hangPoint = mProj(head, (1.2, boardHeight, 0))
        let swing = sin(time * 2) * 0.25 - head.physDx * 0.8
        let tasselEnd = CGPoint(x: hangPoint.x + sin(swing) * radius * 0.18, y: hangPoint.y + radius * 0.4)
        var cord = Path()
        cord.move(to: CGPoint(x: button.x, y: button.y))
        cord.addLine(to: CGPoint(x: hangPoint.x, y: hangPoint.y))
        cord.addLine(to: tasselEnd)
        context.stroke(cord, with: .color(OutfitPalette.gold), style: StrokeStyle(lineWidth: max(0.8, radius * 0.03), lineCap: .round, lineJoin: .round))
        let tassel = Path(roundedRect: CGRect(x: tasselEnd.x - radius * 0.05, y: tasselEnd.y - radius * 0.02, width: radius * 0.1, height: radius * 0.16),
                          cornerRadius: radius * 0.03)
        context.fill(tassel, with: .color(OutfitPalette.gold))
    }

    // MARK: - Halo

    private func drawHalo(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let height = 1.38 + sin(time * 2) * 0.05
        let loop = (0...48).map { step -> P3 in
            let angle = CGFloat(step) / 48 * 2 * .pi
            return mProj(head, (sin(angle) * 0.7, height, cos(angle) * 0.7))
        }
        let halo = polyline(loop)
        context.stroke(halo, with: .color(OutfitPalette.haloLight.opacity(0.22 + 0.1 * Double(sin(time * 3)))), lineWidth: radius * 0.22)
        context.stroke(halo, with: .linearGradient(Gradient(colors: [OutfitPalette.haloLight, OutfitPalette.haloDeep]),
                                                   startPoint: CGPoint(x: -head.rx, y: 0), endPoint: CGPoint(x: head.rx, y: 0)),
                       lineWidth: radius * 0.075)
    }

    // MARK: - Devil horns

    private func drawDevilHorns(_ context: inout GraphicsContext, head: MochiH) {
        let radius = head.R
        for side: CGFloat in [-1, 1] {
            let root = mProj(head, (side * 0.42, 0.84, 0.3))
            var horn = context
            horn.translateBy(x: root.x, y: root.y)
            horn.rotate(by: .radians(side * (0.15 + head.physDy * 0.3)))
            horn.scaleBy(x: side, y: 1)
            var shape = Path()
            shape.move(to: CGPoint(x: -radius * 0.1, y: radius * 0.05))
            shape.addQuadCurve(to: CGPoint(x: radius * 0.14, y: -radius * 0.36), control: CGPoint(x: -radius * 0.08, y: -radius * 0.22))
            shape.addQuadCurve(to: CGPoint(x: radius * 0.1, y: radius * 0.05), control: CGPoint(x: radius * 0.14, y: -radius * 0.1))
            shape.closeSubpath()
            horn.fill(shape, with: .linearGradient(Gradient(colors: [OutfitPalette.hornLight, OutfitPalette.hornDeep]),
                                                   startPoint: CGPoint(x: 0, y: -radius * 0.36), endPoint: CGPoint(x: 0, y: radius * 0.05)))
            var shine = Path()
            shine.move(to: CGPoint(x: -radius * 0.04, y: -radius * 0.02))
            shine.addQuadCurve(to: CGPoint(x: radius * 0.09, y: -radius * 0.27), control: CGPoint(x: -radius * 0.03, y: -radius * 0.18))
            horn.stroke(shine, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: max(0.6, radius * 0.025), lineCap: .round))
        }
    }

    // MARK: - Antlers and red nose

    private func drawAntlers(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        for side: CGFloat in [-1, 1] {
            let root = mProj(head, (side * 0.4, 0.86, 0))
            var antler = context
            antler.translateBy(x: root.x, y: root.y)
            antler.rotate(by: .radians(side * 0.1 - head.physDx * 0.3))
            antler.scaleBy(x: side, y: 1)
            var branches = Path()
            branches.move(to: CGPoint(x: 0, y: radius * 0.05))
            branches.addQuadCurve(to: CGPoint(x: radius * 0.3, y: -radius * 0.55), control: CGPoint(x: radius * 0.02, y: -radius * 0.35))
            branches.move(to: CGPoint(x: radius * 0.06, y: -radius * 0.22))
            branches.addLine(to: CGPoint(x: radius * 0.24, y: -radius * 0.28))
            branches.move(to: CGPoint(x: radius * 0.16, y: -radius * 0.42))
            branches.addLine(to: CGPoint(x: radius * 0.1, y: -radius * 0.62))
            antler.stroke(branches, with: .color(OutfitPalette.antler),
                          style: StrokeStyle(lineWidth: radius * 0.08, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawRedNose(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let spot = faceSpot(lift: -0.4, rx: head.rx, ry: head.ry)
        guard spot.isVisible else { return }
        let radius = head.R
        let glowRadius = radius * 0.24
        context.fill(Path(ellipseIn: CGRect(x: spot.point.x - glowRadius, y: spot.point.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                     with: .radialGradient(Gradient(colors: [OutfitPalette.hornLight.opacity(0.3 + 0.3 * Double(sin(time * 3))), .clear]),
                                           center: spot.point, startRadius: 0, endRadius: glowRadius))
        let noseRadius = radius * 0.085
        context.fill(Path(ellipseIn: CGRect(x: spot.point.x - noseRadius, y: spot.point.y - noseRadius, width: noseRadius * 2, height: noseRadius * 2)),
                     with: .radialGradient(Gradient(colors: [OutfitPalette.hornLight, OutfitPalette.hornDeep]),
                                           center: CGPoint(x: spot.point.x - noseRadius * 0.3, y: spot.point.y - noseRadius * 0.3),
                                           startRadius: 0, endRadius: noseRadius * 1.4))
        let shine = noseRadius * 0.35
        context.fill(Path(ellipseIn: CGRect(x: spot.point.x - noseRadius * 0.5, y: spot.point.y - noseRadius * 0.6, width: shine, height: shine)),
                     with: .color(.white.opacity(0.8)))
    }

    // MARK: - Heart glasses

    private func drawHeartGlasses(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let lensWidth = radius * MochiConst.eyeW * 1.2 * max(1.6, eyeSizeScale(radius: radius))
        let lensHeight = radius * MochiConst.eyeH * 1.05 * max(1.6, eyeSizeScale(radius: radius))
        let lenses = mEyeFrames(head).filter(\.visible)
        let frameWidth = max(0.8, radius * 0.045)
        for lens in lenses {
            var lensContext = context
            lensContext.translateBy(x: lens.x, y: lens.y)
            lensContext.scaleBy(x: lens.fx, y: lens.fy)
            let heart = heartPath(width: lensWidth, height: lensHeight)
            lensContext.fill(heart, with: .color(OutfitPalette.lens.opacity(0.55)))
            var shineContext = lensContext
            shineContext.clip(to: heart)
            let sweep = (time * 0.5).truncatingRemainder(dividingBy: 2) - 0.5
            var shine = Path()
            shine.move(to: CGPoint(x: (sweep - 0.4) * lensWidth, y: lensHeight * 0.5))
            shine.addLine(to: CGPoint(x: (sweep + 0.1) * lensWidth, y: -lensHeight * 0.5))
            shineContext.stroke(shine, with: .color(.white.opacity(0.55)), lineWidth: lensWidth * 0.14)
            lensContext.stroke(heart, with: .color(OutfitPalette.lensFrame), lineWidth: frameWidth)
            var arm = Path()
            arm.move(to: CGPoint(x: lens.sd * lensWidth * 0.5, y: -lensHeight * 0.1))
            arm.addLine(to: CGPoint(x: lens.sd * lensWidth * 0.95, y: -lensHeight * 0.18))
            lensContext.stroke(arm, with: .color(OutfitPalette.lensFrame), style: StrokeStyle(lineWidth: frameWidth, lineCap: .round))
        }
        if lenses.count == 2 {
            var bridge = Path()
            bridge.move(to: CGPoint(x: lenses[0].x + lensWidth * 0.45 * lenses[0].fx, y: lenses[0].y - lensHeight * 0.12))
            bridge.addQuadCurve(to: CGPoint(x: lenses[1].x - lensWidth * 0.45 * lenses[1].fx, y: lenses[1].y - lensHeight * 0.12),
                                control: CGPoint(x: (lenses[0].x + lenses[1].x) / 2, y: lenses[0].y - lensHeight * 0.32))
            context.stroke(bridge, with: .color(OutfitPalette.lensFrame), style: StrokeStyle(lineWidth: frameWidth, lineCap: .round))
        }
    }

    private func heartPath(width: CGFloat, height: CGFloat) -> Path {
        var heart = Path()
        heart.move(to: CGPoint(x: 0, y: height * 0.45))
        heart.addCurve(to: CGPoint(x: -width * 0.5, y: -height * 0.1),
                       control1: CGPoint(x: -width * 0.18, y: height * 0.3), control2: CGPoint(x: -width * 0.5, y: height * 0.15))
        heart.addCurve(to: CGPoint(x: 0, y: -height * 0.22),
                       control1: CGPoint(x: -width * 0.5, y: -height * 0.5), control2: CGPoint(x: -width * 0.05, y: -height * 0.5))
        heart.addCurve(to: CGPoint(x: width * 0.5, y: -height * 0.1),
                       control1: CGPoint(x: width * 0.05, y: -height * 0.5), control2: CGPoint(x: width * 0.5, y: -height * 0.5))
        heart.addCurve(to: CGPoint(x: 0, y: height * 0.45),
                       control1: CGPoint(x: width * 0.5, y: height * 0.15), control2: CGPoint(x: width * 0.18, y: height * 0.3))
        heart.closeSubpath()
        return heart
    }

    // MARK: - Chef hat

    private func drawChefHat(_ context: inout GraphicsContext, head: MochiH) {
        let radius = head.R
        let bandBottom = frontArc(ring(head, y: 0.5, scale: 1.06))
        guard bandBottom.count > 2 else { return }
        let bandHeight = radius * 0.3
        _ = fillCap(context, head: head, bandHeight: 0.5,
                    shading: .linearGradient(Gradient(colors: [.white, OutfitPalette.chefShade]),
                                             startPoint: CGPoint(x: 0, y: -head.ry), endPoint: CGPoint(x: 0, y: bandBottom[0].y)))
        let bandTop = bandBottom.map { CGPoint(x: $0.x, y: $0.y - bandHeight) }
        var bandLines = context
        bandLines.clip(to: mochiPath(rx: head.rx * 1.05, ry: head.ry * 1.05, morph: 0, R: head.R))
        var bandEdge = Path()
        bandEdge.addLines(bandTop)
        bandLines.stroke(bandEdge, with: .color(OutfitPalette.chefLine), lineWidth: max(0.6, radius * 0.025))
        for index in stride(from: bandBottom.count / 6, to: bandBottom.count, by: max(1, bandBottom.count / 6)) {
            var pleat = Path()
            pleat.move(to: CGPoint(x: bandBottom[index].x, y: bandBottom[index].y - bandHeight * 0.15))
            pleat.addLine(to: CGPoint(x: bandTop[index].x, y: bandTop[index].y + bandHeight * 0.15))
            bandLines.stroke(pleat, with: .color(OutfitPalette.chefLine), lineWidth: max(0.6, radius * 0.02))
        }
        let crown = mProj(head, (0, 0.95, 0))
        let puffBase = CGPoint(x: crown.x + head.physDx * radius * 0.08, y: crown.y - bandHeight * 0.55)
        var puffs = context
        puffs.translateBy(x: puffBase.x, y: puffBase.y)
        puffs.scaleBy(x: 1, y: 1 - head.physDy * 0.2)
        var cloud = Path()
        for (offsetX, offsetY, puffRadius) in [(-0.45, 0.05, 0.3), (-0.17, -0.12, 0.34), (0.17, -0.12, 0.34), (0.45, 0.05, 0.3), (0, -0.36, 0.34)] {
            let puffSize = radius * CGFloat(puffRadius)
            cloud.addEllipse(in: CGRect(x: radius * CGFloat(offsetX) - puffSize, y: radius * CGFloat(offsetY) - puffSize,
                                        width: puffSize * 2, height: puffSize * 2))
        }
        puffs.fill(cloud, with: .linearGradient(Gradient(colors: [.white, OutfitPalette.chefShade]),
                                                startPoint: CGPoint(x: 0, y: -radius * 0.7), endPoint: CGPoint(x: 0, y: radius * 0.35)))
        puffs.stroke(cloud, with: .color(OutfitPalette.chefLine.opacity(0.7)), lineWidth: max(0.6, radius * 0.02))
    }

    // MARK: - Ninja headband

    private func drawHeadband(_ context: inout GraphicsContext, head: MochiH) {
        let radius = head.R
        let band = polyline(frontArc(ring(head, y: 0.5, scale: 1.04)))
        context.stroke(band, with: .color(OutfitPalette.headbandDark), style: StrokeStyle(lineWidth: radius * 0.17, lineCap: .round))
        context.stroke(band, with: .color(OutfitPalette.headband), style: StrokeStyle(lineWidth: radius * 0.12, lineCap: .round))
    }

    private func drawHeadbandTails(_ context: inout GraphicsContext, head: MochiH, time: CGFloat) {
        let radius = head.R
        let knot = mProj(head, mSurf(0.5, .pi * 0.62, 1.04))
        for (index, droop) in [CGFloat(0.12), 0.36].enumerated() {
            let flutter = sin(time * 6 + CGFloat(index) * 1.7) * radius * 0.06
            let end = CGPoint(x: knot.x + radius * (0.62 - CGFloat(index) * 0.1) - head.physDx * radius * 0.3,
                              y: knot.y + radius * droop + flutter)
            var tail = Path()
            tail.move(to: CGPoint(x: knot.x, y: knot.y))
            tail.addQuadCurve(to: end, control: CGPoint(x: knot.x + radius * 0.3, y: knot.y - radius * 0.04 - flutter))
            context.stroke(tail, with: .color(OutfitPalette.headband), style: StrokeStyle(lineWidth: radius * 0.1, lineCap: .round))
        }
    }
}
