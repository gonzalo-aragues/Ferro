import SwiftUI

enum GlassMode {
    /// Offscreen snapshots can't capture Liquid Glass, so they use a material stand-in.
    static var fallback = false
}

extension View {
    /// Liquid Glass, kept dark enough for white text but clear enough to refract what's behind it.
    /// `tint` is the old darkness scale (0...1); it's halved so every surface reads as glass first.
    @ViewBuilder
    func ferroGlass<S: Shape>(_ shape: S, tint: Double = 0.45, interactive: Bool = false) -> some View {
        if GlassMode.fallback {
            self.background(shape.fill(Color.white.opacity(0.11)))
                .overlay(GlassRim(shape: shape))
        } else {
            let glass = Glass.regular.tint(Color.black.opacity(tint * 0.5))
            self.glassEffect(interactive ? glass.interactive() : glass, in: shape)
                .overlay(GlassRim(shape: shape))
        }
    }
}

/// Specular edge: bright where light hits the top-left, a faint bounce at the bottom-right.
struct GlassRim<S: Shape>: View {
    let shape: S
    var body: some View {
        shape.stroke(LinearGradient(stops: [
            .init(color: .white.opacity(0.5), location: 0),
            .init(color: .white.opacity(0.08), location: 0.35),
            .init(color: .white.opacity(0.02), location: 0.65),
            .init(color: .white.opacity(0.22), location: 1),
        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// The island's own glass layer.
struct IslandGlass<S: Shape>: View {
    let shape: S
    var body: some View {
        if GlassMode.fallback {
            shape.fill(Color(white: 0.2).opacity(0.85))
        } else {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.3)), in: shape)
        }
    }
}

/// Round glass icon button.
struct GlassIconButton: View {
    let symbol: String
    var size: CGFloat = 32
    var weight: Font.Weight = .semibold
    var prominent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: weight))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background {
                    if prominent { Circle().fill(.white) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .ferroGlass(Circle(), tint: prominent ? 0 : 0.4, interactive: true)
        .scaleEffect(hover ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small glass capsule text button.
struct PillButton: View {
    let title: String
    var symbol: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { if selected { Capsule().fill(.white) } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .ferroGlass(Capsule(), tint: 0.4, interactive: true)
    }
}

/// Thin draggable bar, used for the scrubber and volume.
struct GlassSlider: View {
    var value: Double            // 0...1
    var tint: Color = .white
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void = { _ in }
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), .white], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(dragging ? 8 : 5, g.size.width * min(1, max(0, value))))
                    .shadow(color: tint.opacity(0.6), radius: dragging ? 6 : 3)
            }
            .frame(height: dragging ? 8 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        onChange(min(1, max(0, v.location.x / g.size.width)))
                    }
                    .onEnded { v in
                        dragging = false
                        onCommit(min(1, max(0, v.location.x / g.size.width)))
                    }
            )
            .animation(.spring(response: 0.25), value: dragging)
        }
        .frame(height: 14)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
                .symbolEffect(.breathe)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
