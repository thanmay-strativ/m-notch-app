// Ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import Foundation

/// Reads and rewrites a settings file m_notch does not own: never treats an unreadable file as empty,
/// always backs up first, and only writes over the exact bytes the user saw in the preview.
public enum SettingsFileWriter {
    public enum Failure: LocalizedError, Equatable {
        case unreadable(String)
        case invalid(String)
        case changed(String)
        case backupFailed(String)
        case writeFailed(String)
        case unexpectedHooks(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let path): return "\(path) cannot be read. m_notch did not touch it."
            case .invalid(let path): return "\(path) is not valid JSON. m_notch did not touch it."
            case .changed(let path): return "\(path) changed since the preview. Nothing was written, try again."
            case .backupFailed(let path): return "Could not back up \(path). Nothing was written."
            case .writeFailed(let path): return "Could not write \(path). The original is untouched."
            case .unexpectedHooks(let path): return "\(path): \"hooks\" has an unexpected type. m_notch did not touch it."
            }
        }
    }

    public static func read(at url: URL) throws -> (object: [String: Any], bytes: Data?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([:], nil) }
        guard let bytes = try? Data(contentsOf: url) else { throw Failure.unreadable(url.path) }
        if bytes.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) { return ([:], bytes) }
        guard let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
            throw Failure.invalid(url.path)
        }
        return (object, bytes)
    }

    public static func hooks(in settings: [String: Any], path: String) throws -> [String: Any] {
        guard let value = settings["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else { throw Failure.unexpectedHooks(path) }
        return hooks
    }

    public static func hookGroups(in hooks: [String: Any], event: String, path: String) throws -> [[String: Any]] {
        guard let value = hooks[event] else { return [] }
        guard let groups = value as? [[String: Any]] else { throw Failure.unexpectedHooks(path) }
        return groups
    }

    @discardableResult
    public static func write(_ data: Data, to url: URL, expecting original: Data?) throws -> URL? {
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: url.path)
        var current: Data?
        if exists {
            guard let bytes = try? Data(contentsOf: url) else { throw Failure.unreadable(url.path) }
            current = bytes
        }
        guard current == original else { throw Failure.changed(url.path) }

        let target = url.resolvingSymlinksInPath()
        var backupURL: URL?
        var mode = 0o600
        if exists {
            let backup = freeBackupURL(for: url)
            do { try fileManager.copyItem(at: target, to: backup) } catch { throw Failure.backupFailed(url.path) }
            backupURL = backup
            if let found = (try? fileManager.attributesOfItem(atPath: target.path))?[.posixPermissions] as? NSNumber {
                mode = found.intValue & 0o777
            }
        } else {
            try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent("\(target.lastPathComponent).m_notch-\(ProcessInfo.processInfo.processIdentifier)")
        try? fileManager.removeItem(at: temporary)
        guard fileManager.createFile(atPath: temporary.path, contents: data,
                                     attributes: [.posixPermissions: NSNumber(value: 0o600)]) else {
            throw Failure.writeFailed(url.path)
        }
        do {
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: temporary.path)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw Failure.writeFailed(url.path)
        }
        guard rename(temporary.path, target.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw Failure.writeFailed(url.path)
        }
        return backupURL
    }

    static func freeBackupURL(for url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(url.lastPathComponent).bak-\(formatter.string(from: Date()))"
        let folder = url.deletingLastPathComponent()
        var candidate = folder.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(suffix)")
            suffix += 1
        }
        return candidate
    }
}
