import SwiftUI

/// The music tab: the artwork with a soft glow of its average color, title, artist and the app it plays in, a live
/// progress bar and the controls. The artwork eases smaller while paused, and the play button morphs into pause.
struct NowPlayingView: View {
    let model: IslandModel
    let actions: IslandActions

    var body: some View {
        if let track = model.nowPlaying {
            let artworkImage = track.artwork.flatMap(NSImage.init(data:))
            let glowColor = artworkImage.flatMap(ArtworkColor.average(of:)) ?? Palette.done
            HStack(alignment: .center, spacing: 16) {
                ArtworkTile(image: artworkImage, appBundleId: track.appBundleId, size: 96, cornerRadius: 16)
                    .scaleEffect(track.isPlaying ? 1 : 0.9)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
                    .id(track.title)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(verbatim: track.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Palette.text)
                        EqualizerBars(isPlaying: track.isPlaying)
                    }
                    if !artistLine(track).isEmpty {
                        Text(verbatim: artistLine(track)).font(.system(size: 11.5)).foregroundColor(Palette.secondary)
                            .padding(.top, 2)
                    }
                    AppBadge(bundleId: track.appBundleId).padding(.top, 5)
                    Spacer(minLength: 6)
                    TrackProgress(track: track) { seconds in actions.sendMediaCommand(.seek(seconds)) }
                    PlaybackControls(isPlaying: track.isPlaying, actions: actions).padding(.top, 8)
                }
                .lineLimit(1)
                .frame(height: IslandLayout.musicContentHeight - 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .leading) {
                Circle()
                    .fill(RadialGradient(colors: [glowColor.opacity(track.isPlaying ? 0.55 : 0.25), .clear],
                                         center: .center, startRadius: 10, endRadius: 100))
                    .saturation(1.5)
                    .frame(width: 210, height: 210)
                    .offset(x: 48 - 105)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.6), value: track.artwork)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: track.isPlaying)
        } else {
            Label("Nothing is playing", systemImage: "music.note")
                .font(.system(size: 12)).foregroundColor(Palette.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artistLine(_ track: NowPlayingTrack) -> String {
        [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// "♫ Song  Artist  [⏸]" above the sessions while a track is loaded; dimmed while paused. A click opens the music tab.
struct NowPlayingRow: View {
    let track: NowPlayingTrack
    let actions: IslandActions

    var body: some View {
        HStack(spacing: 8) {
            ArtworkTile(image: track.artwork.flatMap(NSImage.init(data:)), appBundleId: track.appBundleId, size: 18, cornerRadius: 4)
            EqualizerBars(isPlaying: track.isPlaying)
            Text(verbatim: track.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.text)
            if !track.artist.isEmpty {
                Text(verbatim: track.artist).font(.system(size: 11)).foregroundColor(Palette.tertiary)
            }
            Spacer(minLength: 4)
            Button { actions.sendMediaCommand(.toggle) } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundColor(Palette.text)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1)).clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(track.isPlaying ? "Pause" : "Play")
        }
        .bannerStyle()
        .opacity(track.isPlaying ? 1 : 0.7)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { actions.showMusic() } }
    }
}

/// The artwork, or the playing app's icon on a soft tile when the track has none.
struct ArtworkTile: View {
    let image: NSImage?
    let appBundleId: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(hex: "#2B2D33"), Color(hex: "#16171A")], startPoint: .top, endPoint: .bottom)
                    if let icon = AppIdentity.icon(for: appBundleId) {
                        Image(nsImage: icon).resizable().frame(width: size * 0.62, height: size * 0.62)
                    } else {
                        Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundColor(Palette.secondary)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The average color of the artwork, from a one-pixel redraw. It tints the glow behind the music tab.
enum ArtworkColor {
    @MainActor static func average(of image: NSImage) -> Color? {
        guard let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: pixel) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        return pixel.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB).map(Color.init(nsColor:))
    }
}

