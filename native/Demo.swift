import Foundation

/// Fixed window states for screenshots. Started with `--demo <name>`; the script never runs.
enum Demo {
    static let names = ["checking", "ready", "uptodate", "running", "finished", "failed", "stopped", "error",
                        "exclusions", "log"]

    private static func item(_ kind: Kind, _ name: String, _ from: String, _ to: String, _ bump: Bump,
                             _ state: ItemState = .pending, reason: String? = nil) -> QueueItem {
        var q = QueueItem(id: "\(kind.rawValue):\(name)", kind: kind, name: name, from: from, to: to, bump: bump)
        q.state = state
        q.reason = reason
        return q
    }

    private static func queue(states: [ItemState]) -> [QueueItem] {
        var items = [
            item(.formula, "ffmpeg", "7.1", "8.0", .major),
            item(.formula, "node", "22.9.0", "22.10.0", .minor),
            item(.formula, "supabase", "2.117.0", "2.120.0", .minor),
            item(.cask, "raycast", "1.93.2", "1.94.0", .minor),
            item(.cask, "figma", "125.1.0", "126.0.2", .major),
            item(.cask, "arc", "1.80.1", "1.80.2", .patch),
            item(.store, "Keynote", "14.1", "14.2", .update),
            item(.system, "macOS Tahoe 27.0.2", "", "", .update),
        ]
        for i in items.indices where i < states.count { items[i].state = states[i] }
        return items
    }

    private static func steps(_ statuses: [StepStatus], notes: [String] = []) -> [Step] {
        var all = RunModel.freshSteps()
        for i in all.indices where i < statuses.count {
            all[i].status = statuses[i]
            if i < notes.count { all[i].note = notes[i] }
        }
        return all
    }

    static func apply(_ name: String, to model: RunModel) {
        switch name {
        case "checking":
            model.demoSet(phase: .checking, queue: [], steps: steps([.running]), currentStep: 1)
        case "ready":
            model.demoSet(phase: .ready, queue: queue(states: []),
                          steps: steps([.done, .done, .done, .done, .skipped, .skipped]),
                          summary: RunSummary(seconds: 9, dryRun: true))
        case "uptodate":
            model.demoSet(phase: .ready, queue: [],
                          steps: steps([.done, .done, .done, .done, .skipped, .skipped]),
                          summary: RunSummary(seconds: 8, dryRun: true))
        case "running":
            model.demoSet(phase: .running, mode: .update,
                          queue: queue(states: [.done, .done, .done, .running, .pending, .pending, .pending]),
                          steps: steps([.done, .done, .running]), currentStep: 3)
        case "finished":
            model.demoSet(phase: .finished, mode: .update,
                          queue: queue(states: [.done, .done, .done, .done, .done, .done, .done]),
                          steps: steps([.done, .done, .done, .done, .done, .done]),
                          summary: RunSummary(seconds: 74, upgraded: 7, skipped: 0, failed: 0))
        case "failed":
            var items = queue(states: [.done, .done, .done, .done, .failed, .done, .done])
            items[4].reason = "Failed to download resource: connection reset by peer. Check the connection and run again."
            model.demoSet(phase: .finished, mode: .update, queue: items,
                          steps: steps([.done, .done, .failed, .done, .done, .done]),
                          summary: RunSummary(seconds: 81, upgraded: 6, skipped: 0, failed: 1))
        case "stopped":
            model.demoSet(phase: .finished, mode: .update,
                          queue: queue(states: [.done, .done, .pending, .pending, .pending, .pending, .pending]),
                          steps: steps([.done, .done, .running]), currentStep: 3, stopped: true)
        case "exclusions":
            apply("ready", to: model)
            model.showExclusions = true
        case "log":
            apply("finished", to: model)
            model.demoLog()
            model.showLog = true
        case "error":
            model.demoSet(phase: .failed, queue: [], steps: steps([.failed]),
                          failure: "No network connection. Check your connection and try again.")
        default:
            break
        }
    }
}
