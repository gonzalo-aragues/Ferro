import SwiftUI

/// Island outline: flat top that flares outward into the menu bar, rounded bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let tr = topRadius, br = min(bottomRadius, (r.height - tr) , (r.width - 2 * tr) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr, y: r.minY + tr), control: CGPoint(x: r.minX + tr, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tr, y: r.maxY - br))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr + br, y: r.maxY), control: CGPoint(x: r.minX + tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr - br, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - tr, y: r.maxY - br), control: CGPoint(x: r.maxX - tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - tr, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Glossy black body with a living ferrofluid pool along the bottom edge.
struct FerroSurface: View {
    var expanded: Bool
    var energy: Double
    var accent: Color
    var inset: CGFloat
    /// Fraction of the height that stays solid black so the island blends into the notch.
    var solidTop: CGFloat = 0.12

    var body: some View {
        ZStack {
            // Expanded: black under the notch, melting into the Liquid Glass below.
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: solidTop),
                .init(color: .black.opacity(0.62), location: solidTop + 0.14),
                .init(color: .black.opacity(0.3), location: 0.62),
                .init(color: .black.opacity(0.42), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // Collapsed: solid black, indistinguishable from the hardware notch.
            Color.black.opacity(expanded ? 0 : 1)
            if expanded {
                TimelineView(.animation(minimumInterval: 1 / 45)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    ZStack(alignment: .bottom) {
                        gloss(t)
                        FerroPool(t: t, energy: energy, accent: accent)
                            .frame(height: 84)
                            .padding(.horizontal, inset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .transition(.opacity)
            }
        }
    }

    /// Slow drifting reflection, like light rolling across black glass.
    private func gloss(_ t: Double) -> some View {
        let x = sin(t * 0.22) * 0.32 + 0.5
        return ZStack {
            RadialGradient(colors: [accent.opacity(0.14), .clear],
                           center: UnitPoint(x: x, y: 0.05), startRadius: 0, endRadius: 340)
            // Caustic-like highlight drifting the other way, for a wetter glass look.
            RadialGradient(colors: [.white.opacity(0.06), .clear],
                           center: UnitPoint(x: 1 - x, y: 0.75), startRadius: 0, endRadius: 260)
            LinearGradient(colors: [.white.opacity(0.04), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

/// The ferrofluid itself: metaballs (blur + alpha threshold), filled with a glossy gradient
/// plus a specular rim on the upper edges.
struct FerroPool: View {
    let t: Double
    let energy: Double
    let accent: Color

    var body: some View {
        let blobs = FerroBlobs(t: t, energy: energy)
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(white: 0.34), location: 0.25),
                .init(color: Color(white: 0.10), location: 0.6),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .mask { blobs }

            // Specular rim: blob minus blob shifted down = thin bright upper edge.
            LinearGradient(colors: [.white.opacity(0.9), accent, .white.opacity(0.7)],
                           startPoint: .leading, endPoint: .trailing)
                .mask { blobs }
                .mask {
                    Rectangle()
                        .overlay(blobs.offset(y: 1.1).blendMode(.destinationOut))
                        .compositingGroup()
                }
                .opacity(0.38)
        }
        .drawingGroup()
    }
}

struct FerroBlobs: View {
    let t: Double
    let energy: Double

    var body: some View {
        Canvas { ctx, size in
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .white))
            ctx.addFilter(.blur(radius: 2.6))
            ctx.drawLayer { l in
                let w = size.width, h = size.height
                let field = MagnetField.shared
                field.smoothed += (field.strength - field.smoothed) * 0.12
                let pull = field.smoothed
                let base = h - 10

                // Pool
                l.fill(Path(CGRect(x: -20, y: base, width: w + 40, height: 40)), with: .color(.white))

                // Spikes: concave cones, like ferrofluid in a magnetic field.
                // Music makes them breathe, the cursor acts as the magnet.
                let spacing: CGFloat = 11
                let n = Int(w / spacing)
                for i in 0...n {
                    let x = CGFloat(i) * spacing + 5.5
                    let fi = Double(i)
                    let wave = (sin(t * 2.3 + fi * 0.57) * 0.5 + 0.5) * (sin(t * 1.21 - fi * 0.21) * 0.5 + 0.5)
                    let dx = Double(x - field.x)
                    let magnet = exp(-(dx * dx) / (2 * 46 * 46)) * pull
                    let lift = CGFloat(2 + wave * 22 * energy + magnet * 52)
                    let bw: CGFloat = 13 + CGFloat(magnet) * 3
                    var cone = Path()
                    cone.move(to: CGPoint(x: x - bw / 2, y: base + 3))
                    cone.addQuadCurve(to: CGPoint(x: x, y: base - lift),
                                      control: CGPoint(x: x - bw * 0.1, y: base - lift * 0.25))
                    cone.addQuadCurve(to: CGPoint(x: x + bw / 2, y: base + 3),
                                      control: CGPoint(x: x + bw * 0.1, y: base - lift * 0.25))
                    cone.closeSubpath()
                    l.fill(cone, with: .color(.white))
                }

                // Droplets that detach and fall back in.
                for k in 0..<3 {
                    let fk = Double(k)
                    let phase = (t * (0.35 + fk * 0.07) + fk * 0.37).truncatingRemainder(dividingBy: 1)
                    let hop = sin(phase * .pi) * (18 + 26 * energy)
                    let x = w * (0.22 + 0.28 * fk) + CGFloat(sin(t * 0.4 + fk * 2) * 40)
                    let r: CGFloat = 5 + CGFloat(energy) * 2
                    l.fill(Path(ellipseIn: CGRect(x: x - r, y: base - 6 - hop - r, width: r * 2, height: r * 2)),
                           with: .color(.white))
                }
            }
        }
    }
}

/// Tiny animated equalizer for the collapsed pill.
struct EQBars: View {
    var playing: Bool
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !playing)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let v = playing ? (sin(t * (5 + Double(i) * 1.7) + Double(i)) * 0.5 + 0.5) : 0.15
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: 3, height: 4 + 12 * v)
                }
            }
            .frame(height: 16)
        }
    }
}
