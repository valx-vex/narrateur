import Foundation

public struct NarrateurError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public enum VoiceModel: String, Codable, Sendable { case base, customvoice, voicedesign }
public struct VoiceSettings: Equatable, Sendable {
    public var model: VoiceModel
    public var modelID: String?
    public var voice: String?
    public var instruct: String?
    public var refAudio: String?
    public var refText: String?
    public init(model: VoiceModel, modelID: String? = nil, voice: String? = nil, instruct: String? = nil, refAudio: String? = nil, refText: String? = nil) {
        self.model = model; self.modelID = modelID; self.voice = voice; self.instruct = instruct; self.refAudio = refAudio; self.refText = refText
    }
    public func validate() throws {
        func present(_ value: String?) -> Bool { !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch model {
        case .base: guard present(refAudio), present(refText) else { throw NarrateurError("This voice needs a readable reference and transcript.") }
        case .customvoice: guard present(voice) else { throw NarrateurError("Choose a preset speaker for this voice.") }
        case .voicedesign: guard present(instruct) else { throw NarrateurError("This voice needs a description.") }
        }
    }
}
public struct BookSpec: Equatable, Sendable {
    public var title: String
    public var author: String
    public var language: String
    public var source: String
    public var cover: String?
    public var chapterHeading: String
    public var voice: VoiceSettings
    public var pauses: [String: Double]
    public init(title: String, author: String, language: String, source: String, cover: String? = nil, chapterHeading: String = "# Chapter ", voice: VoiceSettings, pauses: [String: Double] = ["sentence": 0.15, "paragraph": 0.45, "section": 1]) {
        self.title = title; self.author = author; self.language = language; self.source = source; self.cover = cover; self.chapterHeading = chapterHeading; self.voice = voice; self.pauses = pauses
    }
}
public enum BookTOML {
    public static func parse(_ text: String) throws -> BookSpec {
        let doc = try TOMLDocument(text)
        func required(_ key: String) throws -> String {
            guard let value = doc.string(key), !value.isEmpty else { throw NarrateurError("book.toml needs a \(key).") }; return value
        }
        guard let model = doc.string("model", in: "voice").flatMap(VoiceModel.init) else { throw NarrateurError("Unknown or missing voice model in book.toml.") }
        let voice = VoiceSettings(model: model, modelID: doc.string("model_id", in: "voice"), voice: doc.string("voice", in: "voice"), instruct: doc.string("instruct", in: "voice"), refAudio: doc.string("ref_audio", in: "voice"), refText: doc.string("ref_text", in: "voice"))
        try voice.validate()
        let heading = doc.string("chapter_heading") ?? "# Chapter "
        guard !heading.isEmpty else { throw NarrateurError("The chapter heading cannot be empty.") }
        var pauses = ["sentence": 0.15, "paragraph": 0.45, "section": 1.0]
        for key in pauses.keys {
            if let value = doc.raw(key, in: "pauses") {
                guard let number = Double(value), number.isFinite, number >= 0 else { throw NarrateurError("Invalid pause: \(key).") }
                pauses[key] = number
            }
        }
        return try BookSpec(title: required("title"), author: required("author"), language: required("language"), source: required("source"), cover: doc.string("cover"), chapterHeading: heading, voice: voice, pauses: pauses)
    }
    public static func quote(_ text: String) -> String {
        // JSON basic string escapes are valid TOML basic string escapes.
        String(data: try! JSONEncoder().encode(text), encoding: .utf8)!.replacingOccurrences(of: "\\/", with: "/")
    }
    public static func voiceSection(_ voice: VoiceSettings) -> String {
        var lines = ["[voice]", "model = \(quote(voice.model.rawValue))"]
        for (key, value) in [("model_id", voice.modelID), ("voice", voice.voice), ("instruct", voice.instruct), ("ref_audio", voice.refAudio), ("ref_text", voice.refText)] {
            if let value { lines.append("\(key) = \(quote(value))") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
    public static func encode(_ book: BookSpec) -> String {
        var lines = [("title", book.title), ("author", book.author), ("language", book.language), ("source", book.source), ("chapter_heading", book.chapterHeading)].map { "\($0.0) = \(quote($0.1))" }
        if let cover = book.cover { lines.append("cover = \(quote(cover))") }
        lines += ["", voiceSection(book.voice), "[pauses]"]
        lines += ["sentence", "paragraph", "section"].map { "\($0) = \(book.pauses[$0]!)" }
        return lines.joined(separator: "\n") + "\n"
    }
}
