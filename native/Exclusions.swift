import Foundation

/// The saved exclusions list: where it lives and how names are read, added and removed.
/// Follows the same rules as brew_full_update.zsh, so the app and the script share one file.
enum Exclusions {
    static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Brew Full Update", isDirectory: true)

    static var defaultFile: URL {
        supportDir.appendingPathComponent("exclusions.txt")
    }

    private static var locationFile: URL {
        supportDir.appendingPathComponent("exclusions-location.txt")
    }

    /// The file in use: the path saved by the location picker, else the default file.
    static var currentFile: URL {
        guard let text = try? String(contentsOf: locationFile, encoding: .utf8),
              let first = text.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces),
              !first.isEmpty else { return defaultFile }
        return URL(fileURLWithPath: first)
    }

    /// The cask name on one line, or nil for blank lines and comments.
    static func name(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        return trimmed.components(separatedBy: .whitespaces).first
    }

    static func names() -> [String] {
        guard let text = try? String(contentsOf: currentFile, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").compactMap(name(in:))
    }

    /// Lowercase, without spaces, as the script expects cask tokens.
    static func normalize(_ input: String) -> String {
        input.filter { !$0.isWhitespace }.lowercased()
    }

    static func isValid(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9][a-z0-9@._+-]*$"#, options: .regularExpression) != nil
    }

    static func add(_ name: String) throws {
        guard !names().contains(name) else { return }
        let file = currentFile
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += name + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Removes the name from the list. Comments and other lines are kept as they are.
    static func remove(_ name: String) throws {
        let file = currentFile
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let kept = text.components(separatedBy: "\n").filter { Exclusions.name(in: $0) != name }
        try kept.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Saves a new location. A nil URL, or the default file, clears the saved location.
    /// A missing file is created empty; an existing file is used as it is.
    static func setLocation(_ url: URL?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        guard let url, url.standardizedFileURL != defaultFile.standardizedFileURL else {
            if fm.fileExists(atPath: locationFile.path) { try fm.removeItem(at: locationFile) }
            return
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            try "".write(to: url, atomically: true, encoding: .utf8)
        }
        try (url.path + "\n").write(to: locationFile, atomically: true, encoding: .utf8)
    }
}
