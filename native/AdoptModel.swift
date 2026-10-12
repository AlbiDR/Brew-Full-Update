import AppKit
import Foundation

/// An app installed by hand that a Homebrew cask could manage.
struct AdoptCandidate: Identifiable {
    var id: String { token }
    let token: String
    let app: String
    let installed: String
    let caskVersion: String
    let tap: String
    /// match, latest, unknown, newer or older (older cannot be adopted until the app is updated)
    let status: String
    var selected: Bool
    var state: ItemState = .pending
    var reason: String?

    var canAdopt: Bool { status != "older" }

    /// Where the app lives, so its real icon can be shown.
    var path: String? {
        let home = NSHomeDirectory()
        return ["/Applications/\(app).app", "\(home)/Applications/\(app).app"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}

/// An installed package whose tap is no longer added, so it can't receive updates.
struct OrphanTap: Identifiable {
    var id: String { name }
    let name: String
    let items: [String]
    var selected = true
    var state: ItemState = .pending
    var reason: String?
}

struct UnmatchedApp: Identifiable {
    var id: String { name }
    let name: String
    let installed: String
}

/// Finds apps and taps Homebrew could take over, and applies the ones you choose.
/// The script does the work; this reads its progress feed.
final class AdoptModel: ObservableObject {
    enum Phase { case idle, scanning, ready, applying, done, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var candidates: [AdoptCandidate] = []
    @Published private(set) var taps: [OrphanTap] = []
    @Published private(set) var unmatched: [UnmatchedApp] = []
    @Published private(set) var message: String?
    @Published var showing = false

    private let runner = ScriptRunner()
    private var queued: [[String]] = []
    private var currentName: String?
    private var lastFailed: String?
    private var demoMode = false

    init(demo: String? = nil) {
        guard let demo else { return }
        demoMode = true
        AdoptDemo.apply(demo, to: self)
    }

    // MARK: Derived

    var adoptable: [AdoptCandidate] { candidates.filter { $0.canAdopt } }
    var needsUpdate: [AdoptCandidate] { candidates.filter { !$0.canAdopt } }
    var selectedApps: [AdoptCandidate] { candidates.filter { $0.selected && $0.canAdopt } }
    var selectedTaps: [OrphanTap] { taps.filter { $0.selected } }
    var selectedCount: Int { selectedApps.count + selectedTaps.count }

    /// How many apps are ready to adopt right now, for the badge on the toolbar button.
    var readyCount: Int { adoptable.count }

    var finishedCount: Int {
        candidates.filter { $0.state == .done }.count + taps.filter { $0.state == .done }.count
    }
    var failedCount: Int {
        candidates.filter { $0.state == .failed }.count + taps.filter { $0.state == .failed }.count
    }

    // MARK: Actions

    func scan() {
        guard !runner.isRunning, !demoMode else { return }
        phase = .scanning
        message = nil
        candidates = []
        taps = []
        unmatched = []
        if let error = runner.start(arguments: ["--adopt-scan"],
                                    onLine: { [weak self] in self?.handle($0) },
                                    onExit: { [weak self] in self?.scanFinished($0) }) {
            message = error
            phase = .failed
        }
    }

    func toggle(app token: String) {
        guard let i = candidates.firstIndex(where: { $0.token == token }), candidates[i].canAdopt else { return }
        candidates[i].selected.toggle()
    }

    func toggle(tap name: String) {
        guard let i = taps.firstIndex(where: { $0.name == name }) else { return }
        taps[i].selected.toggle()
    }

    /// Taps go first, because an app may live in one of them.
    func applySelected() {
        guard !runner.isRunning, phase == .ready else { return }
        queued = []
        if !selectedTaps.isEmpty { queued.append(["--tap"] + selectedTaps.map(\.name)) }
        if !selectedApps.isEmpty { queued.append(["--adopt"] + selectedApps.map(\.token)) }
        guard !queued.isEmpty else { return }
        phase = .applying
        message = nil
        runNext()
    }

    /// Adds a tap by name, then looks again.
    func addTap(_ typed: String) {
        let name = typed.trimmingCharacters(in: .whitespaces)
        guard !runner.isRunning, Self.isValidTap(name) else { return }
        queued = [["--tap", name]]
        phase = .applying
        message = nil
        runNext()
    }

    func stop() {
        queued = []
        runner.stop()
    }

    static func isValidTap(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }

    // MARK: Running

    private func runNext() {
        guard !queued.isEmpty else {
            finishApplying()
            return
        }
        let arguments = queued.removeFirst()
        if let error = runner.start(arguments: arguments,
                                    onLine: { [weak self] in self?.handle($0) },
                                    onExit: { [weak self] _ in self?.runNext() }) {
            message = error
            phase = .failed
        }
    }

    private func finishApplying() {
        let done = finishedCount, failed = failedCount
        if failed > 0 {
            message = done > 0
                ? "\(done) adopted. \(failed) could not be adopted."
                : "Nothing was adopted. \(failed) could not be adopted."
        } else if done > 0 {
            message = done == 1 ? "1 item adopted." : "\(done) items adopted."
        }
        phase = .done
    }

    private func scanFinished(_ status: Int32) {
        if phase == .scanning {
            phase = status == 0 ? .ready : .failed
            if status != 0 { message = "The scan could not finish." }
        }
    }

    // MARK: Feed

    private func handle(_ line: String) {
        guard line.hasPrefix("@@BFU ") else { return }
        let f = line.dropFirst(6).components(separatedBy: "|")
        switch f[0] {
        case "adopt":
            guard f.count >= 7 else { return }
            let status = f[6]
            candidates.append(AdoptCandidate(token: f[1], app: f[2], installed: f[3], caskVersion: f[4],
                                             tap: f[5], status: status, selected: status == "match"))
        case "noncask":
            guard f.count >= 3 else { return }
            unmatched.append(UnmatchedApp(name: f[1], installed: f[2]))
        case "untapped":
            guard f.count >= 3 else { return }
            taps.append(OrphanTap(name: f[1], items: f[2].components(separatedBy: ",")))
        case "scandone":
            if phase == .scanning { phase = .ready }
        case "item":
            guard f.count >= 4 else { return }
            currentName = f[3]
            setState(.running)
        case "result":
            guard f.count >= 3 else { return }
            setState(f[1] == "fail" ? .failed : (f[1] == "skip" ? .skipped : .done))
        case "reason":
            guard let name = lastFailed else { return }
            let reason = f.dropFirst().joined(separator: "|")
            if let i = candidates.firstIndex(where: { $0.token == name }) { candidates[i].reason = reason }
            if let i = taps.firstIndex(where: { $0.name == name }) { taps[i].reason = reason }
        default:
            break
        }
    }

    private func setState(_ state: ItemState) {
        guard let name = currentName else { return }
        if let i = candidates.firstIndex(where: { $0.token == name }) { candidates[i].state = state }
        if let i = taps.firstIndex(where: { $0.name == name }) { taps[i].state = state }
        if state == .failed { lastFailed = name }
    }

    // MARK: Demo

    func demoSet(phase: Phase, candidates: [AdoptCandidate], taps: [OrphanTap], unmatched: [UnmatchedApp],
                 message: String? = nil, showing: Bool = true) {
        self.phase = phase
        self.candidates = candidates
        self.taps = taps
        self.unmatched = unmatched
        self.message = message
        self.showing = showing
    }
}

/// Fixed states for screenshots: `--demo adopt`, `adopt-running`, `adopt-done`, `adopt-empty`.
enum AdoptDemo {
    static func apply(_ name: String, to model: AdoptModel) {
        func c(_ token: String, _ app: String, _ installed: String, _ cask: String, _ tap: String = "homebrew/cask",
               _ status: String = "match", _ state: ItemState = .pending, selected: Bool = true,
               reason: String? = nil) -> AdoptCandidate {
            var x = AdoptCandidate(token: token, app: app, installed: installed, caskVersion: cask, tap: tap,
                                   status: status, selected: selected)
            x.state = state
            x.reason = reason
            return x
        }
        let unmatched = [UnmatchedApp(name: "Microsoft Word", installed: "16.109"),
                         UnmatchedApp(name: "OneDrive", installed: "26.173"),
                         UnmatchedApp(name: "TinkerTool", installed: "11.6")]
        let taps = [OrphanTap(name: "adamorad/tap", items: ["cask:deckcraft", "formula:supabase"])]
        switch name {
        case "adopt":
            model.demoSet(phase: .ready, candidates: [
                c("google-chrome", "Google Chrome", "155.0.8059.40", "155.0.8059.40"),
                c("vivaldi", "Vivaldi", "8.2.4133.84", "8.2.4133.84"),
                c("spotify", "Spotify", "1.3.4.258", "latest", "homebrew/cask", "latest", selected: false),
                c("deckcraft", "DeckCraft", "0.1.0", "0.5.0", "adamorad/tap", "older", selected: false),
            ], taps: taps, unmatched: unmatched)
        case "adopt-running":
            model.demoSet(phase: .applying, candidates: [
                c("google-chrome", "Google Chrome", "155.0.8059.40", "155.0.8059.40", "homebrew/cask", "match", .done),
                c("vivaldi", "Vivaldi", "8.2.4133.84", "8.2.4133.84", "homebrew/cask", "match", .running),
                c("spotify", "Spotify", "1.3.4.258", "latest", "homebrew/cask", "latest"),
            ], taps: [OrphanTap(name: "adamorad/tap", items: ["cask:deckcraft"], selected: true, state: .done)],
                          unmatched: unmatched)
        case "adopt-done":
            model.demoSet(phase: .done, candidates: [
                c("google-chrome", "Google Chrome", "155.0.8059.40", "155.0.8059.40", "homebrew/cask", "match", .done),
                c("vivaldi", "Vivaldi", "8.2.4133.84", "8.2.4133.84", "homebrew/cask", "match", .failed,
                  reason: "The installed app differs from the one Homebrew has. Update the app first, then adopt it"),
            ], taps: [OrphanTap(name: "adamorad/tap", items: ["cask:deckcraft"], selected: true, state: .done)],
                          unmatched: unmatched, message: "2 adopted. 1 could not be adopted.")
        case "adopt-empty":
            model.demoSet(phase: .ready, candidates: [], taps: [], unmatched: unmatched)
        case "adopt-scanning":
            model.demoSet(phase: .scanning, candidates: [], taps: [], unmatched: [])
        default:
            break
        }
    }
}
