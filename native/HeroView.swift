import SwiftUI

// MARK: - Words

extension RunModel {
    var headline: String {
        switch phase {
        case .checking:
            return "Checking for updates"
        case .ready:
            let n = actionable.count
            if n == 0 { return manual.isEmpty ? "Everything is up to date" : "Only macOS updates are waiting" }
            return n == 1 ? "1 update available" : "\(n) updates available"
        case .running:
            return "Updating"
        case .finished:
            if stopped { return "Update stopped" }
            let failed = failedCount
            if failed > 0 { return failed == 1 ? "1 update needs attention" : "\(failed) updates need attention" }
            let n = installedCount
            if n == 0 { return "Everything is up to date" }
            return n == 1 ? "Updated 1 item" : "Updated \(n) items"
        case .failed:
            return "Couldn’t check for updates"
        }
    }

    var subline: String {
        switch phase {
        case .checking:
            switch runningStep?.title {
            case "Diagnostics": return "Asking Homebrew what’s new"
            case "Formulae": return "Reading command-line tools"
            case "Casks": return "Looking at your apps"
            case "App Store": return "Checking the App Store and macOS"
            case "Dev runtimes": return "Looking at developer tools"
            default: return "Getting ready"
            }
        case .ready:
            if actionable.isEmpty {
                return manual.isEmpty ? "Checked \(checkedText)" : "Install them in System Settings"
            }
            var parts = RunModel.counts(actionable)
            if !manual.isEmpty { parts.append("macOS in System Settings") }
            return parts.joined(separator: "  ·  ")
        case .running:
            if let item = currentItem {
                return item.versions.isEmpty ? "Installing \(item.name)" : "Installing \(item.name)  \(item.versions)"
            }
            if let step = runningStep { return step.title }
            return "Starting"
        case .finished:
            if stopped { return "\(installedCount) of \(actionable.count) installed" }
            if let summary { return "Finished in \(RunModel.duration(summary.seconds))" }
            return failureMessage ?? ""
        case .failed:
            return failureMessage ?? "Something went wrong."
        }
    }

    /// "2 formulae · 3 apps · 1 App Store update"
    static func counts(_ items: [QueueItem]) -> [String] {
        func n(_ kind: Kind) -> Int { items.filter { $0.kind == kind }.count }
        var parts: [String] = []
        let formulae = n(.formula), apps = n(.cask), store = n(.store)
        if formulae > 0 { parts.append(formulae == 1 ? "1 formula" : "\(formulae) formulae") }
        if apps > 0 { parts.append(apps == 1 ? "1 app" : "\(apps) apps") }
        if store > 0 { parts.append(store == 1 ? "1 App Store update" : "\(store) App Store updates") }
        return parts
    }

    static func duration(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
    }

    private var checkedText: String {
        guard let checkedAt else { return "just now" }
        if Date().timeIntervalSince(checkedAt) < 60 { return "just now" }
        return RelativeDateTimeFormatter().localizedString(for: checkedAt, relativeTo: Date())
    }
}

// MARK: - Orb

/// The centre of the window: a glass disc inside a progress ring. Its contents follow the phase.
struct HeroOrb: View {
    @ObservedObject var model: RunModel
    var size: CGFloat = 212

    var body: some View {
        ZStack {
            // A soft glow in the tone colour gives the disc depth.
            Circle()
                .fill(model.tone.accent.opacity(0.35))
                .frame(width: size * 0.7, height: size * 0.7)
                .blur(radius: size * 0.17)

            Circle()
                .stroke(.primary.opacity(0.07), lineWidth: 7)

            ring

            Color.clear
                .frame(width: size - size * 0.19, height: size - size * 0.19)
                .glassEffect(.regular.tint(model.tone.accent.opacity(0.16)), in: .circle)

            center
                .id(model.phase)
                .transition(.blurReplace)
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.5), value: model.phase)
        .animation(.smooth(duration: 0.6), value: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.headline)
        .accessibilityValue(model.subline)
    }

    @ViewBuilder private var ring: some View {
        switch model.phase {
        case .checking:
            SpinningArc(color: model.tone.accent)
        case .running, .finished:
            Circle()
                .trim(from: 0, to: max(model.progress, 0.001))
                .stroke(
                    AngularGradient(colors: [model.tone.accent.opacity(0.55), model.tone.accent],
                                    center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.8), value: model.progress)
        case .ready:
            Circle().stroke(model.tone.accent.opacity(model.actionable.isEmpty ? 0.5 : 0.3), lineWidth: 7)
        case .failed:
            Circle().stroke(Palette.amber.opacity(0.6), lineWidth: 7)
        }
    }

    @ViewBuilder private var center: some View {
        switch model.phase {
        case .checking:
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.25, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
        case .ready:
            if model.actionable.isEmpty {
                Glyph(name: "checkmark", color: Palette.mint, size: size)
            } else {
                Numeral(value: model.actionable.count, caption: model.actionable.count == 1 ? "update" : "updates", size: size)
            }
        case .running:
            if model.actionable.isEmpty {
                Numeral(value: Int(model.progress * 100), caption: "percent", size: size)
            } else {
                Numeral(value: model.settledCount, caption: "of \(model.actionable.count)", size: size)
            }
        case .finished:
            if model.stopped {
                Glyph(name: "pause", color: Palette.amber, size: size)
            } else if model.tone == .attention {
                Glyph(name: "exclamationmark", color: Palette.amber, size: size)
            } else {
                Glyph(name: "checkmark", color: Palette.mint, size: size)
            }
        case .failed:
            Glyph(name: "wifi.exclamationmark", color: Palette.amber, size: size)
        }
    }
}

private struct Numeral: View {
    let value: Int
    let caption: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .animation(.smooth, value: value)
            Text(caption.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Glyph: View {
    let name: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.30, weight: .medium))
            .foregroundStyle(color.gradient)
            .symbolEffect(.bounce, options: .nonRepeating)
    }
}

/// A short arc that circles the orb while the check runs.
private struct SpinningArc: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(
                    AngularGradient(colors: [color.opacity(0), color], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(100)),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees((t * 220).truncatingRemainder(dividingBy: 360)))
        }
    }
}

// MARK: - Headline and steps

struct HeadlineBlock: View {
    @ObservedObject var model: RunModel

    var body: some View {
        VStack(spacing: 8) {
            Text(model.headline)
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            Text(model.subline)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .contentTransition(.opacity)
        }
        .animation(.smooth, value: model.headline)
        .animation(.smooth, value: model.subline)
        .frame(maxWidth: 520)
    }
}

/// Six short bars, one per step of the run.
struct StepStrip: View {
    @ObservedObject var model: RunModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(model.steps) { step in
                    StepPill(status: step.status, tint: model.tone.accent)
                        .help(step.title)
                }
            }
            Text(model.runningStep?.title ?? " ")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .contentTransition(.opacity)
                .animation(.smooth, value: model.runningStep?.title)
        }
        .accessibilityHidden(true)
    }
}

private struct StepPill: View {
    let status: StepStatus
    let tint: Color

    var body: some View {
        Capsule()
            .fill(fill)
            .frame(width: 38, height: 5)
            .phaseAnimator(status == .running ? [0.45, 1.0] : [1.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.8) }
            .animation(.smooth, value: status)
    }

    private var fill: Color {
        switch status {
        case .pending: return .primary.opacity(0.12)
        case .running: return tint
        case .done: return tint.opacity(0.85)
        case .skipped: return tint.opacity(0.35)
        case .failed: return Palette.red
        }
    }
}
