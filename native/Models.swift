import Foundation

/// Where an update comes from.
enum Kind: String {
    case formula, cask, store, system, task

    var symbol: String {
        switch self {
        case .formula: return "shippingbox"
        case .cask: return "macwindow"
        case .store: return "bag"
        case .system: return "apple.logo"
        case .task: return "wrench.and.screwdriver"
        }
    }

    var plural: String {
        switch self {
        case .formula: return "formulae"
        case .cask: return "apps"
        case .store: return "App Store"
        case .system: return "macOS"
        case .task: return "tasks"
        }
    }

    /// Updates the app installs itself. macOS updates are left to System Settings.
    var installsHere: Bool { self != .system }
}

/// How big a version jump is.
enum Bump: String {
    case major, minor, patch, update
}

enum ItemState {
    case pending, running, done, skipped, failed
}

/// One pending update, from the first check through to its result.
struct QueueItem: Identifiable {
    let id: String
    let kind: Kind
    var name: String
    var from = ""
    var to = ""
    var bump: Bump = .update
    var state: ItemState = .pending
    var reason: String?

    var versions: String {
        if from.isEmpty && to.isEmpty { return "" }
        if from.isEmpty { return to }
        return "\(from)  →  \(to)"
    }
}

enum StepStatus {
    case pending, running, done, skipped, failed
}

/// One of the script's numbered sections, such as Casks or Cleanup.
struct Step: Identifiable {
    let id: Int
    var title: String
    var status: StepStatus = .pending
    var note = ""
    var seconds = 0
}

struct RunSummary {
    var seconds = 0
    var upgraded = 0
    var skipped = 0
    var failed = 0
    var dryRun = false
}

enum Phase {
    /// A read-only look at what is out of date. Runs on launch and on "Check Again".
    case checking
    /// The check finished; the queue shows what an update would install.
    case ready
    case running
    case finished
    /// The check itself could not finish.
    case failed
}

enum Mode {
    case check, update
}

/// The colour mood of the window, which follows what the app is doing.
enum Tone {
    case calm, active, success, attention
}
