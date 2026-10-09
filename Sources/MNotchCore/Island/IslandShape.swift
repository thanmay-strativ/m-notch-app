// Ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import SwiftUI

/// The black island: square top hidden under the screen edge, rounded bottom corners.
/// Width, height and corner radius animate together, which is what makes the morph smooth.
struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(width, height), cornerRadius) }
        set {
            width = newValue.first.first
            height = newValue.first.second
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(max(0, cornerRadius), min(width / 2, height / 2))
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: height - radius))
        path.addArc(center: CGPoint(x: width - radius, y: height - radius), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: radius, y: height))
        path.addArc(center: CGPoint(x: radius, y: height - radius), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}
