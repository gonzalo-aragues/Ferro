import AppKit
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL?
    var text: String?
    var added = Date()
    var displayName: String { url?.lastPathComponent ?? text ?? "" }
}

/// Drag-and-drop shelf: drop files/images/text on the notch, drag them back out later.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = [] { didSet { save() } }
    var onAdded: ((Int) -> Void)?

    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ferro/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private let key = "ferro.shelf"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ShelfItem].self, from: d) {
            items = saved.filter { $0.url == nil || FileManager.default.fileExists(atPath: $0.url!.path) }
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }

    var fileURLs: [URL] { items.compactMap(\.url) }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var found: [ShelfItem] = []
        func add(_ i: ShelfItem) { lock.lock(); found.append(i); lock.unlock() }

        for p in providers {
            group.enter()
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { obj, _ in
                    defer { group.leave() }
                    if let d = obj as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { add(ShelfItem(url: u)) }
                    else if let u = obj as? URL { add(ShelfItem(url: u)) }
                }
            } else if p.canLoadObject(ofClass: NSImage.self) {
                _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                    defer { group.leave() }
                    if let img = obj as? NSImage, let u = Self.saveImage(img) { add(ShelfItem(url: u)) }
                }
            } else if p.canLoadObject(ofClass: NSURL.self) {
                _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                    defer { group.leave() }
                    if let u = obj as? URL { add(ShelfItem(text: u.absoluteString)) }
                }
            } else if p.canLoadObject(ofClass: NSString.self) {
                _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                    defer { group.leave() }
                    if let s = obj as? String, !s.isEmpty { add(ShelfItem(text: s)) }
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let fresh = found.filter { n in !self.items.contains { $0.url != nil && $0.url == n.url } }
            guard !fresh.isEmpty else { return }
            self.items.insert(contentsOf: fresh, at: 0)
            self.onAdded?(fresh.count)
        }
        return true
    }

    static func saveImage(_ img: NSImage, prefix: String = "Image") -> URL? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dir.appendingPathComponent("\(prefix) \(f.string(from: Date())) \(UUID().uuidString.prefix(4)).png")
        do { try png.write(to: url); return url } catch { return nil }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        // Only delete files we created ourselves (pasted images); originals stay where they were.
        if let u = item.url, u.path.hasPrefix(Self.dir.path) { try? FileManager.default.removeItem(at: u) }
    }

    func clear() { items.forEach(remove) }

    func open(_ item: ShelfItem) {
        if let u = item.url { NSWorkspace.shared.open(u) }
        else if let t = item.text, let u = URL(string: t), u.scheme?.hasPrefix("http") == true { NSWorkspace.shared.open(u) }
    }

    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    func airDrop(_ items: [ShelfItem]) {
        let payload: [Any] = items.compactMap { $0.url ?? ($0.text as Any?) }
        guard !payload.isEmpty, let s = NSSharingService(named: .sendViaAirDrop) else { return }
        s.perform(withItems: payload)
    }

    func copyText(_ item: ShelfItem) {
        guard let t = item.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
    }

    func provider(for item: ShelfItem) -> NSItemProvider {
        if let u = item.url { return NSItemProvider(contentsOf: u) ?? NSItemProvider(object: u as NSURL) }
        return NSItemProvider(object: (item.text ?? "") as NSString)
    }
}
