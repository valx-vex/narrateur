import Foundation
import Testing
@testable import NarrateurCore

struct LegacyWorkspaceTests {
    func config(_ source: String, title: String = "Existing book") -> String {
        BookTOML.encode(BookSpec(title: title, author: "Original author", language: "English", source: source, voice: VoiceSettings(model: .customvoice, voice: "Ryan")))
    }
    @Test func sameSourceReusesLegacyWithoutAnyWrites() throws {
        let temp = try TempFolder()
        let source = try temp.write("Book.md", "# Book\n# Chapter 1 — One\nHello.")
        let legacy = try temp.write("audiobook/book.toml", config("../Book.md"))
        try temp.write("audiobook/audio/chapters/01_one.md", "- duration: 12.0 s\n")
        try temp.write("audiobook/audio/Existing book.m4b", "existing audio")
        try temp.write("audiobook/audio/REPORT.md", "existing report")
        let before = try Data(contentsOf: legacy)
        let beforeDate = try FileManager.default.attributesOfItem(atPath: legacy.path)[.modificationDate] as? Date
        let book = try BookWorkspace.prepare(input: source, voice: nil, author: "Should not replace")
        #expect(book.configURL == legacy)
        #expect(book.spec.author == "Original author")
        #expect(try Data(contentsOf: legacy) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: legacy.path)[.modificationDate] as? Date == beforeDate)
        #expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("Book.audiobook").path))
        #expect(ProgressReader.read(document: book).completedCount == 1)
        #expect(ProgressReader.read(document: book).output != nil)
    }
    @Test func canonicalWorkspaceTakesPrecedence() throws {
        let temp = try TempFolder()
        let source = try temp.write("Book.md", "# Chapter 1 — One")
        try temp.write("audiobook/book.toml", config("../Book.md"))
        let canonical = try temp.write("Book.audiobook/book.toml", config("../Book.md", title: "Canonical"))
        let book = try BookWorkspace.prepare(input: source, voice: nil, author: "Ignored")
        #expect(book.configURL == canonical)
        #expect(book.spec.title == "Canonical")
    }
    @Test func foreignOrBrokenLegacyDoesNotCaptureNewBook() throws {
        for legacyText in [config("../Other.md"), "broken settings"] {
            let temp = try TempFolder()
            let voice = try WorkspaceTests().voice(temp)
            let source = try temp.write("Book.md", "# New book\n# Chapter 1 — One")
            try temp.write("Other.md", "# Other\n# Chapter 1 — Other")
            let legacy = try temp.write("audiobook/book.toml", legacyText)
            let book = try BookWorkspace.prepare(input: source, voice: voice, author: "New author")
            #expect(book.configURL == temp.url.appendingPathComponent("Book.audiobook/book.toml"))
            #expect(try String(contentsOf: legacy, encoding: .utf8) == legacyText)
        }
    }
}
