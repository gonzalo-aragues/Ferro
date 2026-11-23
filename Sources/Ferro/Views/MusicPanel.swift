import SwiftUI

struct MusicPanel: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        if media.hasTrack { player } else { empty }
    }

    private var player: some View {
        HStack(alignment: .top, spacing: 18) {
            Artwork(image: media.artwork, accent: media.accent, playing: media.isPlaying)
                .frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.title)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        Text(media.artist)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    SourceBadge(source: media.source)
                }
                LyricLineView()
                    .padding(.top, 8)
                Spacer(minLength: 6)
                Scrubber()
                HStack(spacing: 10) {
                    GlassIconButton(symbol: "backward.fill", size: 34) { media.previous() }
                    GlassIconButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 42, prominent: true) {
                        media.togglePlay()
                    }
                    GlassIconButton(symbol: "forward.fill", size: 34) { media.next() }
                    Spacer(minLength: 12)
                    VolumeControl()
                }
                .padding(.top, 4)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            EmptyState(symbol: "waveform", title: "Nothing playing", subtitle: "Start something and it shows up here")
                .frame(maxHeight: 90)
            HStack(spacing: 8) {
                PillButton(title: "Music", symbol: "music.note") { media.openPlayer("com.apple.Music") }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil {
                    PillButton(title: "Spotify", symbol: "dot.radiowaves.left.and.right") { media.openPlayer("com.spotify.client") }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Artwork: View {
    let image: NSImage?
    let accent: Color
    let playing: Bool

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(white: 0.18), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.5))
            }
            // Glass sheen
            LinearGradient(colors: [.white.opacity(0.22), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: accent.opacity(playing ? 0.55 : 0.2), radius: playing ? 22 : 10, y: 6)
        .scaleEffect(playing ? 1 : 0.93)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: playing)
        .animation(.easeInOut(duration: 0.4), value: image)
    }
}

struct SourceBadge: View {
    let source: PlayerSource
    var body: some View {
        if let id = source.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .opacity(0.85)
        }
    }
}

struct LyricLineView: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
            let idx = media.lyricIndex(at: tl.date)
            Group {
                if let idx, media.lyrics.indices.contains(idx) {
                    Text(media.lyrics[idx].text)
                        .id(idx)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                } else if !media.album.isEmpty {
                    Text(media.album).foregroundStyle(.white.opacity(0.35)).id(-1)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [.white, media.accent], startPoint: .leading, endPoint: .trailing))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: idx)
        }
        .frame(height: 34, alignment: .top)
        .clipped()
    }
}

struct Scrubber: View {
    @EnvironmentObject var media: MediaController
    @State private var scrub: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let el = scrub ?? media.elapsed(at: tl.date)
            let dur = max(media.duration, 0.001)
            VStack(spacing: 2) {
                GlassSlider(value: el / dur, tint: media.accent,
                            onChange: { scrub = $0 * dur },
                            onCommit: { media.seek(to: $0 * dur); scrub = nil })
                HStack {
                    Text(Self.fmt(el))
                    Spacer()
                    Text("-" + Self.fmt(max(0, media.duration - el)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    static func fmt(_ t: Double) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct VolumeControl: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: media.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                  variableValue: media.volume)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 18)
            GlassSlider(value: media.volume, tint: .white, onChange: { media.setVolume($0) })
                .frame(width: 92)
        }
    }
}
