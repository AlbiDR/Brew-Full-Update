import AppKit
import SwiftUI

@main
struct BrewFullUpdateApp: App {
    @StateObject private var model: RunModel
    @StateObject private var adopt: AdoptModel

    init() {
        // `--demo <state>` shows a fixed state for screenshots and never runs the script.
        let args = CommandLine.arguments
        var demo: String?
        if let i = args.firstIndex(of: "--demo"), i + 1 < args.count { demo = args[i + 1] }
        // Adopt states sit on top of an ordinary "ready" window.
        let adoptDemo = demo?.hasPrefix("adopt") == true ? demo : nil
        _model = StateObject(wrappedValue: RunModel(demo: adoptDemo == nil ? demo : "ready"))
        _adopt = StateObject(wrappedValue: AdoptModel(demo: adoptDemo))
        // `-BFUAppearance dark|light` forces the appearance, for screenshots.
        switch UserDefaults.standard.string(forKey: "BFUAppearance") {
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    var body: some Scene {
        WindowGroup("Brew Command Center") {
            RootView(model: model, adopt: adopt)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 800)
        .commands {
            CommandMenu("Update") {
                Button("Install Updates") { model.update() }
                    .keyboardShortcut("u", modifiers: .command)
                    .disabled(model.phase != .ready || model.actionable.isEmpty)
                Button("Check Again") { model.check() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.phase == .checking || model.phase == .running)
                Button("Stop") { model.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(model.phase != .checking && model.phase != .running)
                Divider()
                Button("Adopt Apps and Taps…") { adopt.showing = true }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Exclusions…") { model.showExclusions = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Show Log") { model.showLog = true }
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
    }
}
