import AppKit
import AVFoundation
import IOKit.ps
import SwiftUI

// MARK: - Battery / charging

final class BatteryMonitor: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var charging = false
    @Published private(set) var onAC = false
    @Published private(set) var hasBattery = false
    var onPlug: ((Int) -> Void)?

    private var timer: Timer?
    private var primed = false

    init() {
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.read() }
    }

    private func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            hasBattery = true
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let lvl = max > 0 ? cur * 100 / max : cur
            if lvl != level { level = lvl }
            let ch = d[kIOPSIsChargingKey] as? Bool ?? false
            if ch != charging { charging = ch }
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if ac && !onAC && primed { onPlug?(lvl) }
            if ac != onAC { onAC = ac }
        }
        primed = true
    }

    var symbol: String {
        if onAC { return "battery.100percent.bolt" }
        let bucket = [0, 25, 50, 75, 100].min { abs($0 - level) < abs($1 - level) } ?? 100
        return "battery.\(bucket)percent"
    }
}

// MARK: - Focus timer

final class FocusTimer: ObservableObject {
    @Published private(set) var total: TimeInterval = 25 * 60
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var running = false
    var onFinish: (() -> Void)?

    private var ticker: Timer?
    private var endDate: Date?

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    func start() {
        guard !running else { return }
        if remaining <= 0 { remaining = total }
        endDate = Date().addingTimeInterval(remaining)
        running = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() {
        tick()
        running = false
        ticker?.invalidate()
    }

    func toggle() { running ? pause() : start() }

    func set(minutes: Double) {
        pause()
        total = minutes * 60
        remaining = total
    }

    func reset() { pause(); remaining = total }

    private func tick() {
        guard running, let e = endDate else { return }
        let r = max(0, e.timeIntervalSinceNow)
        if Int(r) != Int(remaining) || r == 0 { remaining = r }
        if r == 0 {
            running = false
            ticker?.invalidate()
            remaining = total
            NSSound(named: "Glass")?.play()
            onFinish?()
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Camera mirror

final class CameraView: NSView {
    private let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            if ok { DispatchQueue.main.async { self?.configure() } }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium
        session.addInput(input)
        session.commitConfiguration()
        if let c = preview.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    override func layout() {
        super.layout()
        preview.frame = bounds
    }

    func stop() {
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }
}

struct MirrorView: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraView { CameraView(frame: .zero) }
    func updateNSView(_ nsView: CameraView, context: Context) {}
    static func dismantleNSView(_ nsView: CameraView, coordinator: ()) { nsView.stop() }
}
