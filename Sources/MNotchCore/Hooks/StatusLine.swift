import Foundation

public struct PlanWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date
}

/// Claude plan limits as reported to the status line (Pro and Max plans only).
public struct PlanUsage: Equatable, Sendable {
    public var fiveHour: PlanWindow?
    public var sevenDay: PlanWindow?
}

/// The JSON Claude Code hands to its status line command, reduced to what the island shows.
public struct StatusLineInfo: Sendable, Equatable {
    public let sessionId: String?
    public let transcriptPath: String?
    public let modelName: String?
    public let contextUsed: Int?
    public let contextWindow: Int?
    public let plan: PlanUsage?

    public init(body: JSONValue) {
        sessionId = body["session_id"]?.stringValue
        transcriptPath = body["transcript_path"]?.stringValue
        modelName = body["model"]?["display_name"]?.stringValue
        let context = body["context_window"]
        if let input = context?["total_input_tokens"]?.intValue, let output = context?["total_output_tokens"]?.intValue {
            contextUsed = input + output
        } else {
            contextUsed = nil
        }
        contextWindow = context?["context_window_size"]?.intValue
        let fiveHour = Self.window(body["rate_limits"]?["five_hour"])
        let sevenDay = Self.window(body["rate_limits"]?["seven_day"])
        plan = fiveHour == nil && sevenDay == nil ? nil : PlanUsage(fiveHour: fiveHour, sevenDay: sevenDay)
    }

    static func window(_ raw: JSONValue?) -> PlanWindow? {
        guard case .number(let percent) = raw?["used_percentage"], (0...200).contains(percent),
              case .number(let epoch) = raw?["resets_at"], epoch > 0,
              epoch < Date().timeIntervalSince1970 + 400 * 86_400 else { return nil }
        return PlanWindow(usedPercent: min(100, percent), resetsAt: Date(timeIntervalSince1970: epoch))
    }
}

public enum StatsFormat {
    public static func tokens(_ count: Int) -> String {
        count >= 1000 ? "\(Int((Double(count) / 1000).rounded()))k" : "\(count)"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        if minutes >= 24 * 60 { return "\(minutes / 1440)d \(minutes % 1440 / 60)h" }
        if minutes >= 60 { return String(format: "%dh %02dm", minutes / 60, minutes % 60) }
        return "\(minutes)m"
    }

    public static func modelName(fromId modelId: String) -> String {
        let parts: [String] = modelId.replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-").map(String.init)
            .filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        guard let family = parts.first else { return modelId }
        let version: String = parts.dropFirst().filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        let familyName = String(family.prefix(1)).uppercased() + String(family.dropFirst())
        return version.isEmpty ? familyName : "\(familyName) \(version)"
    }
}

/// Puts m_notch in front of Claude's status line: it forwards the status JSON to the app, then runs the
/// previous status line command unchanged, so the terminal status line looks exactly the same.
public enum StatusLineRelay {
    static let path = "/m_notch/statusline"
    static let previousSeparator = "; printf '%s' \"$input\" | "

    public static func command(port: UInt16, token: String, previous: String?) -> String {
        var command = "input=$(cat) && printf '%s' \"$input\" | curl -s -m 0.5 --data-binary @- "
            + "-H 'Authorization: Bearer \(token)' http://127.0.0.1:\(port)\(path) >/dev/null 2>&1"
        if let previous, !previous.isEmpty { command += previousSeparator + previous }
        return command
    }

    public static func previousCommand(in command: String) -> String? {
        guard command.contains(path) else { return command }
        guard let range = command.range(of: previousSeparator) else { return nil }
        return String(command[range.upperBound...])
    }

    public static func status(port: UInt16, token: String, folder: String) -> HookStatus {
        do {
            let (settings, _) = try SettingsFileWriter.read(at: HookTarget.claude.fileURL(folder: folder))
            guard let current = (settings["statusLine"] as? [String: Any])?["command"] as? String,
                  current.contains(path) else { return .missing }
            return current.contains("Bearer \(token)") && current.contains(":\(port)\(path)") ? .installed : .outdated
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    public static func plan(install: Bool, port: UInt16, token: String, folder: String) throws -> HookInstallPlan {
        let url = HookTarget.claude.fileURL(folder: folder)
        var (settings, bytes) = try SettingsFileWriter.read(at: url)
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        let previous = (statusLine["command"] as? String).flatMap(previousCommand(in:))
        if install {
            statusLine["type"] = "command"
            statusLine["command"] = command(port: port, token: token, previous: previous)
            settings["statusLine"] = statusLine
        } else if let previous, !previous.isEmpty {
            statusLine["command"] = previous
            settings["statusLine"] = statusLine
        } else {
            settings["statusLine"] = nil
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return HookInstallPlan(url: url, newData: data + Data("\n".utf8), originalBytes: bytes)
    }
}
