import SwiftUI

struct ToolsPanel: View {
    var body: some View {
        HStack(spacing: 10) {
            TimerCard()
            MirrorCard()
            NoteCard()
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ferroGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: 0.5)
    }
}

struct TimerCard: View {
    @EnvironmentObject var timer: FocusTimer

    var body: some View {
        Card(title: "Focus", symbol: "timer") {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .orange.opacity(0.6), radius: 5)
                    Text(FocusTimer.format(timer.remaining))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 62, height: 62)
                .animation(.linear(duration: 0.25), value: timer.progress)

                VStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach([5.0, 15, 25], id: \.self) { m in
                            PillButton(title: "\(Int(m))", selected: timer.total == m * 60 && !timer.running) {
                                timer.set(minutes: m)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        GlassIconButton(symbol: timer.running ? "pause.fill" : "play.fill", size: 30, prominent: true) {
                            timer.toggle()
                        }
                        GlassIconButton(symbol: "arrow.counterclockwise", size: 30) { timer.reset() }
                    }
                }
            }
        }
    }
}

struct MirrorCard: View {
    @State private var on = false

    var body: some View {
        Card(title: "Mirror", symbol: "camera") {
            ZStack {
                if on {
                    MirrorView()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture { on = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Button { withAnimation(.spring(response: 0.4)) { on = true } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "person.crop.square")
                                .font(.system(size: 26, weight: .light))
                            Text("Check yourself").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
    }
}

struct NoteCard: View {
    @AppStorage("ferro.note") private var note = ""

    var body: some View {
        Card(title: "Scratchpad", symbol: "square.and.pencil") {
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Jot something…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 1)
                        .padding(.leading, 5)
                }
                TextEditor(text: $note)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
            }
        }
    }
}
