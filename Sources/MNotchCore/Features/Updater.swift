import AppKit
import CryptoKit

/// A release on GitHub that is newer than the running app.
struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let notes: String
    let zipURL: URL
    let checksumURL: URL
}

/// Shown in Settings → About and the menu.
enum UpdateState: Equatable {
    case idle, checking, upToDate, installing
    case available(AvailableUpdate)
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Not checked yet"
        case .checking: return "Checking GitHub…"
        case .upToDate: return "Up to date"
        case .installing: return "Downloading and installing…"
        case .available(let update): return "Version \(update.version) is available"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

enum UpdateError: LocalizedError, Equatable {
    case httpStatus(Int, URL)
    case unreadableRelease(String)
    case missingAsset(String, tag: String)
    case unreadableChecksum(String)
    case checksumMismatch(expected: String, actual: String)
    case unzipFailed(Int32, String)
    case unexpectedApp(String)
    case cannotReplace(String, reason: String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let url): return "GitHub answered HTTP \(code) for \(url.absoluteString)"
        case .unreadableRelease(let preview): return "The release answer is not a GitHub release: \(preview)"
        case .missingAsset(let name, let tag): return "Release \(tag) has no \(name) file"
        case .unreadableChecksum(let preview): return "The checksum file does not start with a SHA-256: \(preview)"
        case .checksumMismatch(let expected, let actual): return "The download's SHA-256 is \(actual), the release says \(expected)"
        case .unzipFailed(let status, let path): return "ditto exited with status \(status) while unzipping \(path)"
        case .unexpectedApp(let detail): return "The download is not this app: \(detail)"
        case .cannotReplace(let path, let reason): return "Cannot replace \(path): \(reason)"
        }
    }
}

/// Updates from the GitHub releases of the m_notch repository. scripts/release.sh publishes a release with
/// m_notch.zip (the app, made by ditto) and m_notch.zip.sha256. Installing downloads both, checks the hash,
/// unzips next to the running app, swaps it in and opens the new copy once this one has quit.
enum Updater {
    static let repository = "thanmay-strativ/m-notch-app"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let zipName = "m_notch.zip"
    static let checksumName = "m_notch.zip.sha256"
    static let appName = "m_notch.app"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }

        let tagName: String
        let body: String?
        let assets: [Asset]
    }

    /// "0.1.10" is newer than "0.1.9". A "v" in front is ignored.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func trimmed(_ version: String) -> String { version.hasPrefix("v") ? String(version.dropFirst()) : version }
        return trimmed(candidate).compare(trimmed(current), options: .numeric) == .orderedDescending
    }

    /// Reads GitHub's "latest release" answer. nil when it is not newer than `current`.
    static func update(fromRelease data: Data, current: String) throws -> AvailableUpdate? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(Release.self, from: data) else {
            throw UpdateError.unreadableRelease(String(decoding: data.prefix(80), as: UTF8.self))
        }
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard isNewer(version, than: current) else { return nil }
        func asset(_ name: String) throws -> URL {
            guard let found = release.assets.first(where: { $0.name == name }) else {
                throw UpdateError.missingAsset(name, tag: release.tagName)
            }
            return found.browserDownloadUrl
        }
        return AvailableUpdate(version: version, notes: release.body ?? "",
                               zipURL: try asset(zipName), checksumURL: try asset(checksumName))
    }

    /// The first word of a `shasum -a 256` line.
    static func checksum(from data: Data) throws -> String {
        let text = String(decoding: data, as: UTF8.self)
        let hash = text.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else {
            throw UpdateError.unreadableChecksum(String(text.prefix(80)))
        }
        return hash
    }

    static func latest() async throws -> AvailableUpdate? {
        try update(fromRelease: try await download(latestReleaseURL), current: currentVersion)
    }

    /// Replaces the app at `appURL` with the release. The running copy keeps working until it quits.
    static func install(_ update: AvailableUpdate, over appURL: URL = Bundle.main.bundleURL) async throws {
        try checkReplaceable(appURL)
        let expected = try checksum(from: try await download(update.checksumURL))
        let zip = try await download(update.zipURL)
        let actual = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.checksumMismatch(expected: expected, actual: actual) }

        let workFolder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: appURL, create: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }
        let zipURL = workFolder.appendingPathComponent(zipName)
        try zip.write(to: zipURL)
        try await Task.detached { try unzip(zipURL, into: workFolder) }.value
        let newApp = workFolder.appendingPathComponent(appName)
        try checkIsThisApp(newApp, version: update.version)
        _ = try FileManager.default.replaceItemAt(appURL, withItemAt: newApp)
    }

    /// Opens `appURL` again once this process has exited, then quits.
    @MainActor
    static func relaunch(_ appURL: URL = Bundle.main.bundleURL) throws {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
                            "relaunch", String(ProcessInfo.processInfo.processIdentifier), appURL.path]
        try waiter.run()
        NSApp.terminate(nil)
    }

    private static func download(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else { throw UpdateError.httpStatus(statusCode, url) }
        return data
    }

    private static func checkReplaceable(_ appURL: URL) throws {
        if appURL.path.contains("/AppTranslocation/") {
            throw UpdateError.cannotReplace(appURL.path, reason: "macOS runs it from a temporary copy. Move m_notch.app to Applications and open it from there.")
        }
        let folder = appURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: folder) else {
            throw UpdateError.cannotReplace(appURL.path, reason: "your user cannot write to \(folder)")
        }
    }

    private static func unzip(_ zipURL: URL, into folder: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.unzipFailed(ditto.terminationStatus, zipURL.path) }
    }

    private static func checkIsThisApp(_ newApp: URL, version: String) throws {
        guard let bundle = Bundle(url: newApp) else { throw UpdateError.unexpectedApp("no \(appName) inside \(zipName)") }
        let bundleId = bundle.bundleIdentifier ?? "none"
        let bundleVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "none"
        guard bundleId == Bundle.main.bundleIdentifier, bundleVersion == version else {
            throw UpdateError.unexpectedApp("it is \(bundleId) \(bundleVersion), expected \(Bundle.main.bundleIdentifier ?? "none") \(version)")
        }
    }
}
