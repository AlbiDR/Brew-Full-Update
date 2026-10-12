import AppKit
import SwiftUI

/// Review apps and taps Homebrew could take over, tick the ones you want, and adopt them.
struct AdoptSheet: View {
    @ObservedObject var model: AdoptModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var newTap = Box("")
    @StateObject private var showUnmatched = Box(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            content
            footer
        }
        .padding(28)
        .frame(width: 600, height: 700)
        .onAppear { if model.phase == .idle { model.scan() } }
    }

    // MARK: Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adopt")
                .font(.system(size: 26, weight: .semibold))
            Text("Apps you installed by hand, and taps that went missing. Homebrew can manage them and keep them updated. Nothing is adopted until you choose it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let message = model.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(model.failedCount > 0 ? Palette.amber : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            switch model.phase {
            case .applying:
                Button("Stop") { model.stop() }
                    .buttonStyle(.glass)
            case .scanning:
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
            case .done, .failed:
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
                Button("Scan Again") { model.scan() }
                    .buttonStyle(.glassProminent)
            default:
                Button("Scan Again") { model.scan() }
                    .buttonStyle(.glass)
                Button(model.selectedCount == 0 ? "Adopt" : "Adopt \(model.selectedCount)") {
                    model.applySelected()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedCount == 0)
            }
        }
        .controlSize(.large)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .scanning:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Looking for apps Homebrew could manage")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundStyle(Palette.amber)
                Text(model.message ?? "Something went wrong.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .applying, .done:
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.candidates.isEmpty && model.taps.isEmpty {
                        nothingToAdopt
                    }
                    if !model.adoptable.isEmpty {
                        section("Ready to adopt") {
                            ForEach(model.adoptable) { AppRow(item: $0, model: model) }
                        }
                    }
                    if !model.needsUpdate.isEmpty {
                        section("Update these first") {
                            ForEach(model.needsUpdate) { AppRow(item: $0, model: model) }
                        }
                    }
                    if !model.taps.isEmpty {
                        section("Taps to add back", note: "Installed packages came from these, but Homebrew can no longer update them.") {
                            ForEach(model.taps) { TapRow(item: $0, model: model) }
                        }
                    }
                    addTapField
                    if !model.unmatched.isEmpty { unmatchedList }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            // A soft fade, so a long list ends gracefully instead of being cut mid-line.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22)
                }
            }
        }
    }

    private var nothingToAdopt: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26))
                .foregroundStyle(Palette.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing to adopt").font(.system(size: 14, weight: .semibold))
                Text("Every app that has a cask is already managed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private func section<Content: View>(_ title: String, note: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .padding(.vertical, 4)
                .glassCard(cornerRadius: 20)
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var addTapField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD A TAP")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            HStack(spacing: 10) {
                TextField("user/repo, for example adamorad/tap", text: $newTap.value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .onSubmit { addTypedTap() }
                Button("Add") { addTypedTap() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(!AdoptModel.isValidTap(newTap.value.trimmingCharacters(in: .whitespaces))
                              || model.phase == .applying)
            }
            Text("Tapping a repository can reveal casks for apps that had none. It is scanned again afterwards.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    private var unmatchedList: some View {
        DisclosureGroup(isExpanded: $showUnmatched.value) {
            Text(model.unmatched.map(\.name).joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text("No cask found for \(model.unmatched.count) apps")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private func addTypedTap() {
        let name = newTap.value
        guard AdoptModel.isValidTap(name.trimmingCharacters(in: .whitespaces)) else { return }
        newTap.value = ""
        model.addTap(name)
    }
}

// MARK: - Rows

private struct AppRow: View {
    let item: AdoptCandidate
    @ObservedObject var model: AdoptModel

    private var detail: String {
        switch item.status {
        case "match": return "\(item.installed)  ·  matches Homebrew"
        case "latest": return "\(item.installed)  ·  Homebrew follows the latest version"
        case "newer": return "\(item.installed)  ·  newer than Homebrew's \(item.caskVersion)"
        case "older": return "\(item.installed)  ·  Homebrew has \(item.caskVersion), so update the app first"
        default: return item.installed
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CheckButton(on: item.selected && item.canAdopt, enabled: item.canAdopt && model.phase == .ready) {
                model.toggle(app: item.token)
            }
            AppIcon(path: item.path)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.app)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(item.tap == "homebrew/cask" ? item.token : "\(item.tap)/\(item.token)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if item.state == .failed, let reason = item.reason {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            StateMark(state: item.state, kind: .cask)
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .opacity(item.canAdopt ? 1 : 0.62)
    }
}

private struct TapRow: View {
    let item: OrphanTap
    @ObservedObject var model: AdoptModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CheckButton(on: item.selected, enabled: model.phase == .ready) {
                model.toggle(tap: item.name)
            }
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.violet)
                .frame(width: 34, height: 34)
                .background(Palette.violet.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Text(item.items.map { $0.replacingOccurrences(of: ":", with: " ") }.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if item.state == .failed, let reason = item.reason {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            StateMark(state: item.state, kind: .formula)
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct CheckButton: View {
    let on: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21))
                .foregroundStyle(on ? Palette.blue : Color.secondary.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .frame(width: 26, height: 34)
        .accessibilityLabel(on ? "Selected" : "Not selected")
    }
}

/// The app's own icon, so a row looks like the app it is about.
private struct AppIcon: View {
    let path: String?

    var body: some View {
        Group {
            if let path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
    }
}
