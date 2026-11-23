import SwiftUI

/// Colors and type from Claude Code's dark terminal theme.
enum ClaudeTheme {
    static let claude = Color(red: 215 / 255, green: 119 / 255, blue: 87 / 255)
    static let shimmer = Color(red: 245 / 255, green: 179 / 255, blue: 147 / 255)
    static let success = Color(red: 78 / 255, green: 186 / 255, blue: 101 / 255)
    static let error = Color(red: 255 / 255, green: 107 / 255, blue: 128 / 255)
    static let text = Color.white
    static let dim = Color(white: 0.6)
    static let subtle = Color(white: 0.36)

    static func mono(_ size: CGFloat = 11, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    static func tokens(_ n: Int) -> String {
        n < 1000 ? "\(n)" : String(format: "%.1fk", Double(n) / 1000)
    }

    static let verbs = ["Thinking", "Pondering", "Crafting", "Brewing", "Noodling", "Percolating", "Tinkering",
                        "Conjuring", "Forging", "Simmering", "Mulling", "Wrangling", "Computing", "Cooking"]
}

/// Claude Code's spinner glyph: · ✢ ✳ ✶ ✻ ✽, ping-ponging.
struct ClaudeSpinner: View {
    var animating = true
    var size: CGFloat = 12
    var color: Color = ClaudeTheme.claude
    private static let frames = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { tl in
            let i = animating ? Int(tl.date.timeIntervalSinceReferenceDate / 0.12) % Self.frames.count : 4
            Text(Self.frames[i])
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: size * 1.1)
        }
    }
}

// MARK: - Panel

struct ClaudePanel: View {
    @EnvironmentObject var claude: ClaudeWatcher
    @State private var selected: String?

    private var index: Int {
        claude.sessions.firstIndex { $0.id == selected } ?? 0
    }

    var body: some View {
        Group {
            if claude.sessions.isEmpty {
                ClaudeWelcome()
            } else {
                let i = min(index, claude.sessions.count - 1)
                ClaudeSessionView(session: claude.sessions[i], position: i, count: claude.sessions.count) { step in
                    let n = claude.sessions.count
                    withAnimation(.snappy) { selected = claude.sessions[(i + step + n) % n].id }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ferroGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: 0.75)
        .environment(\.font, ClaudeTheme.mono())
    }
}

private struct ClaudeWelcome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("✻").foregroundStyle(ClaudeTheme.claude).font(ClaudeTheme.mono(13, .bold))
                Text("Claude Code").font(ClaudeTheme.mono(12, .bold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudeTheme.claude, lineWidth: 1))

            Text("No session running.")
            Text("Start Claude Code in a terminal or the desktop app\nand its progress shows up here, live.")
                .foregroundStyle(ClaudeTheme.dim)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ClaudeSpinner(animating: false)
                Text("Waiting for Claude…").foregroundStyle(ClaudeTheme.subtle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ClaudeSessionView: View {
    let session: ClaudeSession
    let position: Int
    let count: Int
    let move: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 12) {
                log
                if !session.steps.isEmpty {
                    Rectangle().fill(ClaudeTheme.subtle.opacity(0.6)).frame(width: 1)
                    todos.frame(width: 200)
                }
            }
            .frame(maxHeight: .infinity)
            StatusLine(session: session)
        }
    }

    // ╭ ✻ Claude Code · Ferro · main ─────── ‹ 1/2 › ╮
    private var header: some View {
        HStack(spacing: 6) {
            ClaudeSpinner(animating: session.working, size: 13)
            Text("Claude Code").font(ClaudeTheme.mono(11, .bold))
            Text(session.title)
                .foregroundStyle(ClaudeTheme.dim)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(session.branch.map { "\(session.project) ⎇ \($0)" } ?? session.project)
                .foregroundStyle(ClaudeTheme.subtle)
                .lineLimit(1)
            if count > 1 {
                HStack(spacing: 2) {
                    chevron("‹", -1)
                    Text("\(position + 1)/\(count)").foregroundStyle(ClaudeTheme.dim)
                    chevron("›", 1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudeTheme.claude.opacity(0.9), lineWidth: 1))
    }

    private func chevron(_ s: String, _ step: Int) -> some View {
        Button { move(step) } label: {
            Text(s).font(ClaudeTheme.mono(13, .bold)).foregroundStyle(ClaudeTheme.text)
                .frame(width: 14).contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    if !session.prompt.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(">").foregroundStyle(ClaudeTheme.dim)
                            Text(session.prompt.replacingOccurrences(of: "\n", with: " "))
                                .foregroundStyle(ClaudeTheme.dim)
                                .lineLimit(2)
                        }
                        .padding(.bottom, 2)
                    }
                    ForEach(session.events.suffix(24)) { EventRow(event: $0) }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.events) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
    }

