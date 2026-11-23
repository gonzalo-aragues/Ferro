import Foundation

// Live view of Claude Code sessions, read from the transcripts Claude Code writes to
// ~/.claude/projects/<project>/<session>.jsonl. Works for the CLI and the desktop app, no setup needed.

struct ClaudeStep: Equatable, Identifiable {
    enum Status: Equatable { case pending, active, done }
    let id: Int
    var text: String
    var status: Status
}

struct ClaudeEvent: Equatable, Identifiable {
    enum Kind: Equatable { case tool, text }
    enum State: Equatable { case running, ok, failed }
    let id: String
    var kind: Kind
    var title: String
    var detail: String
    var state: State
    var result: String?
}

struct ClaudeSession: Equatable, Identifiable {
    let id: String
    var title: String
    var project: String
    var branch: String?
    var prompt: String
    var working: Bool
    var turnStart: Date?
    var turnEnd: Date?
    var lastActivity: Date
    var steps: [ClaudeStep]
    var events: [ClaudeEvent]
    var outputTokens: Int

    var doneSteps: Int { steps.filter { $0.status == .done }.count }

    func elapsed(at now: Date) -> TimeInterval {
        guard let s = turnStart else { return 0 }
        return max(0, (working ? now : (turnEnd ?? lastActivity)).timeIntervalSince(s))
    }

    /// What Claude is doing right now, for the collapsed pill.
    var currentAction: String? {
        events.last(where: { $0.kind == .tool && $0.state == .running }).map { $0.title }
    }
}

