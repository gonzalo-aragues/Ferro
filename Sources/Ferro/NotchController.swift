import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Allow the window to sit over the menu bar / notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Clicks land on buttons immediately, instead of the first click only focusing the panel.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController {
    let model = NotchModel()
    let media = MediaController()
    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let battery = BatteryMonitor()
    let timer = FocusTimer()
    let claude = ClaudeWatcher()

    private var panel: NotchPanel?
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var sticky = false

    func start() {
        layout()
        installMonitors()
        bindActivity()
        battery.onPlug = { [weak self] level in self?.model.flash(.charging(level), for: 3) }
        timer.onFinish = { [weak self] in self?.model.flash(.timerDone, for: 5) }
        clipboard.onCopiedFromIsland = { [weak self] in self?.model.flash(.copied, for: 1.4) }
        shelf.onAdded = { [weak self] n in self?.model.flash(.shelved(n)) }
        claude.onFinish = { [weak self] _ in
            self?.model.flash(.claudeDone, for: 4)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        claude.start()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.layout() }
    }

    // MARK: Geometry

    static func pickScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    static func notchSize(for s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        // No notch: draw our own island the height of the menu bar.
        return CGSize(width: 180, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
    }

    private func layout() {
        guard let s = Self.pickScreen() else { return }
        screen = s
        model.notchSize = Self.notchSize(for: s)
        let c = NotchModel.canvas
        let frame = NSRect(x: s.frame.midX - c.width / 2, y: s.frame.maxY - c.height,
                           width: c.width, height: c.height)
        if panel == nil {
            let p = NotchPanel(contentRect: frame)
            let root = NotchRootView()
                .environmentObject(model)
                .environmentObject(media)
                .environmentObject(shelf)
                .environmentObject(clipboard)
                .environmentObject(battery)
                .environmentObject(timer)
                .environmentObject(claude)
            let host = FirstMouseHostingView(rootView: root)
            host.sizingOptions = []
            p.contentView = host
            panel = p
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    // MARK: Hover / drag tracking

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) {
            monitors.append(l)
        }
    }

    private func handle(_ e: NSEvent) {
        guard let s = screen, let panel else { return }
        let p = NSEvent.mouseLocation
        if e.type == .leftMouseDown { dragChangeCount = NSPasteboard(name: .drag).changeCount }

        let outer = model.outerSize
        var rect = CGRect(x: s.frame.midX - outer.width / 2, y: s.frame.maxY - outer.height,
                          width: outer.width, height: outer.height)
        if !model.expanded { rect = rect.insetBy(dx: -10, dy: -8) }
        let inside = rect.contains(p)
        panel.ignoresMouseEvents = !inside

        // Feed the ferrofluid magnet.
        let body = model.bodySize
        MagnetField.shared.x = p.x - (s.frame.midX - body.width / 2)
        let distToBottom = body.height - (s.frame.maxY - p.y)
        MagnetField.shared.strength = (inside && model.expanded) ? max(0, min(1, 1 - distToBottom / 160)) : 0

        let isFileDrag = e.type == .leftMouseDragged && NSPasteboard(name: .drag).changeCount != dragChangeCount

        if inside {
            sticky = false
            collapseWork?.cancel(); collapseWork = nil
            if isFileDrag && model.tab != .shelf { withAnimation(.snappy) { model.tab = .shelf } }
            if !model.expanded && expandWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    self?.expandWork = nil
                    self?.setExpanded(true)
                }
                expandWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + (isFileDrag ? 0 : 0.1), execute: w)
            }
        } else {
            expandWork?.cancel(); expandWork = nil
            if model.expanded && !sticky && collapseWork == nil && !model.dropTargeted {
                let w = DispatchWorkItem { [weak self] in
                    self?.collapseWork = nil
                    self?.setExpanded(false)
                }
                collapseWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
            }
        }
    }

    func setExpanded(_ v: Bool, sticky: Bool = false) {
        if sticky { self.sticky = true }
        guard model.expanded != v else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.expanded = v }
        if v {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            panel?.ignoresMouseEvents = false
            panel?.makeKey()
        } else {
            panel?.ignoresMouseEvents = true
        }
        media.setFastPolling(v)
    }

    // MARK: Live activity in the collapsed pill

    private func bindActivity() {
        Publishers.CombineLatest(
            Publishers.CombineLatest4(media.$isPlaying, timer.$running, model.$toast, media.$title),
            claude.$sessions.map { $0.contains { $0.working } }.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] m, claudeWorking in
                let (playing, running, toast, title) = m
                let a: LiveActivity = toast ?? (running ? .timer : claudeWorking ? .claude
                                                : (playing && !title.isEmpty ? .music : .none))
                guard self?.model.activity != a else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { self?.model.activity = a }
            }
            .store(in: &bag)
    }
}
