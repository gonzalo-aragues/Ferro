import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

/// Time-synced lyrics from LRCLIB (free, no API key).
enum LyricsService {
    private struct Entry: Decodable { let syncedLyrics: String? }

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> [LyricLine] {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: album),
        ]
        if duration > 0 { get.queryItems?.append(.init(name: "duration", value: String(Int(duration.rounded())))) }
        if let d = await request(get.url!), let e = try? JSONDecoder().decode(Entry.self, from: d),
           let lrc = e.syncedLyrics, !lrc.isEmpty {
            return parse(lrc)
        }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        if let d = await request(search.url!), let list = try? JSONDecoder().decode([Entry].self, from: d),
           let lrc = list.first(where: { ($0.syncedLyrics ?? "").isEmpty == false })?.syncedLyrics {
            return parse(lrc)
        }
        return []
    }

    private static func request(_ url: URL) async -> Data? {
        var r = URLRequest(url: url)
        r.setValue("Ferro/1.0", forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 8
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return d
    }

    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [(Double, String)] = []
        for raw in lrc.split(separator: "\n") {
            var line = Substring(raw)
            var times: [Double] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) { times.append(m * 60 + s) }
                line = line[line.index(after: close)...]
            }
            let text = line.trimmingCharacters(in: .whitespaces)
            for t in times { out.append((t, text.isEmpty ? "♪" : text)) }
        }
        return out.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
