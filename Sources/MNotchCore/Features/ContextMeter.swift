import Foundation

public struct ContextReading: Equatable, Sendable {
    public let usedTokens: Int
    public let window: Int
    public let modelId: String?

    public var percent: Int { min(100, Int((Double(usedTokens) / Double(window) * 100).rounded())) }
}

/// Reads how full a Claude session's context window is, from the tail of its transcript.
/// Used when the status line relay is not installed; the relay's numbers win when present.
/// ponytail: assumes a 200k window and switches to 1M past 200k; the transcript is not a public API, so it returns nil on any surprise.
public enum ContextMeter {
    static let tailBytes = 65_536
    static let standardWindow = 200_000
    static let largeWindow = 1_000_000

    public static func read(transcriptPath: String) -> ContextReading? {
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return reading(fromTail: String(decoding: data, as: UTF8.self))
    }

    static func reading(fromTail text: String) -> ContextReading? {
        for line in text.split(separator: "\n").reversed() {
            guard let record = JSONValue.decode(Data(line.utf8)),
                  let usage = record["message"]?["usage"] else { continue }
            let used = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                .compactMap { usage[$0]?.intValue }
                .reduce(0, +)
            guard used > 0 else { continue }
            return ContextReading(usedTokens: used, window: used > standardWindow ? largeWindow : standardWindow,
                                  modelId: record["message"]?["model"]?.stringValue)
        }
        return nil
    }
}

/// Session facts read once from the transcript file when a session first shows up.
public enum TranscriptStats {
    static let toolUseMarker = Data(#""type":"tool_use""#.utf8)

    public static func toolCount(transcriptPath: String) -> Int {
        guard let data = FileManager.default.contents(atPath: transcriptPath) else { return 0 }
        return count(of: toolUseMarker, in: data)
    }

    public static func createdAt(transcriptPath: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: transcriptPath))?[.creationDate] as? Date
    }

    static func count(of marker: Data, in data: Data) -> Int {
        var total = 0
        var searchRange = data.startIndex..<data.endIndex
        while let found = data.range(of: marker, in: searchRange) {
            total += 1
            searchRange = found.upperBound..<data.endIndex
        }
        return total
    }
}
