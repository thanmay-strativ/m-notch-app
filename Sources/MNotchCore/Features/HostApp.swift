import Foundation

/// The app a session runs inside, used for "jump to window" and quiet mode.
public enum HostApp: Equatable, Sendable {
    case pycharm
    case vscode
    case other(bundleId: String)
    case unknown

    public static let pycharmBundleIds = ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
    public static let vscodeBundleId = "com.microsoft.VSCode"

    public var displayName: String {
        switch self {
        case .pycharm: return "PyCharm"
        case .vscode: return "VS Code"
        case .other(let bundleId): return bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        case .unknown: return "Terminal"
        }
    }

    public var bundleIds: [String] {
        switch self {
        case .pycharm: return Self.pycharmBundleIds
        case .vscode: return [Self.vscodeBundleId]
        case .other(let bundleId): return [bundleId]
        case .unknown: return []
        }
    }

    public static func detect(hints: HostHints, rootMarker: String?) -> HostApp {
        if let bundleId = hints.bundleId {
            if bundleId.hasPrefix("com.jetbrains.pycharm") { return .pycharm }
            if bundleId == vscodeBundleId { return .vscode }
        }
        if hints.emulator == "JetBrains-JediTerm" { return .pycharm }
        if hints.termProgram == "vscode" || hints.entrypoint?.contains("vscode") == true { return .vscode }
        if let bundleId = hints.bundleId { return .other(bundleId: bundleId) }
        switch rootMarker {
        case ".idea": return .pycharm
        case ".vscode": return .vscode
        default: return .unknown
        }
    }
}

/// Finds the folder an IDE opened as its project, walking up from the session's cwd.
public enum ProjectRoot {
    public struct Result: Equatable, Sendable {
        public let path: String
        public let marker: String?
    }

    public static func markerGroups(for host: HostApp) -> [[String]] {
        switch host {
        case .pycharm: return [[".idea"], [".git"]]
        case .vscode: return [[".vscode", ".git"]]
        case .other, .unknown: return [[".idea", ".vscode", ".git"]]
        }
    }

    public static func find(cwd: String, markerGroups: [[String]], home: String = NSHomeDirectory(),
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Result {
        let start = URL(fileURLWithPath: cwd).standardizedFileURL.path
        for markers in markerGroups {
            var folder = start
            while folder != "/" && folder != home && !folder.isEmpty {
                if let marker = markers.first(where: { exists(folder + "/" + $0) }) {
                    return Result(path: folder, marker: marker)
                }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return Result(path: start, marker: nil)
    }

    public static func resolve(cwd: String, hints: HostHints, home: String = NSHomeDirectory(),
                               exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> (HostApp, Result) {
        var host = HostApp.detect(hints: hints, rootMarker: nil)
        if host == .unknown {
            let anyMarker = find(cwd: cwd, markerGroups: markerGroups(for: .unknown), home: home, exists: exists)
            host = HostApp.detect(hints: hints, rootMarker: anyMarker.marker)
        }
        return (host, find(cwd: cwd, markerGroups: markerGroups(for: host), home: home, exists: exists))
    }
}
