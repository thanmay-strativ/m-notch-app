import Foundation

public struct DiffLine: Equatable, Sendable {
    public enum Kind: Sendable { case context, added, removed }
    public let kind: Kind
    public let text: String
}

public struct FileDiff: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let filePath: String
    public let added: Int
    public let removed: Int
    public let lines: [DiffLine]
    public let firstChangedLine: Int

    public var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }
}

/// Builds a FileDiff from an Edit, MultiEdit or Write PostToolUse payload.
public enum LineDiff {
    public static let maxLines = 400

    public static func make(toolName: String?, toolInput: JSONValue?, toolResponse: JSONValue?,
                            readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }) -> FileDiff? {
        guard let toolName, ["Edit", "MultiEdit", "Write"].contains(toolName),
              let filePath = toolResponse?["filePath"]?.stringValue ?? toolInput?["file_path"]?.stringValue else {
            return nil
        }
        if let hunks = toolResponse?["structuredPatch"]?.arrayValue, !hunks.isEmpty {
            return fromPatch(filePath: filePath, hunks: hunks)
        }
        if toolName == "Write" {
            let content = toolResponse?["content"]?.stringValue ?? toolInput?["content"]?.stringValue ?? ""
            let original = toolResponse?["originalFile"]?.stringValue
            return fromStrings(filePath: filePath, old: original ?? "", new: content, firstLine: 1)
        }
        let edits: [(String, String)]
        if toolName == "MultiEdit" {
            edits = (toolInput?["edits"]?.arrayValue ?? []).map {
                ($0["old_string"]?.stringValue ?? "", $0["new_string"]?.stringValue ?? "")
            }
        } else {
            edits = [(toolInput?["old_string"]?.stringValue ?? "", toolInput?["new_string"]?.stringValue ?? "")]
        }
        let oldText = edits.map(\.0).joined(separator: "\n")
        let newText = edits.map(\.1).joined(separator: "\n")
        return fromStrings(filePath: filePath, old: oldText, new: newText,
                           firstLine: lineNumber(of: edits.first?.1 ?? "", in: readFile(filePath)))
    }

    static func fromPatch(filePath: String, hunks: [JSONValue]) -> FileDiff {
        var lines: [DiffLine] = []
        var firstChangedLine: Int?
        for hunk in hunks {
            var newLineNumber = hunk["newStart"]?.intValue ?? 1
            for raw in hunk["lines"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                let text = String(raw.dropFirst())
                switch raw.first {
                case "+":
                    firstChangedLine = firstChangedLine ?? newLineNumber
                    lines.append(DiffLine(kind: .added, text: text))
                    newLineNumber += 1
                case "-":
                    firstChangedLine = firstChangedLine ?? newLineNumber
                    lines.append(DiffLine(kind: .removed, text: text))
                default:
                    lines.append(DiffLine(kind: .context, text: text))
                    newLineNumber += 1
                }
            }
        }
        return FileDiff(filePath: filePath,
                        added: lines.filter { $0.kind == .added }.count,
                        removed: lines.filter { $0.kind == .removed }.count,
                        lines: Array(lines.prefix(maxLines)),
                        firstChangedLine: firstChangedLine ?? 1)
    }

    static func fromStrings(filePath: String, old: String, new: String, firstLine: Int) -> FileDiff {
        let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")
        var removed: [DiffLine] = []
        var added: [DiffLine] = []
        for change in newLines.difference(from: oldLines) {
            switch change {
            case .remove(_, let text, _): removed.append(DiffLine(kind: .removed, text: text))
            case .insert(_, let text, _): added.append(DiffLine(kind: .added, text: text))
            }
        }
        return FileDiff(filePath: filePath, added: added.count, removed: removed.count,
                        lines: Array((removed + added).prefix(maxLines)), firstChangedLine: firstLine)
    }

    static func lineNumber(of snippet: String, in content: String?) -> Int {
        guard let content, let firstLine = snippet.components(separatedBy: "\n").first,
              !firstLine.trimmingCharacters(in: .whitespaces).isEmpty,
              let range = content.range(of: firstLine) else { return 1 }
        return content[content.startIndex..<range.lowerBound].filter { $0 == "\n" }.count + 1
    }
}
