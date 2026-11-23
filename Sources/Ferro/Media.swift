import AppKit
import SwiftUI

enum PlayerSource: String {
    case none, music, spotify, system
    var bundleID: String? {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        default: nil
        }
    }
}

struct NowPlayingSnapshot {
    var source: PlayerSource
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var playing: Bool
    var artworkData: Data?
    var artworkURL: URL?
}

/// Now-playing state. Uses AppleScript for Music/Spotify (reliable on current macOS) and
/// falls back to the private MediaRemote framework for everything else.
final class MediaController: ObservableObject {
    @Published private(set) var source: PlayerSource = .none
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = Color(white: 0.85)
    @Published private(set) var lyrics: [LyricLine] = []
    @Published var volume: Double = 0.5

    private var elapsedAnchor: Double = 0
    private var anchorDate = Date()
    private var trackKey = ""
    private let queue = DispatchQueue(label: "ferro.media", qos: .userInitiated)
    private let remote = MediaRemoteBridge()
    private var pollTimer: Timer?
    private var scriptCache: [String: NSAppleScript] = [:]

    var hasTrack: Bool { !title.isEmpty }

    init() {
        schedule(1.5)
        refresh()
        refreshVolume()
    }

    func setFastPolling(_ fast: Bool) {
        schedule(fast ? 0.75 : 1.5)
        if fast { refresh(); refreshVolume() }
    }

