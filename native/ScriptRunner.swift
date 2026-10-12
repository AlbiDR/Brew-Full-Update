import Foundation

/// Runs brew_full_update.zsh in a non-interactive shell with the progress feed on, and hands back
/// its output line by line on the main thread. Used by the update window and the Adopt screen.
final class ScriptRunner {
    private var process: Process?
    private var partial = ""

    var isRunning: Bool { process != nil }

    /// Starts the script with the given arguments. Returns an error message if it could not start.
    @discardableResult
    func start(arguments: [String], onLine: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) -> String? {
        guard process == nil else { return "The script is already running." }
        guard let script = Bundle.main.url(forResource: "brew_full_update", withExtension: "zsh") else {
            return "The update script is missing from the app."
        }

        var env = ProcessInfo.processInfo.environment
        env["BFU_EVENTS"] = "1"
        env["NO_COLOR"] = "1"
        if let askpass = ScriptRunner.writeAskpass() { env["SUDO_ASKPASS"] = askpass.path }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "source \"$1\"; shift; brew_full_update \"$@\"", "zsh", script.path] + arguments
        p.environment = env
        p.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        partial = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text, onLine) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                self.consume(rest, onLine)
                if !self.partial.isEmpty {
                    onLine(self.partial)
                    self.partial = ""
                }
                self.process = nil
                onExit(code)
            }
        }

        do {
            try p.run()
            process = p
            return nil
        } catch {
            return "Could not start: \(error.localizedDescription)"
        }
    }

    /// Asks the script to stop. Its own trap cleans up the sudo session on the way out.
    func stop() {
        process?.terminate()
    }

    private func consume(_ text: String, _ onLine: (String) -> Void) {
        partial += text
        var lines = partial.components(separatedBy: "\n")
        partial = lines.removeLast()
        lines.forEach(onLine)
    }

    /// A small askpass helper for sudo, so the admin password prompt is a native dialog.
    /// Written on each run so it always matches the app.
    static func writeAskpass() -> URL? {
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
}
