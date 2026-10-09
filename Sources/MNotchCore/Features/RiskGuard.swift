import Foundation

/// Flags commands and file writes that deserve Touch ID before "Allow".
/// ponytail: a pattern list is a speed bump, not a sandbox; extend the list when a miss shows up.
public enum RiskGuard {
    static let commandPatterns: [(pattern: String, reason: String)] = [
        (#"\brm\s+-[a-z]*(r[a-z]*f|f[a-z]*r)"#, "rm -rf"),
        (#"\brm\s+(-r|--recursive)\s+(-f|--force)\b"#, "rm -rf"),
        (#"\brm\s+(-f|--force)\s+(-r|--recursive)\b"#, "rm -rf"),
        (#"\bsudo\b"#, "sudo"),
        (#"\bgit\s+push\b[^;&|]*\s(--force|--force-with-lease|-f)\b"#, "git push --force"),
        (#"\bgit\s+reset\s+[^;&|]*--hard\b"#, "git reset --hard"),
        (#"\bgit\s+clean\s+-[a-z]*f"#, "git clean -f"),
        (#"\bdrop\s+(table|database|schema)\b"#, "DROP TABLE"),
        (#"\btruncate\b"#, "TRUNCATE"),
        (#"\b(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(sh|bash|zsh)\b"#, "pipes a download into a shell"),
        (#"\bchmod\s+-R\s+777\b"#, "chmod -R 777"),
        (#"\bdd\s+if="#, "dd"),
        (#"\bmkfs"#, "mkfs"),
        (#">\s*/dev/(sd|disk|nvme)"#, "writes to a disk device"),
    ]

    static let harmlessEnvSuffixes = [".example", ".sample", ".template"]

    public static func assess(toolName: String?, toolInput: JSONValue?, projectRoot: String,
                              home: String = NSHomeDirectory()) -> String? {
        switch toolName {
        case "Bash":
            return assess(command: toolInput?["command"]?.stringValue ?? "")
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            let path = toolInput?["file_path"]?.stringValue ?? toolInput?["notebook_path"]?.stringValue ?? ""
            return assess(filePath: path, projectRoot: projectRoot, home: home)
        default:
            return nil
        }
    }

    static func assess(command: String) -> String? {
        commandPatterns.first { command.range(of: $0.pattern, options: [.regularExpression, .caseInsensitive]) != nil }?.reason
    }

    static func assess(filePath: String, projectRoot: String, home: String) -> String? {
        guard !filePath.isEmpty else { return nil }
        let path = URL(fileURLWithPath: filePath).standardizedFileURL.path
        if path.hasPrefix(home + "/.ssh/") { return "writes to ~/.ssh" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name == ".env" || (name.hasPrefix(".env.") && !harmlessEnvSuffixes.contains { name.hasSuffix($0) }) {
            return "writes to \(name)"
        }
        if !path.hasPrefix(projectRoot + "/") { return "writes outside the project" }
        return nil
    }
}
