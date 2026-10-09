import SwiftUI

/// Claude's AskUserQuestion, one question at a time. Single-select answers on click; multi-select needs Next.
struct QuestionCardView: View {
    let request: PendingRequest
    let question: AskQuestion
    let session: Session?
    let counter: String?
    let model: IslandModel
    let actions: IslandActions
    @State private var questionIndex = 0
    @State private var selections: [[String]] = []

    private var item: AskQuestionItem { question.questions[min(questionIndex, question.questions.count - 1)] }
    private var currentSelection: [String] { questionIndex < selections.count ? selections[questionIndex] : [] }

    var body: some View {
        ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 8) {
                SessionWho(session: session, label: "asks", counter: progressText, onBack: actions.hideRequests)
                HStack(spacing: 6) {
                    if !item.header.isEmpty {
                        Text(verbatim: item.header)
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(Palette.needsYou)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.needsYou.opacity(0.15)).clipShape(Capsule())
                    }
                    Text(verbatim: item.question)
                        .font(.system(size: 12.5, weight: .medium)).foregroundColor(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                options
                HStack(spacing: 8) {
                    if item.multiSelect {
                        PillButton(title: isLastQuestion ? "Send" : "Next", style: .primary) { advance() }
                            .disabled(currentSelection.isEmpty)
                            .opacity(currentSelection.isEmpty ? 0.5 : 1)
                    }
                    Spacer(minLength: 4)
                    TerminalLink { actions.replyInTerminal(request) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear { selections = Array(repeating: [], count: question.questions.count) }
        .onChange(of: model.optionPickCount) { _, _ in pick(index: model.lastOptionPick) }
    }

    @ViewBuilder private var options: some View {
        if item.hasDescriptions {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                    optionButton(index: index, option: option, showsDescription: true)
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                    optionButton(index: index, option: option, showsDescription: false)
                }
            }
        }
    }

    private func optionButton(index: Int, option: AskQuestionOption, showsDescription: Bool) -> some View {
        let isSelected = currentSelection.contains(option.label)
        return Button { pick(index: index) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: "⌥⌘\(index + 1)").font(.system(size: 9.5)).foregroundColor(Palette.tertiary)
                    Text(verbatim: option.label).font(.system(size: 12, weight: .medium))
                }
                if showsDescription && !option.description.isEmpty {
                    Text(verbatim: option.description).font(.system(size: 11)).foregroundColor(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: showsDescription ? .infinity : nil, alignment: .leading)
            .background(isSelected ? Palette.needsYou.opacity(0.28) : Color.white.opacity(0.08))
            .foregroundColor(Palette.text)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var isLastQuestion: Bool { questionIndex >= question.questions.count - 1 }

    private var progressText: String? {
        let parts = [question.questions.count > 1 ? "\(questionIndex + 1)/\(question.questions.count)" : nil, counter]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private func pick(index: Int) {
        guard item.options.indices.contains(index), questionIndex < selections.count else { return }
        let label = item.options[index].label
        if item.multiSelect {
            if let existing = selections[questionIndex].firstIndex(of: label) {
                selections[questionIndex].remove(at: existing)
            } else {
                selections[questionIndex].append(label)
            }
        } else {
            selections[questionIndex] = [label]
            advance()
        }
    }

    private func advance() {
        guard !currentSelection.isEmpty else { return }
        if isLastQuestion {
            actions.answer(request, selections: selections)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { questionIndex += 1 }
        }
    }
}
