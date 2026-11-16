import Foundation

public struct Voice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let owner: String
    public let language: String
    public let created: String
    public let description: String
    public let origin: String
    public let folder: URL
    public let settings: VoiceSettings?
    public let transcriptURL: URL?
    public let unavailableReason: String?
    public func engineVoice() throws -> VoiceSettings {
        if let unavailableReason { throw NarrateurError(unavailableReason) }
        guard var settings else { throw NarrateurError("This voice has no settings.") }
        if settings.model == .base {
            guard let path = settings.refAudio, FileManager.default.isReadableFile(atPath: path), let transcriptURL else { throw NarrateurError("Reference audio is missing or unreadable.") }
            settings.refText = try VoiceLibrary.transcript(transcriptURL)
        }
        try settings.validate(); return settings
    }
}
public enum VoiceLibrary {
    public static func load(from folder: URL) -> [Voice] {
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return children.compactMap { child in
            let manifest = child.appendingPathComponent("voice.toml")
            guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
            var name = child.lastPathComponent, owner = "", language = "", created = "", description = "", origin = ""
            var settings: VoiceSettings?, transcript: URL?, problem: String?
            do {
                let doc = try TOMLDocument(String(contentsOf: manifest, encoding: .utf8))
                name = doc.string("name") ?? name; owner = doc.string("owner") ?? ""; language = doc.string("language") ?? ""
                created = doc.string("created") ?? ""; description = doc.string("description") ?? ""; origin = doc.string("origin") ?? ""
                guard !name.isEmpty, !owner.isEmpty, !language.isEmpty, let model = doc.string("model").flatMap(VoiceModel.init) else { throw NarrateurError("voice.toml needs a name, owner, language and valid model.") }
                settings = VoiceSettings(model: model, modelID: doc.string("model_id"), voice: doc.string("voice"), instruct: description.isEmpty ? nil : description)
                if model == .base {
                    let reference = resolvePath(doc.string("reference") ?? "reference.wav", relativeTo: child)
                    transcript = resolvePath(doc.string("transcript") ?? "reference.txt", relativeTo: child)
                    if let reason = EngineRules.recordingProblem(reference) { throw NarrateurError(reason) }
                    settings?.refAudio = reference.path
                    settings?.refText = try VoiceLibrary.transcript(transcript!)
                    settings?.instruct = nil
                }
                try settings?.validate()
                // What the engine would refuse before it downloads anything is said here, next to the voice, in its words.
                if let settings, let reason = EngineRules.voiceProblem(settings) ?? EngineRules.languageProblem(language, for: settings) { throw NarrateurError(reason) }
            } catch { problem = error.localizedDescription }
            return Voice(id: child.lastPathComponent, name: name, owner: owner, language: language, created: created, description: description, origin: origin, folder: child, settings: settings, transcriptURL: transcript, unavailableReason: problem)
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
    /// The voices of `folder` as the disk holds them now, or nil when they are the ones already listed. It only reads
    /// a few small files, and writes nothing: cheap enough each time the app comes back to the front.
    public static func reload(_ listed: [Voice], from folder: URL) -> [Voice]? {
        let current = load(from: folder)
        return current == listed ? nil : current
    }
    /// Transcripts are compared and written verbatim by the engine; a trailing newline would silently change every cache key.
    static func transcript(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// The narrator on the card when no book is open: the one last chosen, then the one shown until now, then the
    /// first that can read; each only while it is listed and can read. Reading the folder again (back from the Finder,
    /// a voice added) never moves the card by itself, and an Apply back to a folder finds the narrator chosen there.
    public static func preferred(_ voices: [Voice], lastUsed: String?, shown: String? = nil) -> Voice? {
        func listed(_ id: String?) -> Voice? { voices.first { $0.id == id && $0.unavailableReason == nil } }
        return listed(lastUsed) ?? listed(shown) ?? voices.first { $0.unavailableReason == nil }
    }
}
public func resolvePath(_ path: String, relativeTo folder: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    return (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)).standardizedFileURL
}
