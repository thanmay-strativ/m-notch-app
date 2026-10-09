import SwiftUI

/// Permission card: Deny / Allow / Always. Risky commands turn red and need Touch ID.
struct ApprovalCardView: View {
    let request: PendingRequest
    let session: Session?
    let counter: String?
    let actions: IslandActions

    private var label: String {
        request.toolName == "Bash" ? "wants to run" : "wants to use \(request.toolName)"
    }

    var body: some View {
        ZStack {
            CardBackground(wash: request.risk == nil ? .amber : .red)
            VStack(alignment: .leading, spacing: 7) {
                SessionWho(session: session, label: label, counter: counter, onBack: actions.hideRequests)
                CodeBlock(text: request.summary)
                if let risk = request.risk {
                    Label {
                        Text(verbatim: "risky: \(risk) · Touch ID to allow")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Palette.danger)
                }
                HStack(spacing: 8) {
                    PillButton(title: "Deny", shortcut: "⌥⌘N") {
                        actions.decide(request, .deny(message: HookReply.deniedMessage))
                    }
                    PillButton(title: "Allow", shortcut: "⌥⌘Y", style: request.risk == nil ? .primary : .danger) {
                        actions.decide(request, .allow)
                    }
                    if request.canAlwaysAllow {
                        PillButton(title: "Always", shortcut: "⌥⌘A") { actions.decide(request, .always) }
                    }
                    Spacer(minLength: 4)
                    TerminalLink { actions.replyInTerminal(request) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

/// Plan approval: the plan as formatted text, then Approve plan / Keep planning.
struct PlanCardView: View {
    let request: PendingRequest
    let plan: String
    let session: Session?
    let counter: String?
    let actions: IslandActions

    var body: some View {
        ZStack {
            CardBackground(wash: .green)
            VStack(alignment: .leading, spacing: 8) {
                SessionWho(session: session, label: "has a plan", counter: counter, onBack: actions.hideRequests)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(plan.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            PlanLine(line: line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    PillButton(title: "Keep planning", shortcut: "⌥⌘N") {
                        actions.decide(request, .deny(message: HookReply.keepPlanningMessage))
                    }
                    PillButton(title: "Approve plan", shortcut: "⌥⌘Y", style: .primary) { actions.decide(request, .allow) }
                    Spacer(minLength: 4)
                    TerminalLink { actions.replyInTerminal(request) }
                }
            }
            .padding(14)
        }
    }
}

struct PlanLine: View {
    let line: String

    var body: some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            Text(inline(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                .font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.text).padding(.top, 4)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            Text(inline("•  " + trimmed.dropFirst(2))).font(.system(size: 12)).foregroundColor(Palette.text.opacity(0.9))
        } else {
            Text(inline(line)).font(.system(size: 12)).foregroundColor(Palette.text.opacity(0.9))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct TerminalLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "Reply in terminal").font(.system(size: 11)).foregroundColor(Palette.secondary).underline()
        }
        .buttonStyle(.plain)
    }
}
