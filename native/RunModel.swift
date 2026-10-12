import AppKit
import Foundation

/// Runs brew_full_update.zsh with the progress feed on and turns its lines into window state.
/// Everything here runs on the main thread, so the views can read it directly.
final class RunModel: ObservableObject {
    static let defaultTitles = ["Diagnostics", "Formulae", "Casks", "App Store", "Dev runtimes", "Cleanup"]

    @Published private(set) var phase: Phase = .checking
    @Published private(set) var mode: Mode = .check
    @Published private(set) var steps: [Step] = RunModel.freshSteps()
    @Published private(set) var currentStep = 0
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var summary: RunSummary?
    @Published private(set) var log: [String] = []
    @Published private(set) var excluded: [String] = []
    @Published private(set) var failureMessage: String?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var stopped = false
    @Published var showExclusions = false
    @Published var showLog = false

    private var process: Process?
    private var partial = ""
    private var launched = false
    private var lastFailed: Int?
    private var demoMode = false

    static func freshSteps() -> [Step] {
        defaultTitles.enumerated().map { Step(id: $0.offset + 1, title: $0.element) }
    }

    // MARK: Derived state

    /// Updates the app installs itself.
    var actionable: [QueueItem] { queue.filter { $0.kind.installsHere && $0.kind != .task } }
    /// macOS updates, which are only reported.
    var manual: [QueueItem] { queue.filter { $0.kind == .system } }
    var issues: [QueueItem] { queue.filter { $0.kind == .task } }

    var installedCount: Int { actionable.filter { $0.state == .done }.count }
    var failedCount: Int { queue.filter { $0.state == .failed }.count }
    var skippedCount: Int { actionable.filter { $0.state == .skipped }.count }
    var settledCount: Int {
        actionable.filter { [.done, .failed, .skipped].contains($0.state) }.count
    }

    var runningStep: Step? { steps.first { $0.status == .running } }

    /// 0...1 over the whole run. Inside the Formulae and Casks steps it follows the items.
    var progress: Double {
        switch phase {
        case .checking: return 0
        case .ready: return 0
        case .finished: return stopped ? progressNow : 1
        case .failed: return 0
        case .running: return progressNow
        }
    }

    private var progressNow: Double {
        let total = Double(max(steps.count, 1))
        let finished = Double(steps.filter { [.done, .skipped, .failed].contains($0.status) }.count)
        var fraction = 0.0
        if let step = runningStep, let kind = RunModel.kind(forStep: step.title) {
            let items = queue.filter { $0.kind == kind }
            if !items.isEmpty {
                let settled = items.filter { [.done, .failed, .skipped].contains($0.state) }.count
                fraction = Double(settled) / Double(items.count)
            }
        }
        return min((finished + fraction) / total, 1)
    }

    var tone: Tone {
        switch phase {
        case .checking, .ready: return .calm
        case .running: return .active
        case .finished: return failedCount > 0 || (summary?.failed ?? 0) > 0 ? .attention : .success
        case .failed: return .attention
        }
    }

    /// The update being installed right now, if any.
    var currentItem: QueueItem? { queue.first { $0.state == .running } }

    // MARK: Lifecycle

    /// Called once when the window appears: loads the exclusions and starts the first check.
    func launch() {
        guard !launched, !demoMode else { return }
        launched = true
        reloadExclusions()
        check()
    }

    func reloadExclusions() {
        guard !demoMode else { return }
        excluded = Exclusions.names()
    }

    func check() { run(.check) }
    func update() { run(.update) }

    /// Asks the script to stop. Its own trap cleans up the sudo session on the way out.
    func stop() {
        stopped = true
        process?.terminate()
    }

