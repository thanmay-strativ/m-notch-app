import Foundation

/// A terminal command that ran for a while and just ended, as the zsh hook reports it.
public struct FinishedCommand: Equatable, Sendable {
    public let command: String
    public let exitCode: Int
    public let seconds: Int
    public let folder: String
    public let finishedAt: Date

    public var succeeded: Bool { exitCode == 0 }

    /// "45s", "2m 10s", "1h 05m".
    public var durationText: String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return StatsFormat.duration(TimeInterval(seconds))
    }

    /// The hook posts a form body made by `curl --data-urlencode`: command=...&exit=0&seconds=42&cwd=/path.
    public init?(formBody: Data, finishedAt: Date) {
        let fields = Self.formFields(formBody)
        guard let command = fields["command"]?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty,
              let exitCode = fields["exit"].flatMap({ Int($0) }),
              let seconds = fields["seconds"].flatMap({ Int($0) }) else { return nil }
        self.command = command
        self.exitCode = exitCode
        self.seconds = seconds
        self.folder = URL(fileURLWithPath: fields["cwd"] ?? "/").lastPathComponent
        self.finishedAt = finishedAt
    }

    static func formFields(_ body: Data) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first.flatMap({ String($0).removingPercentEncoding }) else { continue }
            let rawValue = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: "+", with: " ") : ""
            fields[name] = rawValue.removingPercentEncoding ?? rawValue
        }
        return fields
    }
}

/// Reports terminal commands that run 30 s or more. The token and port live in a script m_notch owns;
/// ~/.zshrc only gets a marked line that loads it, so dotfiles never hold the token.
public enum ShellHook {
    static let path = "/m_notch/shell"
    static let minimumSeconds = 30
    static let beginMarker = "# >>> m_notch terminal hook >>>"
    static let endMarker = "# <<< m_notch terminal hook <<<"
    static let scriptRelativePath = "Library/Application Support/m_notch/terminal-hook.zsh"

    public enum Failure: LocalizedError, Equatable {
        case notText(String)

        public var errorDescription: String? {
            switch self {
            case .notText(let path): return "\(path) is not UTF-8 text. m_notch did not touch it."
            }
        }
    }

    public static func zshrcURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".zshrc")
    }

    public static func scriptURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(scriptRelativePath)
    }

    static var block: String {
        let script = "\"$HOME/\(scriptRelativePath)\""
        return "\(beginMarker)\n[[ -r \(script) ]] && source \(script)\n\(endMarker)"
    }

    /// Skips editors, pagers, remote shells, agents and bare REPLs (they run long because you use them),
    /// and commands you stopped with Ctrl-C (130) or Ctrl-Z (146 on macOS, 148 on Linux).
    static func script(port: UInt16, token: String) -> String {
        """
        # Written by m_notch: tells the notch when a terminal command that ran \(minimumSeconds) seconds or more ends.
        # m_notch rewrites this file. Remove the hook in m_notch Settings, Extras.
        zmodload zsh/datetime 2>/dev/null
        autoload -Uz add-zsh-hook
        typeset -ga _m_notch_skip=(vim vi nvim nano emacs less more man ssh mosh top htop btop tmux screen watch claude codex ipython psql mysql sqlite3 redis-cli)
        typeset -ga _m_notch_repls=(python python3 node irb)
        _m_notch_preexec() {
          _m_notch_command=$1
          _m_notch_started=$EPOCHSECONDS
        }
        _m_notch_precmd() {
          local exit_code=$?
          [[ -n $_m_notch_started ]] || return 0
          local seconds=$(( EPOCHSECONDS - _m_notch_started ))
          local command=$_m_notch_command
          unset _m_notch_started _m_notch_command
          (( seconds >= \(minimumSeconds) )) || return 0
          (( exit_code == 130 || exit_code == 146 || exit_code == 148 )) && return 0
          (( ${_m_notch_skip[(Ie)${${(z)command}[1]}]} || ${_m_notch_repls[(Ie)$command]} )) && return 0
          curl -s -m 2 -o /dev/null -H 'Authorization: Bearer \(token)' \\
            --data-urlencode "command=$command" --data-urlencode "exit=$exit_code" \\
            --data-urlencode "seconds=$seconds" --data-urlencode "cwd=$PWD" \\
            http://127.0.0.1:\(port)\(path) >/dev/null 2>&1 &!
        }
        add-zsh-hook preexec _m_notch_preexec
        precmd_functions=(_m_notch_precmd ${precmd_functions:#_m_notch_precmd})

        """
    }

    public static func status(port: UInt16, token: String, home: String = NSHomeDirectory()) -> HookStatus {
        do {
            guard try readText(at: zshrcURL(home: home)).text.contains(beginMarker) else { return .missing }
        } catch {
            return .unreadable(error.localizedDescription)
        }
        let installedScript = try? String(contentsOf: scriptURL(home: home), encoding: .utf8)
        return installedScript == script(port: port, token: token) ? .installed : .outdated
    }

    public static func isInZshrc(home: String = NSHomeDirectory()) throws -> Bool {
        try readText(at: zshrcURL(home: home)).text.contains(beginMarker)
    }

    /// The new ~/.zshrc: the marked block appended (install) or taken out (removal), everything else unchanged.
    public static func plan(install: Bool, home: String = NSHomeDirectory()) throws -> HookInstallPlan {
        let url = zshrcURL(home: home)
        let (text, bytes) = try readText(at: url)
        var newText = removingBlock(from: text)
        if install {
            if !newText.isEmpty && !newText.hasSuffix("\n") { newText += "\n" }
            newText += (newText.isEmpty ? "" : "\n") + block + "\n"
        }
        return HookInstallPlan(url: url, newData: Data(newText.utf8), originalBytes: bytes)
    }

    public static func writeScript(port: UInt16, token: String, home: String = NSHomeDirectory()) throws {
        let url = scriptURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script(port: port, token: token).utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
    }

    public static func removeScript(home: String = NSHomeDirectory()) throws {
        let url = scriptURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func removingBlock(from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(of: beginMarker),
              let end = lines[begin...].firstIndex(of: endMarker) else { return text }
        let start = begin > 0 && lines[begin - 1].isEmpty ? begin - 1 : begin
        lines.removeSubrange(start...end)
        return lines.joined(separator: "\n")
    }

    static func readText(at url: URL) throws -> (text: String, bytes: Data?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ("", nil) }
        guard let bytes = try? Data(contentsOf: url) else { throw SettingsFileWriter.Failure.unreadable(url.path) }
        guard let text = String(data: bytes, encoding: .utf8) else { throw Failure.notText(url.path) }
        return (text, bytes)
    }
}