    private var todos: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tasks \(session.doneSteps)/\(session.steps.count)").foregroundStyle(ClaudeTheme.dim)
                .padding(.bottom, 2)
            ForEach(session.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(step.status == .done ? "☒" : "☐")
                        .foregroundStyle(step.status == .active ? ClaudeTheme.claude : ClaudeTheme.dim)
                    Text(step.text)
                        .strikethrough(step.status == .done, color: ClaudeTheme.subtle)
                        .fontWeight(step.status == .active ? .bold : .regular)
                        .foregroundStyle(step.status == .done ? ClaudeTheme.subtle :
                                            step.status == .active ? ClaudeTheme.text : ClaudeTheme.dim)
                        .lineLimit(2)
                }
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy, value: session.steps)
    }
}

private struct EventRow: View {
    let event: ClaudeEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Dot(state: event.state, kind: event.kind)
            VStack(alignment: .leading, spacing: 2) {
                if event.kind == .text {
                    Text(event.title).foregroundStyle(ClaudeTheme.text).lineLimit(3)
                } else {
                    (Text(event.title).fontWeight(.bold).foregroundStyle(ClaudeTheme.text)
                     + Text(event.detail.isEmpty ? "" : "(\(event.detail))").foregroundStyle(ClaudeTheme.text.opacity(0.85)))
                        .lineLimit(1).truncationMode(.tail)
                    if let r = event.result {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("⎿").foregroundStyle(ClaudeTheme.subtle)
                            Text(r).foregroundStyle(event.state == .failed ? ClaudeTheme.error : ClaudeTheme.dim)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .padding(.leading, 2)
                    }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }
}

/// ⏺ — blinks while a tool runs, green when it worked, red when it failed.
private struct Dot: View {
    let state: ClaudeEvent.State
    let kind: ClaudeEvent.Kind

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let blink = state == .running && Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text("⏺")
                .foregroundStyle(color)
                .opacity(blink ? 0.25 : 1)
        }
        .font(ClaudeTheme.mono(9))
        .frame(width: 10)
    }

    private var color: Color {
        if kind == .text { return ClaudeTheme.text }
        switch state {
        case .running: return ClaudeTheme.dim
        case .ok: return ClaudeTheme.success
        case .failed: return ClaudeTheme.error
        }
    }
}

/// ✶ Crafting… (1m 12s · ↓ 3.4k tokens)   /   ✻ Worked for 4m 3s
struct StatusLine: View {
    let session: ClaudeSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !session.working)) { tl in
            let now = tl.date
            HStack(spacing: 6) {
                if session.working {
                    ClaudeSpinner()
                    ShimmerText(text: verb + "…", t: now.timeIntervalSinceReferenceDate)
                    Text("(\(ClaudeTheme.duration(session.elapsed(at: now))) · ↓ \(ClaudeTheme.tokens(session.outputTokens)) tokens)")
                        .foregroundStyle(ClaudeTheme.dim)
                } else {
                    Text("✻").foregroundStyle(ClaudeTheme.claude).font(ClaudeTheme.mono(12, .bold))
                    Text(session.turnStart == nil ? "Idle" : "Worked for \(ClaudeTheme.duration(session.elapsed(at: now)))")
                        .foregroundStyle(ClaudeTheme.dim)
                    Text("· \(session.lastActivity, style: .relative) ago").foregroundStyle(ClaudeTheme.subtle)
                }
                Spacer(minLength: 0)
                if let a = session.currentAction, session.working {
                    Text(a).foregroundStyle(ClaudeTheme.subtle).lineLimit(1)
                }
            }
            .lineLimit(1)
        }
    }

    private var verb: String {
        let seed = Int(session.turnStart?.timeIntervalSince1970 ?? 0)
        return ClaudeTheme.verbs[abs(seed) % ClaudeTheme.verbs.count]
    }
}

/// A highlight that sweeps across the text, like Claude Code's working indicator.
private struct ShimmerText: View {
    let text: String
    let t: Double

    var body: some View {
        let chars = Array(text)
        let span = Double(chars.count + 8)
        let pos = (t * 14).truncatingRemainder(dividingBy: span) - 4
        return chars.enumerated().reduce(Text("")) { acc, item in
            let d = abs(Double(item.offset) - pos)
            let c = d < 1 ? ClaudeTheme.shimmer : (d < 2.5 ? ClaudeTheme.shimmer.mix(with: ClaudeTheme.claude, by: 0.5) : ClaudeTheme.claude)
            return acc + Text(String(item.element)).foregroundStyle(c)
        }
    }
}
