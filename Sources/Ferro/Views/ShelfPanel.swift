import QuickLookThumbnailing
import SwiftUI

struct ShelfPanel: View {
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var model: NotchModel

    var body: some View {
        if shelf.items.isEmpty {
            dropZone
        } else {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { ShelfTile(item: $0) }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                HStack(spacing: 8) {
                    Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s") · drag out to use")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    PillButton(title: "AirDrop", symbol: "dot.radiowaves.up.forward") { shelf.airDrop(shelf.items) }
                    if !shelf.fileURLs.isEmpty {
                        PillButton(title: "Reveal", symbol: "folder") { shelf.reveal(shelf.fileURLs) }
                    }
                    PillButton(title: "Clear", symbol: "xmark") { withAnimation(.snappy) { shelf.clear() } }
                }
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
            .foregroundStyle(.white.opacity(model.dropTargeted ? 0.7 : 0.2))
            .overlay {
                EmptyState(symbol: model.dropTargeted ? "arrow.down.to.line.compact" : "tray",
                           title: model.dropTargeted ? "Let go to keep it here" : "Drop files, images, links or text",
                           subtitle: "Drag them back out whenever you need them")
            }
            .ferroGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: 0.55)
            .scaleEffect(model.dropTargeted ? 1.02 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.dropTargeted)
    }
}

struct ShelfTile: View {
    @EnvironmentObject var shelf: ShelfStore
    let item: ShelfItem
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url = item.url {
                    FileThumb(url: url)
                } else {
                    Image(systemName: (item.text ?? "").hasPrefix("http") ? "link" : "text.quote")
                        .font(.system(size: 26, weight: .light))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 70, height: 62)

            Text(item.displayName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 82, height: 26, alignment: .top)
        }
        .padding(8)
        .ferroGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: 0.45, interactive: true)
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { withAnimation(.snappy) { shelf.remove(item) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(hover ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { shelf.provider(for: item) }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            if let u = item.url { Button("Show in Finder") { shelf.reveal([u]) } }
            if item.text != nil { Button("Copy") { shelf.copyText(item) } }
            Button("AirDrop") { shelf.airDrop([item]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.displayName)
    }
}

struct FileThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .task(id: url) {
                let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 70, height: 62),
                                                       scale: 2, representationTypes: .thumbnail)
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                    image = rep.nsImage
                }
            }
    }
}
