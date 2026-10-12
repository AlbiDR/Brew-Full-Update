import AppKit
import SwiftUI

/// A value a view owns. Stands in for @State, whose macro needs the full Xcode toolchain.
final class Box<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

/// Casks the update leaves alone, and where that list is saved.
struct ExclusionsSheet: View {
    @ObservedObject var model: RunModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var newName = Box("")
    @StateObject private var message = Box<String?>(nil)
    @StateObject private var location = Box(Exclusions.currentFile.path)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            list
            addRow
            locationCard

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
        .onAppear { model.reloadExclusions() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Exclusions")
                .font(.system(size: 26, weight: .semibold))
            Text("These apps are never updated. A name also skips any cask that starts with it, so topaz covers topaz-photo.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if model.excluded.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "nosign")
                        .foregroundStyle(.tertiary)
                    Text("Nothing is excluded")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                ForEach(Array(model.excluded.enumerated()), id: \.element) { index, name in
                    HStack {
                        Text(name)
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Button {
                            remove(name)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Stop excluding \(name)")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    if index < model.excluded.count - 1 {
                        Divider().padding(.leading, 16).opacity(0.5)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .glassCard(cornerRadius: 20)
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Cask name, for example topaz-photo", text: $newName.value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .onSubmit { add() }
                Button("Add") { add() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(Exclusions.normalize(newName.value).isEmpty)
            }
            if let text = message.value {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.red)
                    .padding(.leading, 6)
            }
        }
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SAVED IN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(location.value)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button("Choose…") { chooseLocation() }
                Button("Use Default Location") { useDefault() }
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    // MARK: Actions

    private func add() {
        let name = Exclusions.normalize(newName.value)
        guard !name.isEmpty else { return }
        guard Exclusions.isValid(name) else {
            message.value = "Use lowercase letters, numbers and hyphens, for example topaz-photo."
            return
        }
        do {
            try Exclusions.add(name)
            newName.value = ""
            message.value = nil
            model.reloadExclusions()
        } catch {
            message.value = error.localizedDescription
        }
    }

    private func remove(_ name: String) {
        do {
            try Exclusions.remove(name)
            message.value = nil
            model.reloadExclusions()
        } catch {
            message.value = error.localizedDescription
        }
    }

    private func chooseLocation() {
        let panel = NSSavePanel()
        panel.message = "Choose the exclusions file, or type a new name to create one."
        panel.prompt = "Use This File"
        panel.nameFieldStringValue = "exclusions.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply { try Exclusions.setLocation(url) }
    }

    private func useDefault() {
        apply { try Exclusions.setLocation(nil) }
    }

    private func apply(_ change: () throws -> Void) {
        do {
            try change()
            location.value = Exclusions.currentFile.path
            message.value = nil
            model.reloadExclusions()
        } catch {
            message.value = error.localizedDescription
        }
    }
}
