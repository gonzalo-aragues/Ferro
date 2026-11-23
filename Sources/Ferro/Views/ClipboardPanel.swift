import SwiftUI

struct ClipboardPanel: View {
    @EnvironmentObject var clipboard: ClipboardStore

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        if clipboard.items.isEmpty {
            EmptyState(symbol: "doc.on.clipboard", title: "Clipboard history",
                       subtitle: "Copy anything — it lands here. Click to copy again, or drag it out.")
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text("Click to copy · drag to drop · ★ to pin")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    PillButton(title: "Clear", symbol: "trash") { withAnimation(.snappy) { clipboard.clearUnpinned() } }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(clipboard.sorted) { ClipRow(item: $0) }
                    }
                    .padding(2)
                }
                .scrollClipDisabled(false)
            }
        }
    }
}

struct ClipRow: View {
    @EnvironmentObject var clipboard: ClipboardStore
    let item: ClipItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            thumb.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text(item.date, style: .relative)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { clipboard.togglePin(item) } } label: {
                Image(systemName: item.pinned ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.pinned ? .yellow : .white.opacity(hover ? 0.6 : 0))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .ferroGlass(RoundedRectangle(cornerRadius: 12, style: .continuous), tint: hover ? 0.25 : 0.5, interactive: true)
        .onHover { hover = $0 }
        .onTapGesture { clipboard.copy(item) }
        .onDrag { clipboard.provider(for: item) }
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Button(item.pinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
            Divider()
            Button("Delete") { clipboard.remove(item) }
        }
    }

    @ViewBuilder private var thumb: some View {
        switch item.kind {
        case .image(let u):
            if let img = NSImage(contentsOf: u) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case .files(let us):
            Image(nsImage: NSWorkspace.shared.icon(forFile: us[0].path)).resizable()
        case .text:
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(.white.opacity(0.08)))
        }
    }
}
