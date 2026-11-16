import Foundation
public enum RenderReadiness {
    public static func reason(hasBook: Bool, chapters: Int, voiceAvailable: Bool, engineAvailable: Bool, active: Bool) -> String? {
        if active { return "A job is already running." }
        if !hasBook { return "Choose a Markdown book to begin." }
        if chapters == 0 { return "No chapters found. Use headings such as # Chapter 1 — Title." }
        if !voiceAvailable { return "This narrator is unavailable. Choose another voice." }
        if !engineAvailable { return "The engine is not installed yet. Open \(EngineSetup.title) to add it." }
        return nil
    }
}
public struct AppPreferences: Codable, Equatable, Sendable {
    public var engineOverride = ""
    public var voicesFolder = AppPreferences.defaultVoicesFolder()
    public var author = AppPreferences.defaultAuthor()
    public var lastVoice: String?
    public init() {}
    /// A saved value always wins; a value that was never saved takes today's default.
    public init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        engineOverride = try saved.decodeIfPresent(String.self, forKey: .engineOverride) ?? ""
        voicesFolder = try saved.decodeIfPresent(String.self, forKey: .voicesFolder) ?? Self.defaultVoicesFolder()
        author = try saved.decodeIfPresent(String.self, forKey: .author) ?? Self.defaultAuthor()
        lastVoice = try saved.decodeIfPresent(String.self, forKey: .lastVoice)
    }
    public static func defaultVoicesFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        home.appendingPathComponent("Library/Application Support/Narrateur/Voices").path
    }
    /// The full name of the macOS account, then its short name. Never empty: book.toml needs an author.
    public static func defaultAuthor(fullName: String = NSFullUserName(), userName: String = NSUserName()) -> String {
        [fullName, userName].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "Anonymous"
    }
}
/// The folder the voices are read from, for what the "Voices folder" field of the settings holds.
public struct VoicesFolder: Equatable, Sendable {
    public let url: URL
    /// One line for the settings when the field could not be used, nil when it was.
    public let note: String?
    public init(url: URL, note: String?) { self.url = url; self.note = note }
    /// A folder that exists is used as it is. An empty field, a path that does not start at the top of the disk
    /// or at the home folder, or a path that is not an existing folder, falls back to Narrateur's own folder:
    /// never the folder the app was started from, and a mistyped path is never created.
    /// Narrateur's own folder is the only one it creates. The field itself is left as it was typed.
    /// A voice's own folder (a voice.toml, and no voice inside), easy to pick in the Choose… panel, which opens among
    /// the voices, sends to the folder that holds it: the starter voices are never written into a voice.
    public static func resolve(_ field: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> VoicesFolder {
        let own = URL(fileURLWithPath: AppPreferences.defaultVoicesFolder(home: home), isDirectory: true)
        func fallback(_ reason: String) -> VoicesFolder { VoicesFolder(url: own, note: "\(reason) Narrateur is using its own voices folder: \(own.path)") }
        var path = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return fallback("No voices folder is set.") }
        if path == "~" { path = home.path } else if path.hasPrefix("~/") { path = home.appendingPathComponent(String(path.dropFirst(2))).path }
        guard path.hasPrefix("/") else { return fallback("“\(path)” is not a full path.") }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        if url.path == own.standardizedFileURL.path { return VoicesFolder(url: own, note: nil) }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return fallback("“\(url.path)” is not an existing folder.") }
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("voice.toml").path), VoiceLibrary.load(from: url).isEmpty {
            let holder = url.deletingLastPathComponent()
            return VoicesFolder(url: holder, note: "“\(url.path)” is a voice: it holds a voice.toml. Narrateur is using the folder that holds it: \(holder.path)")
        }
        return VoicesFolder(url: url, note: nil)
    }
}
public enum VoiceSelection {
    public static func match(_ settings: VoiceSettings, folder: URL, voices: [Voice]) -> Voice? {
        voices.first { voice in
            guard let other = try? voice.engineVoice() else { return false }
            return equivalent(other, to: settings, folder: folder)
        }
    }
    /// True when `candidate` (an engine voice from the library) is the voice `current` (a book's settings, relative to `folder`) already names.
    /// Older books keep their cloned reference inside the book folder: the same bytes and the same trimmed transcript count as the same voice.
    public static func equivalent(_ candidate: VoiceSettings, to current: VoiceSettings, folder: URL) -> Bool {
        var canonical = current
        if let path = canonical.refAudio { canonical.refAudio = resolvePath(path, relativeTo: folder).path }
        if candidate == canonical { return true }
        guard canonical.model == .base, candidate.model == .base,
              let reference = canonical.refAudio, let libraryReference = candidate.refAudio,
              canonical.refText?.trimmingCharacters(in: .whitespacesAndNewlines) == candidate.refText?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        var comparable = canonical
        comparable.refAudio = candidate.refAudio; comparable.refText = candidate.refText
        return comparable == candidate && FileManager.default.contentsEqual(atPath: reference, andPath: libraryReference)
    }
    public static func available(_ settings: VoiceSettings, folder: URL) -> Bool {
        guard (try? settings.validate()) != nil else { return false }
        if settings.model == .base {
            guard let path = settings.refAudio else { return false }
            return FileManager.default.isReadableFile(atPath: resolvePath(path, relativeTo: folder).path)
        }
        return true
    }
}