    private func run(_ mode: Mode) {
        guard process == nil else { return }
        guard let script = Bundle.main.url(forResource: "brew_full_update", withExtension: "zsh") else {
            failureMessage = "The update script is missing from the app."
            phase = .failed
            return
        }

        self.mode = mode
        steps = RunModel.freshSteps()
        currentStep = 0
        summary = nil
        log = []
        partial = ""
        failureMessage = nil
        stopped = false
        lastFailed = nil
        if mode == .check {
            queue = []
        } else {
            for i in queue.indices {
                queue[i].state = .pending
                queue[i].reason = nil
            }
            queue.removeAll { $0.kind == .task }
        }
        phase = mode == .check ? .checking : .running

        var env = ProcessInfo.processInfo.environment
        env["BFU_EVENTS"] = "1"
        env["NO_COLOR"] = "1"
        if let askpass = writeAskpass() { env["SUDO_ASKPASS"] = askpass.path }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "source \"$1\"; brew_full_update \"$2\"", "zsh", script.path, mode == .check ? "--dry-run" : ""]
        p.environment = env
        p.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                self?.consume(rest)
                self?.finish(status: code)
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            failureMessage = "Could not start: \(error.localizedDescription)"
            phase = .failed
        }
    }

    // MARK: Parsing the feed

    private func consume(_ text: String) {
        partial += text
        var lines = partial.components(separatedBy: "\n")
        partial = lines.removeLast()
        lines.forEach(handle)
    }

    private func handle(_ line: String) {
        guard line.hasPrefix("@@BFU ") else {
            appendLog(line)
            return
        }
        let f = line.dropFirst(6).components(separatedBy: "|")
        switch f[0] {
        case "step":
            guard f.count >= 4, let n = Int(f[1]) else { return }
            for i in steps.indices where steps[i].id < n && steps[i].status == .running {
                steps[i].status = RunModel.classify(steps[i].note)
            }
            let title = f[3...].joined(separator: "|")
            if let i = steps.firstIndex(where: { $0.id == n }) {
                steps[i].title = title
                steps[i].status = .running
            } else {
                steps.append(Step(id: n, title: title, status: .running))
            }
            currentStep = n
            if mode == .update, title == "App Store" {
                for i in queue.indices where queue[i].kind == .store && queue[i].state == .pending {
                    queue[i].state = .running
                }
            }
        case "note":
            if let i = steps.firstIndex(where: { $0.id == currentStep }) {
                steps[i].note = f.dropFirst().joined(separator: "|")
            }
        case "queued":
            guard f.count >= 6 else { return }
            addQueued(kind: f[1], name: f[2], from: f[3], to: f[4], bump: f[5])
        case "item":
            guard f.count >= 5 else { return }
            startItem(named: f[3])
        case "result":
            guard f.count >= 3 else { return }
            finishItem(status: f[1], text: f[2...].joined(separator: "|"))
        case "reason":
            if let i = lastFailed {
                queue[i].reason = f.dropFirst().joined(separator: "|")
            }
        case "row":
            guard f.count >= 5, let n = Int(f[1]), let i = steps.firstIndex(where: { $0.id == n }) else { return }
            steps[i].note = f[3]
            steps[i].seconds = Int(f[4]) ?? 0
            steps[i].status = RunModel.classify(f[3])
        case "summary":
            guard f.count >= 6 else { return }
            summary = RunSummary(
                seconds: Int(f[1]) ?? 0,
                upgraded: Int(f[2]) ?? 0,
                skipped: Int(f[3]) ?? 0,
                failed: Int(f[4]) ?? 0,
                dryRun: f[5] == "true"
            )
        default:
            break
        }
    }

    private func addQueued(kind rawKind: String, name rawName: String, from: String, to: String, bump rawBump: String) {
        guard let kind = Kind(rawValue: rawKind) else { return }
        var name = rawName, from = from, to = to
        if kind == .store {
            let parsed = RunModel.parseStoreLine(rawName)
            name = parsed.name; from = parsed.from; to = parsed.to
        }
        if kind == .formula, let last = name.split(separator: "/").last { name = String(last) }
        let id = "\(kind.rawValue):\(rawName)"
        let bump = Bump(rawValue: rawBump) ?? .update
        let item = QueueItem(id: id, kind: kind, name: name, from: from, to: to, bump: bump)
        if let i = queue.firstIndex(where: { $0.id == id }) {
            queue[i] = item
        } else {
            queue.append(item)
        }
    }

    /// "409183694  Keynote (14.1 -> 14.2)" -> name and the two versions.
    static func parseStoreLine(_ line: String) -> (name: String, from: String, to: String) {
        let pattern = #"^\s*\d+\s+(.+?)\s+\(\s*(.+?)\s*->\s*(.+?)\s*\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: line),
              let r2 = Range(m.range(at: 2), in: line),
              let r3 = Range(m.range(at: 3), in: line) else {
            return (line.trimmingCharacters(in: .whitespaces), "", "")
        }
        return (String(line[r1]), String(line[r2]), String(line[r3]))
    }

    private func startItem(named raw: String) {
        let name = raw.split(separator: "/").last.map(String.init) ?? raw
        let kind = runningStep.flatMap { RunModel.kind(forStep: $0.title) }
        if let i = queue.firstIndex(where: { $0.name == name && (kind == nil || $0.kind == kind) }) {
            queue[i].state = .running
        }
    }

    private func finishItem(status: String, text: String) {
        let state: ItemState = status == "fail" ? .failed : (status == "skip" ? .skipped : .done)
        if let i = queue.firstIndex(where: { $0.state == .running && $0.kind != .store }) {
            queue[i].state = state
            if state == .failed { lastFailed = i }
            return
        }
        // The App Store step upgrades everything in one call.
        if runningStep?.title == "App Store" {
            var touched = false
            for i in queue.indices where queue[i].kind == .store && queue[i].state == .running {
                queue[i].state = state
                if state == .failed { lastFailed = i }
                touched = true
            }
            if touched { return }
        }
        // Anything else that fails still has to be visible.
        if state == .failed {
            queue.append(QueueItem(id: "task:\(queue.count):\(text)", kind: .task, name: text, state: .failed))
            lastFailed = queue.count - 1
        }
    }

    private func finish(status: Int32) {
        if !partial.isEmpty {
            handle(partial)
            partial = ""
        }
        process = nil

        for i in steps.indices where steps[i].status == .running {
            steps[i].status = status == 0 ? RunModel.classify(steps[i].note) : .failed
        }
        for i in queue.indices where queue[i].state == .running {
            queue[i].state = status == 0 ? .done : .pending
        }

        switch mode {
        case .check:
            if status == 0, summary != nil {
                checkedAt = Date()
                phase = .ready
            } else {
                failureMessage = log.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                    ?? "The check could not finish."
                phase = .failed
            }
        case .update:
            if summary == nil && status != 0 && !stopped {
                failureMessage = "Stopped before finishing."
            }
            phase = .finished
            NSSound(named: "Glass")?.play()
        }
    }

    /// How a step's short note reads as a status, the same way the script's summary does.
    static func classify(_ note: String) -> StepStatus {
        let n = note.lowercased()
        if n.contains("failed") { return .failed }
        let skipped = ["skipped", "not installed", "dry run", "would", "not set up"]
        if skipped.contains(where: { n.contains($0) }) { return .skipped }
        return .done
    }

    static func kind(forStep title: String) -> Kind? {
        switch title {
        case "Formulae": return .formula
        case "Casks": return .cask
        case "App Store": return .store
        default: return nil
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 1500 { log.removeFirst(300) }
    }

    /// A small askpass helper for sudo, so the admin password prompt is a native dialog.
    /// Written on each run so it always matches the app.
    private func writeAskpass() -> URL? {
        let url = Exclusions.supportDir.appendingPathComponent("askpass.sh")
        let body = """
        #!/bin/sh
        # Password prompt for sudo, used only by Brew Full Update.
        /usr/bin/osascript -e 'text returned of (display dialog "Admin password needed to install app updates." default answer "" with hidden answer with title "Brew Command Center" buttons {"Cancel", "OK"} default button "OK")'
        """
        do {
            try FileManager.default.createDirectory(at: Exclusions.supportDir, withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Demo states

    /// Fills the model with a fixed state and never starts the script. Used for screenshots.
    init(demo: String? = nil) {
        guard let demo else { return }
        demoMode = true
        launched = true
        excluded = ["alfred", "daisydisk", "topaz-photo"]
        Demo.apply(demo, to: self)
    }

    func demoLog() {
        log = ["[2026-10-12 11:04:12] === brew_full_update ===", "==> Updating Homebrew...", "Already up-to-date.",
               "[2026-10-12 11:04:19] brew upgrade --formula ffmpeg", "==> Upgrading ffmpeg", "  7.1 -> 8.0",
               "==> Pouring ffmpeg--8.0.arm64_tahoe.bottle.tar.gz", "🍺  /opt/homebrew/Cellar/ffmpeg/8.0: 291 files, 54MB"]
    }

    /// Hooks for Demo, which sets state the script would normally produce.
    func demoSet(phase: Phase, mode: Mode = .check, queue: [QueueItem], steps: [Step]? = nil,
                 currentStep: Int = 0, summary: RunSummary? = nil, stopped: Bool = false,
                 failure: String? = nil) {
        self.phase = phase
        self.mode = mode
        self.queue = queue
        if let steps { self.steps = steps }
        self.currentStep = currentStep
        self.summary = summary
        self.stopped = stopped
        self.failureMessage = failure
        self.checkedAt = Date()
    }
}
