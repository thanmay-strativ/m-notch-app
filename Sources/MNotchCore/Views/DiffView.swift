import SwiftUI

/// One file change: red and green lines, plus a button that opens the file at the changed line.
struct DiffView: View {
    let diff: FileDiff
    let session: Session
    let actions: IslandActions

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(verbatim: diff.fileName).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.text)
                    Text(verbatim: "+\(diff.added)").font(.system(size: 11, design: .monospaced)).foregroundColor(Palette.done)
                    Text(verbatim: "-\(diff.removed)").font(.system(size: 11, design: .monospaced)).foregroundColor(Palette.danger)
                    Spacer(minLength: 4)
                    PillButton(title: "Open at line \(diff.firstChangedLine)") { actions.open(diff, in: session) }
                    Button { actions.closeDiff() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Palette.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineView(line: line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
            }
            .padding(14)
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        let (prefix, color, background): (String, Color, Color) = {
            switch line.kind {
            case .added: return ("+", Palette.done, Palette.done.opacity(0.10))
            case .removed: return ("-", Palette.danger, Palette.danger.opacity(0.10))
            case .context: return (" ", Palette.secondary, .clear)
            }
        }()
        Text(verbatim: prefix + " " + line.text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
    }
}
