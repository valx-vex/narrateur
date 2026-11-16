import Foundation

public struct BookDocument: Equatable, Sendable {
    public let configURL: URL
    public let spec: BookSpec
    public let chapters: [Chapter]
    public let originalText: String
    public var folder: URL { configURL.deletingLastPathComponent() }
    public var sourceURL: URL { resolvePath(spec.source, relativeTo: folder) }
    public var coverURL: URL? { spec.cover.map { resolvePath($0, relativeTo: folder) } }
    public var outputURL: URL {
        let title = spec.title.replacingOccurrences(of: "[/:]", with: "-", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.appendingPathComponent("audio").appendingPathComponent((title.isEmpty ? "book" : title) + ".m4b")
    }
}
public enum BookWorkspace {
    public static func load(_ configURL: URL) throws -> BookDocument {
        let url = configURL.standardizedFileURL
        let text = try String(contentsOf: url, encoding: .utf8)
        let spec = try BookTOML.parse(text)
        let source = resolvePath(spec.source, relativeTo: url.deletingLastPathComponent())
        let markdown = try String(contentsOf: source, encoding: .utf8)
        return try BookDocument(configURL: url, spec: spec, chapters: ChapterIndex.parse(markdown, heading: spec.chapterHeading), originalText: text)
    }
    public static func prepare(input: URL, voice: Voice?, author: String) throws -> BookDocument {
        if input.pathExtension.lowercased() == "toml" { return try load(input) }
        guard input.pathExtension.lowercased() == "md" else { throw NarrateurError("Choose a Markdown book (.md) or book.toml.") }
        let folder = input.deletingPathExtension().appendingPathExtension("audiobook")
        let config = folder.appendingPathComponent("book.toml")
        if FileManager.default.fileExists(atPath: config.path) { return try load(config) }
        // Books set up by hand often keep their settings in a sibling audiobook/ folder. Reuse only an exact
        // source match, leaving both settings and cached audio in their original place.
        let legacy = input.deletingLastPathComponent().appendingPathComponent("audiobook/book.toml")
        if let existing = try? load(legacy),
           existing.sourceURL.resolvingSymlinksInPath() == input.standardizedFileURL.resolvingSymlinksInPath() {
            return existing
        }
        guard let voice else { throw NarrateurError("Add a voice in Settings before preparing a new book.") }
        let markdown = try String(contentsOf: input, encoding: .utf8)
        _ = try ChapterIndex.parse(markdown)
        let settings = try voice.engineVoice()
        let cover = [input.deletingPathExtension().appendingPathExtension("png"), input.deletingLastPathComponent().appendingPathComponent("cover.png")].first { FileManager.default.fileExists(atPath: $0.path) }
        let spec = BookSpec(title: ChapterIndex.title(markdown, fallback: input.deletingPathExtension().lastPathComponent), author: author, language: voice.language, source: "../" + input.lastPathComponent, cover: cover.map { "../" + $0.lastPathComponent }, voice: settings)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(BookTOML.encode(spec).utf8).write(to: config, options: .withoutOverwriting)
        return try load(config)
    }
    /// The book's narrator becomes this voice. A book takes its language from the voice it was made with: when the
    /// engine refuses the book's language, the new narrator's language takes its place. A language the engine reads
    /// stays as the book has it.
    public static func updateVoice(_ voice: Voice, in book: BookDocument) throws -> BookDocument {
        try updateVoice(voice.engineVoice(), language: voice.language, in: book)
    }
    public static func updateVoice(_ voice: VoiceSettings, language: String? = nil, in book: BookDocument) throws -> BookDocument {
        try voice.validate()
        let repairedLanguage = language.flatMap { language in
            EngineRules.languageProblem(book.spec.language, for: voice) != nil && EngineRules.languageProblem(language, for: voice) == nil ? language : nil
        }
        // Choosing the narrator the book already has must not touch book.toml: every cached clip is keyed on it.
        if repairedLanguage == nil, VoiceSelection.equivalent(voice, to: book.spec.voice, folder: book.folder) { return book }
        let doc = try TOMLDocument(book.originalText)
        guard let section = doc.sections.firstIndex(where: { $0.name == "voice" }) else { throw NarrateurError("Missing [voice] table.") }
        let start = doc.sections[section].line
        // Replace only the voice header and assignments; preserve trailing comments/whitespace before the next table.
        let end = doc.entries.filter { $0.section == "voice" }.map(\.lines.upperBound).max() ?? start + 1
        var lines = doc.lines
        lines.replaceSubrange(start..<end, with: BookTOML.voiceSection(voice).dropLast().components(separatedBy: "\n"))
        // The language is a top-level key, written before any table: replacing it after the voice moves nothing above it.
        if let repairedLanguage, let entry = doc.entries.first(where: { $0.section.isEmpty && $0.key == "language" }), entry.lines.upperBound <= start {
            lines.replaceSubrange(entry.lines, with: ["language = \(BookTOML.quote(repairedLanguage))"])
        }
        return try write(lines.joined(separator: "\n"), replacing: book)
    }
    public static func updateMetadata(title: String, author: String, in book: BookDocument) throws -> BookDocument {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NarrateurError("Title and author cannot be empty.") }
        let doc = try TOMLDocument(book.originalText)
        var lines = doc.lines
        for entry in doc.entries.filter({ $0.section.isEmpty && ["title", "author"].contains($0.key) }).sorted(by: { $0.lines.lowerBound > $1.lines.lowerBound }) {
            lines.replaceSubrange(entry.lines, with: ["\(entry.key) = \(BookTOML.quote(entry.key == "title" ? title : author))"])
        }
        return try write(lines.joined(separator: "\n"), replacing: book)
    }
    private static func write(_ text: String, replacing book: BookDocument) throws -> BookDocument {
        guard try String(contentsOf: book.configURL, encoding: .utf8) == book.originalText else { throw NarrateurError("book.toml changed outside Narrateur. Choose the book again before editing.") }
        _ = try BookTOML.parse(text)
        try text.write(to: book.configURL, atomically: true, encoding: .utf8)
        return try load(book.configURL)
    }
}
