import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: RunModel
    @ObservedObject var adopt: AdoptModel

    private var showsQueue: Bool {
        !(model.actionable + model.issues + model.manual).isEmpty && model.phase != .checking
    }

    var body: some View {
        ZStack {
            Backdrop(tone: model.tone)

            VStack(spacing: 0) {
                TopBar(model: model, adopt: adopt)

                Spacer(minLength: 8)

                VStack(spacing: showsQueue ? 20 : 28) {
                    HeroOrb(model: model, size: showsQueue ? 156 : 212)
                    HeadlineBlock(model: model)
                    if model.phase != .ready {
                        StepStrip(model: model)
                            .transition(.opacity)
                    }
                    if showsQueue {
                        QueueCard(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 32)
                .animation(.smooth(duration: 0.6), value: showsQueue)

                Spacer(minLength: 8)

                Dock(model: model)
                    .padding(.bottom, 30)
                    .padding(.top, 12)
            }
        }
        .frame(minWidth: 680, minHeight: 760)
        .background(WindowConfigurator())
        .sheet(isPresented: $model.showExclusions) {
            ExclusionsSheet(model: model)
        }
        .sheet(isPresented: $model.showLog) {
            LogSheet(lines: model.log)
        }
        .sheet(isPresented: $adopt.showing) {
            AdoptSheet(model: adopt)
        }
        .onAppear {
            model.launch()
            adopt.scan()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stop()
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var model: RunModel
    @ObservedObject var adopt: AdoptModel

    var body: some View {
        HStack {
            Spacer()
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    IconButton(symbol: "plus.app", label: "Adopt apps and taps", badge: adopt.readyCount) {
                        adopt.showing = true
                    }
                    IconButton(symbol: "nosign", label: "Exclusions", badge: model.excluded.count) {
                        model.showExclusions = true
                    }
                    IconButton(symbol: "text.alignleft", label: "Log", badge: 0) {
                        model.showLog = true
                    }
                }
            }
        }
        .padding(.top, 14)
        .padding(.trailing, 18)
        .overlay(alignment: .top) {
            Text("Brew Command Center")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 22)
                .allowsHitTesting(false)
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let label: String
    let badge: Int
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help(label)
            .accessibilityLabel(label)

            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(Palette.blue, in: .capsule)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .offset(x: 6, y: -5)
                    .allowsHitTesting(false)
                    .zIndex(1)
            }
        }
    }
}

// MARK: - Dock

/// The window's actions, as one group of glass buttons that reshapes itself with the phase.
private struct Dock: View {
    @ObservedObject var model: RunModel
    @Namespace private var glass

    private var updateTitle: String {
        let n = model.actionable.count
        return n == 1 ? "Install 1 Update" : "Install \(n) Updates"
    }

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                switch model.phase {
                case .checking:
                    secondary("Stop", id: "secondary") { model.stop() }
                case .ready:
                    secondary("Check Again", id: "secondary") { model.check() }
                    if !model.actionable.isEmpty {
                        primary(updateTitle, id: "primary") { model.update() }
                    }
                case .running:
                    secondary("Stop", id: "secondary") { model.stop() }
                case .finished:
                    secondary("Show Log", id: "secondary") { model.showLog = true }
                    primary("Check Again", id: "primary") { model.check() }
                case .failed:
                    primary("Try Again", id: "primary") { model.check() }
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: model.phase)
    }

    private func secondary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.glass)
            .controlSize(.extraLarge)
            .frame(minWidth: 120)
            .glassEffectID(id, in: glass)
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .tint(model.tone.accent)
            .frame(minWidth: 160)
            .glassEffectID(id, in: glass)
            .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Log

struct LogSheet: View {
    let lines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Log")
                .font(.system(size: 26, weight: .semibold))

            ScrollView {
                Text(lines.isEmpty ? "Nothing logged yet." : lines.suffix(600).joined(separator: "\n"))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(lines.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .glassCard(cornerRadius: 20)

            HStack(spacing: 10) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                }
                .disabled(lines.isEmpty)
                Button("Open Log File") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/brew-full-update.log"))
                }
                .buttonStyle(.glass)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 700, height: 500)
    }
}

// MARK: - Window

/// Lets the whole window background drag the window, which the hidden title bar otherwise takes away.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Demo screenshots are taken at full Retina quality, so they open on a Retina display.
            if CommandLine.arguments.contains("--demo"),
               let screen = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) {
                window.setFrameTopLeftPoint(NSPoint(x: screen.frame.minX + 160, y: screen.frame.maxY - 120))
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