    private func schedule(_ interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func elapsed(at date: Date = Date()) -> Double {
        guard isPlaying else { return elapsedAnchor }
        let e = elapsedAnchor + date.timeIntervalSince(anchorDate)
        return duration > 0 ? min(e, duration) : e
    }

    func lyricIndex(at date: Date) -> Int? {
        let t = elapsed(at: date) + 0.3
        return lyrics.lastIndex { $0.time <= t }
    }

    // MARK: Polling

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let snap = self.fetchSnapshot()
            DispatchQueue.main.async { self.apply(snap) }
        }
    }

    private func isRunning(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    private func fetchSnapshot() -> NowPlayingSnapshot? {
        var candidates: [NowPlayingSnapshot] = []
        if isRunning("com.spotify.client"), let d = run(Self.spotifyScript), let s = parse(d, .spotify) {
            candidates.append(s)
        }
        if isRunning("com.apple.Music"), let d = run(Self.musicScript), let s = parse(d, .music) {
            candidates.append(s)
        }
        if let playing = candidates.first(where: { $0.playing }) { return playing }
        if let mr = remote.snapshot(), !mr.title.isEmpty, mr.playing || candidates.isEmpty { return mr }
        return candidates.first
    }

    private func parse(_ d: NSAppleEventDescriptor, _ src: PlayerSource) -> NowPlayingSnapshot? {
        guard d.numberOfItems >= 6, let state = d.atIndex(1)?.stringValue, state != "stopped" else { return nil }
        var dur = d.atIndex(5)?.doubleValue ?? 0
        if src == .spotify { dur /= 1000 }
        var art: URL?
        if src == .spotify, d.numberOfItems >= 7, let s = d.atIndex(7)?.stringValue { art = URL(string: s) }
        return NowPlayingSnapshot(
            source: src,
            title: d.atIndex(2)?.stringValue ?? "",
            artist: d.atIndex(3)?.stringValue ?? "",
            album: d.atIndex(4)?.stringValue ?? "",
            duration: dur,
            elapsed: d.atIndex(6)?.doubleValue ?? 0,
            playing: state == "playing",
            artworkData: nil, artworkURL: art)
    }

    private func apply(_ s: NowPlayingSnapshot?) {
        guard let s, !s.title.isEmpty else {
            if hasTrack { clear() }
            return
        }
        if source != s.source { source = s.source }
        if isPlaying != s.playing { isPlaying = s.playing }
        elapsedAnchor = s.elapsed
        anchorDate = Date()
        let key = "\(s.title)|\(s.artist)"
        if key != trackKey {
            trackKey = key
            title = s.title
            artist = s.artist
            album = s.album
            lyrics = []
            loadArtwork(s)
            loadLyrics(s)
        }
        if duration != s.duration { duration = s.duration }
    }

    private func clear() {
        trackKey = ""; title = ""; artist = ""; album = ""
        isPlaying = false; duration = 0; artwork = nil; lyrics = []
        source = .none; accent = Color(white: 0.85)
    }

    private func loadArtwork(_ s: NowPlayingSnapshot) {
        let key = trackKey
        if let d = s.artworkData, let img = NSImage(data: d) { setArtwork(img); return }
        queue.async { [weak self] in
            guard let self else { return }
            var data: Data?
            if let url = s.artworkURL { data = try? Data(contentsOf: url) }
            else if s.source == .music { data = self.run(Self.musicArtScript)?.data }
            let img = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async { if self.trackKey == key { self.setArtwork(img) } }
        }
    }

    private func setArtwork(_ img: NSImage?) {
        artwork = img
        accent = img?.accentColor ?? Color(white: 0.85)
    }

    private func loadLyrics(_ s: NowPlayingSnapshot) {
        let key = trackKey
        Task { [weak self] in
            let lines = await LyricsService.fetch(title: s.title, artist: s.artist, album: s.album, duration: s.duration)
            await MainActor.run {
                guard let self, self.trackKey == key else { return }
                self.lyrics = lines
            }
        }
    }

    // MARK: Commands

    func togglePlay() {
        let e = elapsed()
        isPlaying.toggle()
        elapsedAnchor = e; anchorDate = Date()
        command("playpause", mr: 2)
    }
    func next() { command("next track", mr: 4) }
    func previous() { command("previous track", mr: 5) }

    func seek(to t: Double) {
        elapsedAnchor = t; anchorDate = Date()
        let src = source
        queue.async { [weak self] in
            if let id = src.bundleID {
                _ = self?.run("tell application id \"\(id)\" to set player position to \(t)", cache: false)
            } else {
                self?.remote.setElapsed(t)
            }
        }
    }

    private func command(_ verb: String, mr: UInt32) {
        let src = source
        queue.async { [weak self] in
            guard let self else { return }
            if let id = src.bundleID { _ = self.run("tell application id \"\(id)\" to \(verb)") }
            else { self.remote.send(mr) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
        }
    }

    func setVolume(_ v: Double) {
        volume = v
        let n = Int((v * 100).rounded())
        queue.async { [weak self] in _ = self?.run("set volume output volume \(n)", cache: false) }
    }

    private func refreshVolume() {
        queue.async { [weak self] in
            guard let self, let d = self.run("output volume of (get volume settings)") else { return }
            let v = Double(d.int32Value) / 100
            DispatchQueue.main.async { self.volume = v }
        }
    }

    func openPlayer(_ id: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: AppleScript

    /// Must be called on `queue`.
    private func run(_ source: String, cache: Bool = true) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if cache, let s = scriptCache[source] { script = s }
        else {
            guard let s = NSAppleScript(source: source) else { return nil }
            var err: NSDictionary?
            s.compileAndReturnError(&err)
            if err != nil { return nil }
            if cache { scriptCache[source] = s }
            script = s
        }
        var err: NSDictionary?
        let r = script.executeAndReturnError(&err)
        return err == nil ? r : nil
    }

    private static let spotifyScript = """
    tell application id "com.spotify.client"
        set ps to player state as string
        if ps is "stopped" then return {ps}
        set t to current track
        return {ps, name of t, artist of t, album of t, duration of t, player position, artwork url of t}
    end tell
    """

    private static let musicScript = """
    tell application id "com.apple.Music"
        set ps to player state as string
        if ps is "stopped" then return {ps}
        set t to current track
        return {ps, name of t, artist of t, album of t, duration of t, player position}
    end tell
    """

    private static let musicArtScript = """
    tell application id "com.apple.Music" to get raw data of artwork 1 of current track
    """
}

// MARK: - MediaRemote (private framework)

final class MediaRemoteBridge {
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias SendFn = @convention(c) (UInt32, NSDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private var getInfo: GetInfoFn?
    private var sendFn: SendFn?
    private var setElapsedFn: SetElapsedFn?

    init() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
        guard let b = CFBundleCreate(kCFAllocatorDefault, url) else { return }
        if let p = CFBundleGetFunctionPointerForName(b, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            getInfo = unsafeBitCast(p, to: GetInfoFn.self)
        }
        if let p = CFBundleGetFunctionPointerForName(b, "MRMediaRemoteSendCommand" as CFString) {
            sendFn = unsafeBitCast(p, to: SendFn.self)
        }
        if let p = CFBundleGetFunctionPointerForName(b, "MRMediaRemoteSetElapsedTime" as CFString) {
            setElapsedFn = unsafeBitCast(p, to: SetElapsedFn.self)
        }
    }

    func send(_ cmd: UInt32) { _ = sendFn?(cmd, nil) }
    func setElapsed(_ t: Double) { setElapsedFn?(t) }

    func snapshot() -> NowPlayingSnapshot? {
        guard let getInfo else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: NowPlayingSnapshot?
        getInfo(DispatchQueue.global(qos: .userInitiated)) { info in
            defer { sem.signal() }
            guard let d = info as? [String: Any],
                  let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String else { return }
            let rate = d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            var el = d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
            if rate > 0, let ts = d["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                el += Date().timeIntervalSince(ts) * rate
            }
            result = NowPlayingSnapshot(
                source: .system, title: title,
                artist: d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                album: d["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                duration: d["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0,
                elapsed: el, playing: rate > 0,
                artworkData: d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, artworkURL: nil)
        }
        _ = sem.wait(timeout: .now() + 0.6)
        return result
    }
}

extension NSImage {
    /// Average colour, pushed brighter/more saturated so it reads on black.
    var accentColor: Color? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 8
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        var r = 0.0, g = 0.0, b = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2])
        }
        let n = Double(side * side) * 255
        let c = NSColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return Color(hue: h, saturation: min(1, s * 1.35 + 0.08), brightness: max(0.78, v))
    }
}
