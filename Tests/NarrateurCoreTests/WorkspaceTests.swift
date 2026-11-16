import Foundation
import Testing
@testable import NarrateurCore
struct WorkspaceTests {
    func voice(_ temp: TempFolder) throws -> Voice {
        try temp.write("voices/house/voice.toml", "name='House'\nowner='table'\nlanguage='English'\nmodel='customvoice'\nvoice='Ryan'")
        return try #require(VoiceLibrary.load(from: temp.url.appendingPathComponent("voices")).first)
    }
    @Test func prepareAndCoverPriority() throws {
        let temp = try TempFolder(), narrator = try voice(temp)
        let input = try temp.write("A book.md", "# Exact title — Fixture\n\n# Chapter 1 — Opening\nHello.")
        try temp.write("A book.png"); try temp.write("cover.png")
        let book = try BookWorkspace.prepare(input: input, voice: narrator, author: "Author")
        #expect(book.spec.title == "Exact title — Fixture")
        #expect(book.spec.source == "../A book.md")
        #expect(book.spec.cover == "../A book.png")
        #expect(book.chapters.count == 1)
        #expect(book.configURL.lastPathComponent == "book.toml")
    }
    @Test func fallbackCoverAndExistingBookNotOverwritten() throws {
        let temp = try TempFolder(), narrator = try voice(temp)
        let input = try temp.write("Book.md", "No title\n# Chapter 1 — Opening\nHello")
        try temp.write("cover.png")
        let doc = try BookWorkspace.prepare(input: input, voice: narrator, author: "Original")
        #expect(doc.spec.cover == "../cover.png")
        let before = try Data(contentsOf: doc.configURL)
        let again = try BookWorkspace.prepare(input: input, voice: nil, author: "Different")
        #expect(try Data(contentsOf: again.configURL) == before)
        #expect(again.spec.author == "Original")
    }
    @Test func voiceOnlyEditPreservesOtherSectionsVerbatim() throws {
        let temp = try TempFolder(), narrator = try voice(temp)
        let input = try temp.write("Book.md", "# A book\n# Chapter 1 — Opening")
        let doc = try BookWorkspace.prepare(input: input, voice: narrator, author: "Original")
        let suffix = "\n# Keep this casting\n[[casting]]\nname='sample'\nmodel='voicedesign'\ninstruct='Stay calm.'\n"
        var text = try String(contentsOf: doc.configURL, encoding: .utf8)
        text = text.replacingOccurrences(of: "sentence = 0.15", with: "sentence = 0.27 # custom pause") + suffix
        try text.write(to: doc.configURL, atomically: true, encoding: .utf8)
        let fresh = try BookWorkspace.load(doc.configURL)
        let updated = try BookWorkspace.updateVoice(VoiceSettings(model: .voicedesign, instruct: "Quiet voice"), in: fresh)
        let actual = try String(contentsOf: updated.configURL, encoding: .utf8)
        #expect(actual.hasSuffix(suffix))
        #expect(actual.contains("sentence = 0.27 # custom pause"))
        #expect(updated.spec.author == "Original")
        #expect(updated.spec.voice.model == .voicedesign)
    }
    @Test func metadataEditAndExternalChanges() throws {
        let temp = try TempFolder(), narrator = try voice(temp)
        let input = try temp.write("Book.md", "# Book\n# Chapter 1 — One")
        let doc = try BookWorkspace.prepare(input: input, voice: narrator, author: "A")
        let updated = try BookWorkspace.updateMetadata(title: "New title", author: "B", in: doc)
        #expect(updated.spec.title == "New title"); #expect(updated.spec.author == "B")
        #expect(throws: (any Error).self) { try BookWorkspace.updateMetadata(title: "Lost", author: "Lost", in: doc) }
    }
    @Test func missingSourceAndWrongExtensionFail() throws {
        let temp = try TempFolder()
        let config = try temp.write("book.toml", BookTOML.encode(BookSpec(title: "A", author: "B", language: "English", source: "missing.md", voice: VoiceSettings(model: .customvoice, voice: "Ryan"))))
        #expect(throws: (any Error).self) { try BookWorkspace.load(config) }
        let wrong = try temp.write("audio.mp3")
        #expect(throws: (any Error).self) { try BookWorkspace.prepare(input: wrong, voice: nil, author: "A") }
    }
    /// A book takes its language from the voice it was made with. When the engine refuses that language,
    /// choosing another narrator repairs the book; a language the engine reads is left as the book has it.
    @Test func choosingAnotherNarratorRepairsALanguageTheEngineRefuses() throws {
        let temp = try TempFolder()
        try temp.write("book/Book.md", "# Book\n# Chapter 1 — One")
        let spec = BookSpec(title: "Book", author: "A", language: "fr", source: "Book.md", voice: VoiceSettings(model: .customvoice, voice: "ryan"))
        let config = try temp.write("book/book.toml", BookTOML.encode(spec))
        try temp.write("voices/french/voice.toml", "name='French'\nowner='table'\nlanguage='French'\nmodel='voicedesign'\ndescription='Warm and calm.'")
        try temp.write("voices/english/voice.toml", "name='English'\nowner='table'\nlanguage='English'\nmodel='customvoice'\nvoice='serena'")
        let voices = VoiceLibrary.load(from: temp.url.appendingPathComponent("voices"))
        let french = try #require(voices.first { $0.id == "french" }), english = try #require(voices.first { $0.id == "english" })
        let repaired = try BookWorkspace.updateVoice(french, in: try BookWorkspace.load(config))
        #expect(repaired.spec.language == "French")
        #expect(repaired.spec.voice.model == .voicedesign)
        #expect(try String(contentsOf: config, encoding: .utf8).contains("\nlanguage = \"French\"\n"))
        // Now the book's language is one the engine reads: another narrator does not change it.
        let kept = try BookWorkspace.updateVoice(english, in: repaired)
        #expect(kept.spec.language == "French")
        #expect(kept.spec.voice.voice == "serena")
        // The same narrator the book already names still repairs a refused language.
        let refused = BookSpec(title: "Book", author: "A", language: "Français", source: "Book.md", voice: VoiceSettings(model: .customvoice, voice: "serena"))
        try BookTOML.encode(refused).write(to: config, atomically: true, encoding: .utf8)
        let same = try BookWorkspace.updateVoice(english, in: try BookWorkspace.load(config))
        #expect(same.spec.language == "English")
        #expect(same.spec.voice == refused.voice)
    }
    @Test func equivalentVoiceLeavesBookUntouched() throws {
        let temp = try TempFolder()
        try temp.write("library/house/voice.toml", "name='House'\nowner='table'\nlanguage='English'\nmodel='base'")
        try temp.write("library/house/reference.wav", "identical reference bytes")
        try temp.write("library/house/reference.txt", "A quiet voice.\n")
        let house = try #require(VoiceLibrary.load(from: temp.url.appendingPathComponent("library")).first)
        try temp.write("book/voice/narrator.wav", "identical reference bytes")
        try temp.write("book/Book.md", "# Book\n# Chapter 1 — One")
        // A book written by book-audio: relative cloned reference, aligned keys, no trailing newline in the transcript.
        let spec = BookSpec(title: "Book", author: "A", language: "English", source: "Book.md", cover: nil,
                            voice: VoiceSettings(model: .base, refAudio: "voice/narrator.wav", refText: "A quiet voice."))
        let text = BookTOML.encode(spec).replacingOccurrences(of: "model = \"base\"", with: "model    = \"base\"")
        let config = try temp.write("book/book.toml", text)
        let doc = try BookWorkspace.load(config)
        let same = try BookWorkspace.updateVoice(house.engineVoice(), in: doc)
        #expect(same.originalText == text)
        #expect(try String(contentsOf: config, encoding: .utf8) == text)
        let other = try BookWorkspace.updateVoice(VoiceSettings(model: .voicedesign, instruct: "Quiet voice"), in: doc)
        #expect(other.spec.voice.model == .voicedesign)
        #expect(try String(contentsOf: config, encoding: .utf8) != text)
    }
}
