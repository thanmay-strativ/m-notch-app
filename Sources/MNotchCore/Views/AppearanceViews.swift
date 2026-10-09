import SwiftUI

/// Top of the Appearance page: the chosen character, small and live, with its name and outfit.
struct CharacterHero: View {
    let design: CharacterDesign
    let color: Preferences.CharacterColor
    let outfit: Outfit

    private var outfitLine: String {
        let worn = Outfit.resolved(selection: outfit, date: Date(), calendar: .current)
        if worn == .none { return outfit == .auto ? "no outfit this season" : "no outfit" }
        return outfit == .auto ? "wearing \(worn.displayName.lowercased()) (seasonal)" : "wearing \(worn.displayName.lowercased())"
    }

    var body: some View {
        HStack(spacing: 14) {
            CharacterPreview(design: design, color: color, outfit: outfit, width: 50, headroom: 0.4, interactive: true)
                .frame(width: 76, height: 76)
                .background(CharacterTileBackground(glow: Color(hex: color.gradientHex.top), cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: design.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(verbatim: design.tagline.prefix(1).uppercased() + design.tagline.dropFirst() + ", " + outfitLine)
                    .foregroundStyle(.secondary)
                Text(verbatim: "Hover it and it looks at you. Click it for a trick.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// Small tiles that wrap to the width of the settings page.
struct ChoiceGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68, maximum: 80), spacing: 10)], alignment: .leading, spacing: 12) {
            content()
        }
        .padding(.vertical, 4)
    }
}

/// One choice in an Appearance grid: a small live preview of the character as it would look, and a name.
struct ChoiceTile: View {
    let title: String
    let help: String
    let design: CharacterDesign
    let color: Preferences.CharacterColor
    let outfit: Outfit
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                CharacterPreview(design: design, color: color, outfit: outfit, width: 38, headroom: 0.4, framesPerSecond: 24)
                    .frame(width: 60, height: 58)
                    .background(CharacterTileBackground(glow: nil, cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isOn ? Color.accentColor : Color.primary.opacity(isHovered ? 0.3 : 0.08), lineWidth: isOn ? 2 : 1))
                    .scaleEffect(isHovered && !isOn ? 1.04 : 1)
                Text(verbatim: title)
                    .font(.system(size: 10.5, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 72, height: 28, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .help(help)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
    }
}

/// Dark rounded backdrop for live characters, the same in light and dark mode so they look like they do in the notch.
struct CharacterTileBackground: View {
    let glow: Color?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#2A2C33"), Color(hex: "#121317")], startPoint: .top, endPoint: .bottom))
            if let glow {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 34))
                    .offset(y: 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A color choice for the settings window: a ring in the accent color marks the chosen one.
struct SettingsSwatch: View {
    let color: Preferences.CharacterColor
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: color.gradientHex.top), Color(hex: color.gradientHex.bottom)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                .padding(3)
                .overlay(Circle().strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(color.title)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// A small colored capsule with a dot: "OK", "not installed", "listening on 127.0.0.1:47823".
struct StatusPill: View {
    enum Tone { case good, warning, bad, neutral }

    let text: String
    let tone: Tone

    private var color: Color {
        switch tone {
        case .good: return Palette.done
        case .warning: return Palette.needsYou
        case .bad: return .red
        case .neutral: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(verbatim: text).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .help(text)
    }
}
