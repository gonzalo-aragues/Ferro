import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case music, shelf, clipboard, tools
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .music: "music.note"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .tools: "square.grid.2x2.fill"
        }
    }
}

enum LiveActivity: Equatable {
    case none, music, timer, timerDone, copied
    case charging(Int)
    case shelved(Int)
}

final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var tab: IslandTab = .music
    @Published var dropTargeted = false
    @Published var activity: LiveActivity = .none
    @Published var toast: LiveActivity?
    @Published var notchSize = CGSize(width: 190, height: 32)

    static let expandedBody = CGSize(width: 640, height: 300)
    /// Size of the transparent window the island lives in (room for shadows).
    static let canvas = CGSize(width: 760, height: 360)
    let wing: CGFloat = 60

    private var toastWork: DispatchWorkItem?

    var topRadius: CGFloat { expanded ? 14 : 6 }
    var bottomRadius: CGFloat { expanded ? 36 : 12 }

    var bodySize: CGSize {
        if expanded { return Self.expandedBody }
        if activity == .none { return notchSize }
        return CGSize(width: notchSize.width + wing * 2, height: notchSize.height)
    }

    var outerSize: CGSize { CGSize(width: bodySize.width + topRadius * 2, height: bodySize.height) }

    func flash(_ a: LiveActivity, for seconds: TimeInterval = 2.4) {
        toastWork?.cancel()
        toast = a
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }
}

/// Cursor "magnet" the ferrofluid reacts to. Read every frame by the canvas, so it's a plain class.
final class MagnetField {
    static let shared = MagnetField()
    var x: CGFloat = 0
    var strength: Double = 0
    var smoothed: Double = 0
}
