import AppKit
import os

/// What macOS reports as playing (the Control Center "Now Playing" source): Music, Spotify, YouTube in a browser, ...
public struct NowPlayingTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval?
    public var elapsed: TimeInterval
    public var elapsedAt: Date
    public var rate: Double
    public var isPlaying: Bool
    public var appBundleId: String
    public var artwork: Data?

    public enum ParseError: LocalizedError, Equatable {
        case invalidLine(String)

        public var errorDescription: String? {
            switch self {
            case .invalidLine(let preview): return "Now playing line is not a JSON object: \(preview)"
            }
        }
    }

    /// The reported position plus the time since, at the reported speed. Paused tracks stay put.
    func position(at now: Date) -> TimeInterval {
        let speed = isPlaying && rate > 0 ? rate : 0
        let position = elapsed + max(0, now.timeIntervalSince(elapsedAt)) * speed
        return duration.map { min(position, $0) } ?? position
    }

    /// The track as it will be once a seek takes effect, so the progress bar stays where it was dropped.
    func seeked(to seconds: TimeInterval, now: Date) -> NowPlayingTrack {
        var track = self
        track.elapsed = min(max(0, seconds), duration ?? .greatestFiniteMagnitude)
        track.elapsedAt = now
        return track
    }

    /// The track as it will be once play/pause takes effect, so the controls answer at once.
    func toggled(now: Date) -> NowPlayingTrack {
        var track = self
        track.elapsed = position(at: now)
        track.elapsedAt = now
        track.isPlaying.toggle()
        if track.isPlaying && track.rate <= 0 { track.rate = 1 }
        return track
    }

    /// "1:23", "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let remainder = String(format: "%02d", total % 60)
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(remainder)" : "\(minutes):\(remainder)"
    }

    /// Reads one line from the helper. nil means nothing is playing. Artwork is only sent when it changes,
    /// so without an "artwork" key the previous artwork stays; an empty one means the track has none.
    static func parse(line: Data, previous: NowPlayingTrack?) throws -> NowPlayingTrack? {
        guard let fields = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            throw ParseError.invalidLine(String(String(decoding: line, as: UTF8.self).prefix(80)))
        }
        let title = (fields["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let duration = (fields["duration"] as? NSNumber)?.doubleValue
        let artwork: Data?
        if let encoded = fields["artwork"] as? String {
            artwork = encoded.isEmpty ? nil : Data(base64Encoded: encoded)
        } else {
            artwork = previous?.artwork
        }
        return NowPlayingTrack(
            title: title,
            artist: fields["artist"] as? String ?? "",
            album: fields["album"] as? String ?? "",
            duration: duration.flatMap { $0 > 0 ? $0 : nil },
            elapsed: (fields["elapsed"] as? NSNumber)?.doubleValue ?? 0,
            elapsedAt: Date(timeIntervalSince1970: (fields["elapsedAt"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970),
            rate: (fields["rate"] as? NSNumber)?.doubleValue ?? 0,
            isPlaying: (fields["playing"] as? NSNumber)?.boolValue ?? false,
            appBundleId: fields["app"] as? String ?? "",
            artwork: artwork)
    }
}

public enum NowPlayingCommand: Equatable, Sendable {
    case toggle, next, previous
    case seek(TimeInterval)

    /// The line the helper reads on stdin.
    var line: String {
        switch self {
        case .toggle: return "toggle"
        case .next: return "next"
        case .previous: return "previous"
        case .seek(let seconds): return "seek " + String(format: "%.2f", max(0, seconds))
        }
    }
}

/// Runs the now playing helper (Adapters/NowPlayingAdapter.m, built into the app) inside the system /usr/bin/perl,
/// because macOS only shares Now Playing with its own programs. Reads one JSON line per change and writes commands.
/// If the helper stops, it starts again after 5 s, doubling up to 5 min while it keeps failing.
@MainActor
final class NowPlayingWatcher {
    static let perlPath = "/usr/bin/perl"
    static let adapterName = "NowPlayingAdapter"
    static let firstRestartDelay: TimeInterval = 5
    static let longestRestartDelay: TimeInterval = 300
    static let loaderScript = """
        use strict;
        use DynaLoader;
        my $handle = DynaLoader::dl_load_file($ARGV[0], 0) or die "Could not load $ARGV[0]: " . DynaLoader::dl_error() . "\\n";
        my $symbol = DynaLoader::dl_find_symbol($handle, "m_notch_now_playing_stream") or die "No stream function in $ARGV[0]\\n";
        DynaLoader::dl_install_xsub("main::stream", $symbol);
        main::stream();
        """

    var onChange: (NowPlayingTrack?) -> Void = { _ in }
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }
    private var process: Process?
    private var commandPipe: Pipe?
    private var pendingOutput = Data()
    private var track: NowPlayingTrack?
    private var failedStarts = 0
    private let logger = Logger(subsystem: "local.mnotch", category: "nowplaying")

    func send(_ command: NowPlayingCommand) {
        guard let commandPipe else {
            logger.warning("Now playing command \(command.line, privacy: .public) dropped: the helper is not running")
            return
        }
        do {
            try commandPipe.fileHandleForWriting.write(contentsOf: Data((command.line + "\n").utf8))
        } catch {
            logger.error("Now playing command \(command.line, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func start() {
        guard process == nil else { return }
        guard let adapterURL = Bundle.main.url(forResource: Self.adapterName, withExtension: "dylib") else {
            logger.warning("\(Self.adapterName, privacy: .public).dylib is missing from \(Bundle.main.bundlePath, privacy: .public), so now playing is off")
            return
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: Self.perlPath)
        helper.arguments = ["-e", Self.loaderScript, adapterURL.path]
        let output = Pipe()
        let input = Pipe()
        let errors = Pipe()
        helper.standardOutput = output
        helper.standardInput = input
        helper.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        errors.fileHandleForReading.readabilityHandler = { [logger] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { logger.error("Now playing helper: \(text, privacy: .public)") }
        }
        helper.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.helperEnded(status: status) } }
        }
        do {
            try helper.run()
        } catch {
            logger.error("Could not start \(Self.perlPath, privacy: .public) for now playing: \(error.localizedDescription, privacy: .public)")
            scheduleRestart()
            return
        }
        process = helper
        commandPipe = input
    }

    private func stop() {
        let helper = process
        process = nil
        commandPipe = nil
        pendingOutput.removeAll()
        helper?.terminate()
        publish(nil)
    }

    private func receive(_ data: Data) {
        pendingOutput.append(data)
        while let newline = pendingOutput.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pendingOutput[pendingOutput.startIndex..<newline]
            pendingOutput.removeSubrange(pendingOutput.startIndex...newline)
            guard !line.isEmpty else { continue }
            do {
                failedStarts = 0
                publish(try NowPlayingTrack.parse(line: Data(line), previous: track))
            } catch {
                logger.warning("Ignored \(line.count, privacy: .public) bytes from the now playing helper: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func helperEnded(status: Int32) {
        guard process != nil else { return }
        process = nil
        commandPipe = nil
        pendingOutput.removeAll()
        publish(nil)
        logger.error("Now playing helper exited with status \(status, privacy: .public)")
        scheduleRestart()
    }

    private func scheduleRestart() {
        let delay = min(Self.longestRestartDelay, Self.firstRestartDelay * pow(2, Double(failedStarts)))
        failedStarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled, self.process == nil else { return }
                self.start()
            }
        }
    }

    private func publish(_ newTrack: NowPlayingTrack?) {
        guard newTrack != track else { return }
        track = newTrack
        onChange(newTrack)
    }
}

/// Name and icon of the app a track plays in, looked up once per app.
@MainActor
enum AppIdentity {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    static func name(for bundleId: String) -> String {
        if let cached = names[bundleId] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? ""
        names[bundleId] = name
        return name
    }

    static func icon(for bundleId: String) -> NSImage? {
        if let cached = icons[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleId] = icon
        return icon
    }
}