/// Four little bars that dance while playing and settle when paused.
struct EqualizerBars: View {
    let isPlaying: Bool
    private static let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<Self.speeds.count, id: \.self) { index in
                    Capsule()
                        .fill(Palette.done)
                        .frame(width: 2.5, height: isPlaying ? barHeight(time: time, index: index) : 3)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
        .animation(.easeOut(duration: 0.25), value: isPlaying)
    }

    private func barHeight(time: Double, index: Int) -> CGFloat {
        let wave = (sin(time * Self.speeds[index] + Double(index) * 1.3) + 1) / 2
        return 3 + CGFloat(wave) * 9
    }
}

/// "Google Chrome" with its icon.
struct AppBadge: View {
    let bundleId: String

    var body: some View {
        let name = AppIdentity.name(for: bundleId)
        if !name.isEmpty {
            HStack(spacing: 5) {
                if let icon = AppIdentity.icon(for: bundleId) {
                    Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                }
                Text(verbatim: name).font(.system(size: 10.5)).foregroundColor(Palette.tertiary)
            }
        }
    }
}

/// "1:23 ━━━━━━━●──── -2:05", gliding forward twice a second; "Live" when the track has no length.
/// Hovering thickens the bar and shows a knob; dragging or clicking it jumps the track there.
struct TrackProgress: View {
    let track: NowPlayingTrack
    let onSeek: (TimeInterval) -> Void
    @State private var scrubPosition: TimeInterval?
    @State private var isHovered = false

    private var isActive: Bool { isHovered || scrubPosition != nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = scrubPosition ?? track.position(at: context.date)
            HStack(spacing: 8) {
                Text(verbatim: NowPlayingTrack.clock(position)).frame(width: 40, alignment: .trailing)
                if let duration = track.duration {
                    GeometryReader { geometry in
                        let fraction = min(1, max(0, position / duration))
                        let barHeight: CGFloat = isActive ? 6 : 4
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(isActive ? 0.22 : 0.14)).frame(height: barHeight)
                            Capsule().fill(Palette.text).frame(width: geometry.size.width * fraction, height: barHeight)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 13, height: 13)
                                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                                .offset(x: geometry.size.width * fraction - 6.5)
                                .scaleEffect(isActive ? 1 : 0.2)
                                .opacity(isActive ? 1 : 0)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { drag in scrubPosition = seconds(at: drag.location.x, width: geometry.size.width, duration: duration) }
                            .onEnded { drag in
                                onSeek(seconds(at: drag.location.x, width: geometry.size.width, duration: duration))
                                scrubPosition = nil
                            })
                        .animation(scrubPosition == nil ? .linear(duration: 0.5) : nil, value: position)
                    }
                    .frame(height: 14)
                    .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
                    .help("Drag to move through the track")
                    Text(verbatim: "-" + NowPlayingTrack.clock(duration - position)).frame(width: 44, alignment: .leading)
                } else {
                    Text(verbatim: "Live").foregroundColor(Palette.danger)
                    Spacer(minLength: 0)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
            .foregroundColor(Palette.tertiary)
            .frame(height: 14)
        }
    }

    private func seconds(at x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return 0 }
        return duration * Double(min(1, max(0, x / width)))
    }
}

struct PlaybackControls: View {
    let isPlaying: Bool
    let actions: IslandActions

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            ControlButton(icon: "backward.fill", help: "Previous") { actions.sendMediaCommand(.previous) }
            ControlButton(icon: isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? "Pause" : "Play", isPrimary: true) {
                actions.sendMediaCommand(.toggle)
            }
            ControlButton(icon: "forward.fill", help: "Next") { actions.sendMediaCommand(.next) }
            Spacer(minLength: 0)
        }
    }
}

struct ControlButton: View {
    let icon: String
    let help: String
    var isPrimary = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isPrimary ? 14 : 11, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundColor(isPrimary ? Color(hex: "#0B0C0E") : Palette.text)
                .frame(width: isPrimary ? 32 : 28, height: isPrimary ? 32 : 28)
                .background(Circle().fill(isPrimary ? Palette.text : Color.white.opacity(isHovered ? 0.16 : 0.08)))
                .scaleEffect(isHovered ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
        .help(help)
    }
}
