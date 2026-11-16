import Foundation
public struct EngineCommand: Equatable, Sendable {
    public let executable: URL
    public let prefixArguments: [String]
    public init(executable: URL, prefixArguments: [String] = []) { self.executable = executable; self.prefixArguments = prefixArguments }
    public var display: String { ([executable.path] + prefixArguments).joined(separator: " ") }
    public func environment(_ inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = inherited
        env.removeValue(forKey: "BOOK_AUDIO_BACKEND")
        let original = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + executable.deletingLastPathComponent().path + ":" + original
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }
}
public enum EngineLocator {
    /// Developer mode: `BOOK_AUDIO_PROJECT` names a book-audio checkout to run through `uv run`.
    public static func developerProject(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let value = environment["BOOK_AUDIO_PROJECT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return resolvePath(value, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    }
    /// Order: the user's own setting, `PATH`, `~/.local/bin` (where `uv tool install` puts it), then the developer project.
    public static func resolve(override: String = "", path: String = ProcessInfo.processInfo.environment["PATH"] ?? "", home: URL = FileManager.default.homeDirectoryForCurrentUser, project: URL? = developerProject()) throws -> EngineCommand {
        // `uv tool install` leaves a symbolic link in ~/.local/bin: what counts is the file the path leads to.
        func usable(_ url: URL) -> Bool { FileManager.default.isExecutableFile(atPath: url.path) && (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let paths = path.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) }
        if !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = resolvePath(override, relativeTo: home)
            guard usable(url) else { throw NarrateurError("The engine override is not an executable file: \(url.path)") }
            return EngineCommand(executable: url)
        }
        for dir in paths + [home.appendingPathComponent(".local/bin")] {
            let url = dir.appendingPathComponent("book-audio")
            if usable(url) { return EngineCommand(executable: url) }
        }
        if let project, FileManager.default.fileExists(atPath: project.appendingPathComponent("pyproject.toml").path) {
            for dir in paths + [home.appendingPathComponent(".local/bin"), URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")] {
                let uv = dir.appendingPathComponent("uv")
                if usable(uv) { return EngineCommand(executable: uv, prefixArguments: ["run", "--project", project.path, "book-audio"]) }
            }
        }
        throw NarrateurError(EngineSetup.notFound)
    }
}