final class ClaudeWatcher: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    var onFinish: ((ClaudeSession) -> Void)?

    var isWorking: Bool { sessions.contains { $0.working } }

    private let queue = DispatchQueue(label: "ferro.claude", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var cache: [String: (mtime: Date, size: Int, session: ClaudeSession?)] = [:]
    private let root: URL = {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("projects")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }()

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let found = self.scan()
            DispatchQueue.main.async { self.publish(found) }
        }
        t.resume()
        timer = t
    }

    /// Synchronous refresh (used by `--snapshot`).
    func refreshNow() {
        let found = queue.sync { scan() }
        publish(found)
    }

    private func publish(_ found: [ClaudeSession]) {
        guard found != sessions else { return }
        let finished = sessions.filter { old in old.working && found.contains { $0.id == old.id && !$0.working } }
        sessions = found
        if let s = finished.first, let done = found.first(where: { $0.id == s.id }) { onFinish?(done) }
    }

    private func scan() -> [ClaudeSession] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let horizon = Date().addingTimeInterval(-6 * 3600)
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [ClaudeSession] = []
        var seen = Set<String>()
        for dir in dirs {
            // A project directory's mtime changes when a session file is created, not when one is appended to,
            // so we can't skip directories by date. Listing them is cheap.
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { continue }
            for f in files where f.pathExtension == "jsonl" {
                guard let v = try? f.resourceValues(forKeys: Set(keys)), let m = v.contentModificationDate, m > horizon else { continue }
                let size = v.fileSize ?? 0
                seen.insert(f.path)
                let session: ClaudeSession?
                if let c = cache[f.path], c.mtime == m, c.size == size {
                    session = c.session
                } else {
                    session = TranscriptParser.parse(f, mtime: m)
                    cache[f.path] = (m, size, session)
                }
                if var s = session {
                    // A turn that went quiet for a long time was abandoned (or the app quit mid-turn).
                    if s.working && Date().timeIntervalSince(s.lastActivity) > 20 * 60 { s.working = false }
                    if !s.prompt.isEmpty || !s.events.isEmpty { out.append(s) }
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        out.sort { a, b in a.working != b.working ? a.working : a.lastActivity > b.lastActivity }
        return Array(out.prefix(8))
    }
}

// MARK: - Transcript parsing

enum TranscriptParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let reminder = try! NSRegularExpression(pattern: "<system-reminder>[\\s\\S]*?</system-reminder>")
    private static let tail: UInt64 = 2_000_000

    static func parse(_ url: URL, mtime: Date) -> ClaudeSession? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return nil }
        let start = size > tail ? size - tail : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd() else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // partial line

        var p = State(id: url.deletingPathExtension().lastPathComponent, mtime: mtime)
        for line in lines {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            p.consume(obj)
        }
        return p.session()
    }

    private struct State {
        let id: String
        let mtime: Date
        var customTitle: String?
        var agentName: String?
        var summary: String?
        var cwd: String?
        var branch: String?
        var prompt = ""
        var working = false
        var turnStart: Date?
        var turnEnd: Date?
        var last: Date?
        var steps: [ClaudeStep] = []
        var events: [ClaudeEvent] = []
        var tokens: [String: Int] = [:]
        var toolNames: [String: String] = [:]

        init(id: String, mtime: Date) { self.id = id; self.mtime = mtime }

        mutating func consume(_ o: [String: Any]) {
            switch o["type"] as? String {
            case "custom-title": customTitle = o["customTitle"] as? String ?? customTitle
            case "agent-name": agentName = o["agentName"] as? String ?? agentName
            case "summary": summary = o["summary"] as? String ?? summary
            case "user": message(o, assistant: false)
            case "assistant": message(o, assistant: true)
            default: break
            }
        }

        mutating func message(_ o: [String: Any], assistant: Bool) {
            if o["isSidechain"] as? Bool == true { return }
            guard let msg = o["message"] as? [String: Any] else { return }
            let ts = (o["timestamp"] as? String).flatMap { TranscriptParser.iso.date(from: $0) } ?? last ?? mtime
            last = ts
            if let c = o["cwd"] as? String { cwd = c }
            if let b = o["gitBranch"] as? String, !b.isEmpty { branch = b }
            let meta = o["isMeta"] as? Bool == true

            if !assistant {
                if let s = msg["content"] as? String {
                    if !meta { userPrompt(s, at: ts) }
                } else if let blocks = msg["content"] as? [[String: Any]] {
                    for b in blocks {
                        switch b["type"] as? String {
                        case "tool_result": toolResult(b)
                        case "text": if !meta, let t = b["text"] as? String { userPrompt(t, at: ts) }
                        default: break
                        }
                    }
                }
                return
            }

            if let id = msg["id"] as? String, let u = msg["usage"] as? [String: Any], let out = u["output_tokens"] as? Int {
                tokens[id] = max(tokens[id] ?? 0, out)
            }
            for b in msg["content"] as? [[String: Any]] ?? [] {
                switch b["type"] as? String {
                case "text":
                    let t = (b["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        events.append(ClaudeEvent(id: "t\(events.count)-\(ts.timeIntervalSince1970)", kind: .text,
                                                  title: t, detail: "", state: .ok))
                    }
                case "tool_use":
                    tool(b)
                default: break
                }
            }
            switch msg["stop_reason"] as? String {
            case "end_turn", "stop_sequence", "max_tokens", "refusal":
                working = false
                turnEnd = ts
                for i in events.indices where events[i].state == .running { events[i].state = .ok }
            default:
                working = true
            }
            trim()
        }

        mutating func userPrompt(_ raw: String, at ts: Date) {
            var text = raw
            let ns = text as NSString
            text = TranscriptParser.reminder.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("[Request interrupted") {
                working = false
                turnEnd = ts
                for i in events.indices where events[i].state == .running { events[i].state = .failed }
                return
            }
            guard !text.isEmpty, !text.hasPrefix("<") else { return }
            prompt = text
            turnStart = ts
            turnEnd = nil
            working = true
            events = []
            tokens = [:]
        }

        mutating func tool(_ b: [String: Any]) {
            let name = b["name"] as? String ?? "Tool"
            let id = b["id"] as? String ?? UUID().uuidString
            let input = b["input"] as? [String: Any] ?? [:]
            toolNames[id] = name
            switch name {
            case "mcp__ccd_turn__update_plan": applyPlan(input); return
            case "mcp__ccd_turn__wrap_up": for i in steps.indices { steps[i].status = .done }; return
            case "TodoWrite": applyTodos(input); return
            case "ToolSearch": return
            default: break
            }
            let (title, detail) = describe(name, input)
            events.append(ClaudeEvent(id: id, kind: .tool, title: title, detail: detail, state: .running))
        }

        mutating func toolResult(_ b: [String: Any]) {
            guard let id = b["tool_use_id"] as? String, let i = events.lastIndex(where: { $0.id == id }) else { return }
            let text = TranscriptParser.text(of: b["content"])
            let failed = b["is_error"] as? Bool == true
            events[i].state = failed ? .failed : .ok
            events[i].result = failed ? firstLine(text) ?? "Error" : summarize(toolNames[id] ?? "", text)
        }

        mutating func applyPlan(_ input: [String: Any]) {
            if let items = input["items"] as? [[String: Any]] {
                steps = items.enumerated().map { i, it in
                    ClaudeStep(id: i, text: it["content"] as? String ?? "", status: status(it["status"] as? String))
                }
            }
            if input["advance"] as? Bool == true {
                if let i = steps.firstIndex(where: { $0.status == .active }) { steps[i].status = .done }
                if let j = steps.firstIndex(where: { $0.status == .pending }) { steps[j].status = .active }
            }
            for n in input["done"] as? [Int] ?? [] where steps.indices.contains(n - 1) { steps[n - 1].status = .done }
            if let s = input["start"] as? Int, steps.indices.contains(s - 1) { steps[s - 1].status = .active }
        }

        mutating func applyTodos(_ input: [String: Any]) {
            guard let todos = input["todos"] as? [[String: Any]] else { return }
            steps = todos.enumerated().map { i, t in
                let st = status(t["status"] as? String)
                let text = st == .active ? (t["activeForm"] as? String ?? t["content"] as? String ?? "") : (t["content"] as? String ?? "")
                return ClaudeStep(id: i, text: text, status: st)
            }
        }

        func status(_ s: String?) -> ClaudeStep.Status {
            switch s { case "completed": .done; case "in_progress": .active; default: .pending }
        }

        func describe(_ name: String, _ i: [String: Any]) -> (String, String) {
            func s(_ k: String) -> String { i[k] as? String ?? "" }
            switch name {
            case "Bash": return ("Bash", firstLine(s("command")) ?? "")
            case "Read": return ("Read", short(s("file_path")))
            case "Edit", "MultiEdit": return ("Update", short(s("file_path")))
            case "Write": return ("Write", short(s("file_path")))
            case "NotebookEdit": return ("Update", short(s("notebook_path")))
            case "Grep", "Glob": return ("Search", "pattern: \"\(s("pattern"))\"")
            case "WebFetch": return ("Fetch", s("url"))
            case "WebSearch": return ("Web Search", "\"\(s("query"))\"")
            case "Agent", "Task": return ("Task", s("description"))
            case "Skill": return ("Skill", s("skill"))
            default:
                if name.hasPrefix("mcp__") {
                    let parts = name.components(separatedBy: "__")
                    let server = parts.count > 1 ? parts[1].replacingOccurrences(of: "_", with: " ") : "mcp"
                    let tool = parts.count > 2 ? parts[2...].joined(separator: "__") : name
                    return ("\(server) - \(tool)", "")
                }
                return (name, "")
            }
        }

        func summarize(_ name: String, _ text: String) -> String {
            switch name {
            case "Read":
                let n = text.split(separator: "\n", omittingEmptySubsequences: false).count
                return "Read \(n) line\(n == 1 ? "" : "s")"
            case "Edit", "MultiEdit", "NotebookEdit": return "Updated"
            case "Write": return "Wrote file"
            default: return firstLine(text) ?? "(No content)"
            }
        }

        func short(_ path: String) -> String {
            if let cwd, path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
            let home = NSHomeDirectory()
            return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        }

        func firstLine(_ s: String) -> String? {
            s.split(separator: "\n").lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("<system-reminder>") }
                .map { String($0.prefix(160)) }
        }

        mutating func trim() {
            if events.count > 60 { events.removeFirst(events.count - 60) }
        }

        func session() -> ClaudeSession? {
            guard let last else { return nil }
            let project = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude"
            let title = customTitle ?? agentName ?? summary ?? String(prompt.prefix(60))
            return ClaudeSession(id: id, title: title.isEmpty ? project : title, project: project, branch: branch,
                                 prompt: prompt, working: working, turnStart: turnStart, turnEnd: turnEnd,
                                 lastActivity: max(last, mtime), steps: steps, events: events,
                                 outputTokens: tokens.values.reduce(0, +))
        }
    }

    static func text(of content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        }
        return ""
    }
}
