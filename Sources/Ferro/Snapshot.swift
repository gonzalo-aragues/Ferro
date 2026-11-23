import AppKit
import SwiftUI

/// `Ferro --snapshot <dir>` renders every tab offscreen to PNGs (no screen-recording permission needed).
enum Snapshot {
    static func run(dir: String) {
        GlassMode.fallback = true
        let model = NotchModel()
        model.notchSize = CGSize(width: 185, height: 32)
        model.expanded = true
        let media = MediaController(), shelf = ShelfStore(), clip = ClipboardStore()
        let battery = BatteryMonitor(), timer = FocusTimer()
        let root = NotchRootView()
            .environmentObject(model).environmentObject(media).environmentObject(shelf)
            .environmentObject(clip).environmentObject(battery).environmentObject(timer)
            .background(Color(white: 0.55))
        let c = NotchModel.canvas
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: c), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let host = NSHostingView(rootView: root)
        window.contentView = host
        MagnetField.shared.x = 300
        MagnetField.shared.strength = 1
        MagnetField.shared.smoothed = 1

        func shot(_ name: String) {
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote", url.path)
        }
        for tab in IslandTab.allCases {
            model.tab = tab
            shot("expanded-\(tab.rawValue)")
        }
        model.expanded = false
        model.activity = .charging(82)
        shot("collapsed-charging")
    }
}
