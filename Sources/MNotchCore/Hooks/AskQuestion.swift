// Ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import Foundation

public struct AskQuestionOption: Equatable, Sendable {
    public var label: String
    public var description: String
}

public struct AskQuestionItem: Equatable, Sendable {
    public var question: String
    public var header: String
    public var options: [AskQuestionOption]
    public var multiSelect: Bool

    public var hasDescriptions: Bool { options.contains { !$0.description.isEmpty } }
}

/// The questions of one AskUserQuestion call: 1 to 4 questions with 2 to 4 options each.
public struct AskQuestion: Equatable, Sendable {
    public var questions: [AskQuestionItem]

    public static func parse(toolInput: JSONValue?) -> AskQuestion? {
        guard let rawQuestions = toolInput?["questions"]?.arrayValue,
              !rawQuestions.isEmpty, rawQuestions.count <= 4 else { return nil }
        var items: [AskQuestionItem] = []
        for rawQuestion in rawQuestions {
            guard let question = rawQuestion["question"]?.stringValue, !question.isEmpty,
                  let rawOptions = rawQuestion["options"]?.arrayValue,
                  (2...4).contains(rawOptions.count) else { return nil }
            var options: [AskQuestionOption] = []
            for rawOption in rawOptions {
                guard let label = rawOption["label"]?.stringValue, !label.isEmpty else { return nil }
                options.append(AskQuestionOption(label: label, description: rawOption["description"]?.stringValue ?? ""))
            }
            items.append(AskQuestionItem(question: question,
                                         header: String((rawQuestion["header"]?.stringValue ?? "").prefix(12)),
                                         options: options,
                                         multiSelect: rawQuestion["multiSelect"]?.boolValue ?? false))
        }
        return AskQuestion(questions: items)
    }

    public static func buildAnswers(questions: [AskQuestionItem], selections: [[String]]) -> [String: JSONValue] {
        var answers: [String: JSONValue] = [:]
        for (index, item) in questions.enumerated() where index < selections.count && !selections[index].isEmpty {
            answers[item.question] = item.multiSelect
                ? .array(selections[index].map { .string($0) })
                : .string(selections[index][0])
        }
        return answers
    }

    public var estimatedHeight: CGFloat {
        func lineCount(_ text: String, characterWidth: CGFloat) -> CGFloat {
            max(1, (CGFloat(text.count) * characterWidth / 480).rounded(.up))
        }
        let tallest = questions.map { item -> CGFloat in
            var height: CGFloat = 52 + lineCount(item.question, characterWidth: 7) * 17 + 50
            if item.hasDescriptions {
                for option in item.options {
                    height += 30 + (option.description.isEmpty ? 0 : lineCount(option.description, characterWidth: 6.4) * 14)
                }
            } else {
                height += item.options.count >= 3 ? 70 : 36
            }
            if item.multiSelect { height += 34 }
            return height
        }.max() ?? 160
        return min(max(tallest, 160), 560)
    }
}
