// Styles ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import SwiftUI

enum Palette {
    static let text = Color(hex: "#F5F6F8")
    static let secondary = Color(hex: "#8E939C")
    static let tertiary = Color(hex: "#6B7079")
    static let card = Color(hex: "#141518")
    static let working = Color(hex: "#3B9EFF")
    static let thinking = Color(hex: "#A78BFA")
    static let needsYou = Color(hex: "#F5A524")
    static let done = Color(hex: "#34D399")
    static let danger = Color(hex: "#F4505E")

    static func color(for state: SessionState) -> Color {
        switch state {
        case .thinking: return thinking
        case .working: return working
        case .needsYou: return needsYou
        case .done: return done
        }
    }
}

struct CardBackground: View {
    enum Wash { case amber, red, green }
    let wash: Wash?

    private var washColor: Color {
        switch wash {
        case .amber: return Palette.needsYou.opacity(0.42)
        case .red: return Palette.danger.opacity(0.55)
        case .green: return Palette.done.opacity(0.5)
        case nil: return .clear
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Palette.card)
            .overlay(
                RadialGradient(gradient: Gradient(stops: [.init(color: washColor, location: 0), .init(color: .clear, location: 0.7)]),
                               center: UnitPoint(x: 0.5, y: 1.3), startRadius: 0, endRadius: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            )
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.035), lineWidth: 1))
    }
}

struct PillButton: View {
    enum Style { case primary, secondary, danger }
    let title: String
    var shortcut: String?
    var style: Style = .secondary
    let action: () -> Void

    private var background: Color {
        switch style {
        case .primary: return Palette.text
        case .secondary: return Color.white.opacity(0.09)
        case .danger: return Palette.danger
        }
    }

    private var foreground: Color { style == .primary ? Color(hex: "#0B0C0E") : Color(hex: "#F1F2F4") }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(verbatim: title).font(.system(size: 12.5, weight: .medium))
                if let shortcut {
                    Text(verbatim: shortcut)
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(foreground.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(background)
            .foregroundColor(foreground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The full command, never truncated: it grows with wrapped lines up to `IslandLayout.maxCodeLines`, then scrolls.
struct CodeBlock: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) {
            Text(verbatim: text)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: IslandLayout.codeBlockHeight(lines: IslandLayout.wrappedLineCount(text)))
        .background(Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundColor(Color(hex: "#E8E9EC"))
        .textSelection(.enabled)
    }
}

struct SessionWho: View {
    let session: Session?
    let label: String
    var counter: String?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            if let onBack {
                BackButton(action: onBack)
            }
            if let session {
                Circle().fill(Palette.color(for: session.state)).frame(width: 8, height: 8)
                Text(verbatim: session.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.text)
                Text(verbatim: "\(session.agent.displayName) · \(session.host.displayName)")
                    .font(.system(size: 11)).foregroundColor(Palette.tertiary)
            }
            Text(verbatim: label).font(.system(size: 12)).foregroundColor(Palette.secondary)
            Spacer(minLength: 4)
            if let counter {
                Text(verbatim: counter).font(.system(size: 11)).foregroundColor(Palette.tertiary)
            }
        }
        .lineLimit(1)
    }
}

/// Leaves a request card for the session list; the request keeps waiting.
struct BackButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? Palette.text : Palette.secondary)
                .frame(width: 22, height: 20)
                .background(Color.white.opacity(isHovered ? 0.12 : 0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Back to sessions. The request keeps waiting.")
    }
}

enum RelativeAge {
    static func text(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
