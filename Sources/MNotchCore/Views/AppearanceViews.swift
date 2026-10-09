import SwiftUI

/// Top of the Appearance page: the chosen character, large and live, with how to play with it.
struct CharacterHero: View {
    let design: CharacterDesign
    let color: Preferences.CharacterColor
    let outfit: Outfit

    private var outfitLine: String {
        let worn = Outfit.resolved(selection: outfit, date: Date(), calendar: .current)
        if worn == .none { return outfit == .auto ? "No outfit this season" : "No outfit" }
        return outfit == .auto ? "Wearing \(worn.displayName.lowercased()) (seasonal)" : "Wearing \(worn.displayName.lowercased())"
    }

    var body: some View {
        HStack(spacing: 20) {
            CharacterPreview(design: design, color: color, outfit: outfit, width: 120, interactive: true)
                .frame(width: 180, height: 190)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [AppearanceStyle.tileTop, AppearanceStyle.tileBottom], startPoint: .top, endPoint: .bottom))
                        Circle()
                            .fill(RadialGradient(colors: [Color(hex: color.gradientHex.top).opacity(0.35), .clear],
                                                 center: .center, startRadius: 0, endRadius: 80))
                            .offset(y: 20)
                    }
                )
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: design.title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(verbatim: design.tagline.prefix(1).uppercased() + design.tagline.dropFirst()).foregroundColor(.secondary)
                Text(verbatim: outfitLine).foregroundColor(.secondary)
                Divider().frame(width: 180).padding(.vertical, 4)
                Group {
                    Label("Hover it: it looks at you", systemImage: "eye")
                    Label("Click it: a random reaction", systemImage: "hand.tap")
                    Label("Three quick clicks: dizzy", systemImage: "tornado")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Six `PreviewCard`s per row: the six characters fit one row, the twelve outfits two.
struct PreviewGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(80), spacing: 10), count: 6), alignment: .leading, spacing: 12) {
            content()
        }
    }
}

/// One choice in an Appearance grid: a small live preview of the character as it would look, and a name.
struct PreviewCard: View {
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
            VStack(spacing: 6) {
                CharacterPreview(design: design, color: color, outfit: outfit, width: 54, headroom: 0.3, framesPerSecond: 30)
                    .frame(width: 76, height: 80)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [AppearanceStyle.tileTop, AppearanceStyle.tileBottom], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isOn ? Color.accentColor : Color.white.opacity(isHovered ? 0.25 : 0.08), lineWidth: isOn ? 2 : 1))
                    .overlay(alignment: .topTrailing) {
                        if isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(5)
                        }
                    }
                    .scaleEffect(isHovered && !isOn ? 1.03 : 1)
                Text(verbatim: title)
                    .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                    .foregroundColor(isOn ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 80, height: 28, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .help(help)
    }
}

enum AppearanceStyle {
    static let tileTop = Color(hex: "#26282E")
    static let tileBottom = Color(hex: "#111215")
}
