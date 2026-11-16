import Foundation
import Testing
@testable import NarrateurCore

struct CoreTests {
    @Test func testTenChaptersAndVerbatimTitle() throws {
        let url = Bundle.module.url(forResource: "ten-chapters", withExtension: "md", subdirectory: "Fixtures")!
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(try ChapterIndex.parse(text).count == 10)
        #expect(ChapterIndex.title(text, fallback: "fallback") == "Signal — Fixture")
    }
    @Test func testNoChapters() throws { #expect(try ChapterIndex.parse("# Just a title\nHello").isEmpty) }
    @Test func testFencedHeadingNotAChapterAndCRLF() throws {
        let chapters = try ChapterIndex.parse("# Chapter 1 — One\r\n```\r\n# Chapter 9 — Code\r\n```\r\n# Chapter 2 — Two")
        #expect(chapters.map(\.number) == [1, 2])
    }
    @Test func testInvalidAndDuplicateHeadingsFail() {
        #expect(throws: (any Error).self) { try ChapterIndex.parse("# Chapter nonsense") }
        #expect(throws: (any Error).self) { try ChapterIndex.parse("# Chapter 1 — A\n# Chapter 1 — B") }
    }
    /// The heading forms that this app and the book-audio engine both accept, and the ones they both refuse.
    /// The same list is in the tests of the engine: a form is never opened on one side only.
    @Test func headingFormsSharedWithTheEngine() throws {
        let shared: [(heading: String, number: Int, title: String)] = [
            ("# Chapter 1 — Title", 1, "Title"),
            ("# Chapter 1 - Title", 1, "Title"),
            ("# Chapter 1: Title", 1, "Title"),
            ("# Chapter 1. Title", 1, "Title"),
            ("# Chapter 11", 11, ""),
        ]
        for item in shared {
            let chapters = try ChapterIndex.parse("\(item.heading)\n\nHello world.\n")
            #expect(chapters == [Chapter(number: item.number, title: item.title)], "\(item.heading)")
        }
        // The engine names its reports after the number and the title: the app finds them under the same name.
        #expect(try ChapterIndex.parse("# Chapter 1: Title\n").first?.slug == "01_title")
        #expect(try ChapterIndex.parse("# Chapter 11\n").first?.slug == "11_chapter-11")
        // The engine reads a chapter 0 (a prologue) and names its report 00_…: so does the app.
        #expect(try ChapterIndex.parse("# Chapter 0 — Prologue\n\n# Chapter 1\n") == [Chapter(number: 0, title: "Prologue"), Chapter(number: 1, title: "")])
        #expect(try ChapterIndex.parse("# Chapter 0 — Prologue\n").first?.slug == "00_prologue")
        // A whole book may mix the forms.
        let book = "# A book\n\n# Chapter 1: One\ntext\n# Chapter 2. Two\ntext\n# Chapter 3 – Three\ntext\n# Chapter 4\ntext\n"
        #expect(try ChapterIndex.parse(book).map(\.title) == ["One", "Two", "Three", ""])
    }
    /// A full stop separates the number from the title only when a space follows it (or nothing at all):
    /// "1.5" is not chapter 1 with the title "5". The same vectors hold for the engine.
    @Test func aFullStopSeparatesOnlyBeforeASpace() throws {
        let read: [(heading: String, number: Int, title: String)] = [
            ("# Chapter 1. Title", 1, "Title"), ("# Chapter 1.", 1, ""), ("# Chapter 1 . Title", 1, "Title"), ("# Chapter 2.  Two words", 2, "Two words"),
            ("# Chapter 1:Title", 1, "Title"), ("# Chapter 1 -Title", 1, "Title"), ("# Chapter 3 -. Title", 3, "Title"),
        ]
        for item in read { #expect(try ChapterIndex.parse(item.heading + "\n") == [Chapter(number: item.number, title: item.title)], "\(item.heading)") }
        for heading in ["# Chapter 1.5 Title", "# Chapter 1.5", "# Chapter 1.5. Title", "# Chapter 1.Title", "# Chapter 1.- Title", "# Chapter 1..."] {
            let error = #expect(throws: NarrateurError.self, "\(heading) was read") { try ChapterIndex.parse("\(heading)\n\nText.\n") }
            #expect(error?.message.hasPrefix("Cannot read the chapter heading “\(heading)”") == true, "\(error?.message ?? "")")
        }
    }
    @Test func aHeadingWithoutANumberIsRefusedAndQuoted() {
        for heading in ["# Chapter Three", "# Chapter One — The Beginning", "# Chapter — The Beginning", "# Chapter 1 The Beginning"] {
            let error = #expect(throws: NarrateurError.self) { try ChapterIndex.parse("\(heading)\n\nText.\n") }
            let message = error?.message ?? ""
            #expect(message.hasPrefix("Cannot read the chapter heading “\(heading)”"), "\(message)")
            #expect(message.contains("“# Chapter 3 — Title”") && !message.contains("\n"), "\(message)")
        }
        // The example follows the heading text of the book.
        let other = #expect(throws: NarrateurError.self) { try ChapterIndex.parse("## Part one\n", heading: "## Part ") }
        #expect(other?.message.contains("“## Part 3 — Title”") == true)
    }
    @Test func twoHeadingsWithTheSameNumberAreRefused() {
        // The same number written another way is the same number: 01 after 1.
        for (book, number) in [("# Chapter 1\n\nOne.\n\n# Chapter 1\n\nShort.\n", 1), ("# Chapter 2 — A\n# Chapter 3: B\n# Chapter 2. C\n", 2), ("# Chapter 1\n# Chapter 01: X\n", 1)] {
            let error = #expect(throws: NarrateurError.self) { try ChapterIndex.parse(book) }
            #expect(error?.message == "Chapter \(number) appears twice: each chapter needs its own number.", "\(error?.message ?? "")")
        }
    }
    /// What the engine reads as the title of a heading, and the name it gives the chapter's files
    /// (clean_inline and slugify in its reader). These lines were produced by the engine itself:
    /// the app finds a finished chapter under that name, so both must read a title the same way.
    @Test func titlesAndFileNamesAreTheEngines() throws {
        let vectors: [(heading: String, title: String, slug: String)] = [
            ("# Chapter 1 — [[Hero|The hero]]", "Hero", "01_hero"),
            ("# Chapter 2 — The map ![a map](x.png)", "The map", "02_the-map"),
            ("# Chapter 3 — Plain", "Plain", "03_plain"),
            ("# Chapter 4 — ![[cover.png]] After the embed", "After the embed", "04_after-the-embed"),
            ("# Chapter 5 — [[The Mill]] and [the link](https://example.org/a_b)", "The Mill and the link", "05_the-mill-and-the-link"),
            ("# Chapter 6: **Bold** and *soft* and _under_ and `code`", "Bold and soft and under and code", "06_bold-and-soft-and-under-and-code"),
            ("# Chapter 7. A snake_case_word stays, 2*3*4 too", "A snake_case_word stays, 234 too", "07_a-snake-case-word-stays-234-too"),
            ("# Chapter 8 - Contents ...... 12", "Contents 12", "08_contents-12"),
            ("# Chapter 9 — « Quoted »   and   spaces", "\"Quoted\" and spaces", "09_quoted-and-spaces"),
            ("# Chapter 10 — ![only an image](x.png)", "", "10_chapter-10"),
            ("# Chapter 11", "", "11_chapter-11"),
            ("# Chapter 12 — Été à l'École №5", "Été à l'École №5", "12_t-l-cole-5"),
            ("# Chapter 13 — __Strong__ *a* b* c", "Strong a b c", "13_strong-a-b-c"),
            ("# Chapter 14 — [[Page|Alias]] [[Other]] ![[x]] [t](u)", "Page Other t", "14_page-other-t"),
            ("# Chapter 15 —  — double dash", "— double dash", "15_double-dash"),
            ("# Chapter 0 — Prologue", "Prologue", "00_prologue"),
        ]
        for vector in vectors {
            let chapter = try #require(try ChapterIndex.parse(vector.heading + "\n\nText.\n").first)
            #expect(chapter.title == vector.title, "\(vector.heading)")
            #expect(chapter.slug == vector.slug, "\(vector.heading)")
        }
    }
    /// Where a chapter starts when comments and code blocks are in the way. These books were read by the engine
    /// itself: a code block hides a heading, a comment does not, and a comment hides the mark that opens a code block.
    @Test func commentsAndCodeBlocksHideTheSameHeadingsAsInTheEngine() throws {
        let books: [(text: String, chapters: [Int])] = [
            ("# Chapter 1 — One\n\n<!--\n```\n-->\n\n# Chapter 2 — Two\n\nText.\n", [1, 2]),
            ("# Chapter 1\n<!-- a note\n# Chapter 2\nstill the note -->\n# Chapter 3\n", [1, 2, 3]),
            ("# Chapter 1 — T\n<!-- open ``` inside\n\n> quote\n~~~\n# Chapter 2\n# Chapter 3\n~~~\n> quote\n    # Chapter 4 — indented\n\n```\n", [1, 2, 3]),
            ("\n    # Chapter 1 — indented\n```\n# Chapter 2\ntext\n<!-- open ``` inside\n```\ntext --> more\n  ```swift\ntext --> more\n> quote\n# Chapter 3\n", [2]),
            ("# Chapter 1\n# Chapter 2\n<!-- one line -->\n<!--\n``` -->\n> quote\ntext --> more\n``` -->\n# Chapter 3 — T\n", [1, 2]),
            ("# Chapter 1 — One\r\n```\r\n# Chapter 9 — Code\r\n```\r\n# Chapter 2 — Two", [1, 2]),
        ]
        for book in books { #expect(try ChapterIndex.parse(book.text).map(\.number) == book.chapters, "\(book.text.debugDescription)") }
    }
    /// Characters that end a line for some programs and not for the engine (a pasted "line separator", a form feed…):
    /// inside a heading the engine reads them as spaces. These headings were read by the engine itself.
    @Test func aLineSeparatorInsideAHeadingIsASpaceAsInTheEngine() throws {
        let vectors: [(heading: String, title: String, slug: String)] = [
            ("# Chapter 3 — One\u{2028}two", "One two", "03_one-two"),
            ("# Chapter 4 — *soft\u{2028}voice* here", "soft voice here", "04_soft-voice-here"),
            ("# Chapter 5 — Tab\u{0B}bed and\u{0C}fed\u{85}nel", "Tab bed and fed nel", "05_tab-bed-and-fed-nel"),
            ("# Chapter 6 — End\u{2029}", "End", "06_end"),
        ]
        for vector in vectors {
            let chapters = try ChapterIndex.parse(vector.heading + "\n\nText.\n")
            #expect(chapters.map(\.title) == [vector.title], "\(vector.heading.debugDescription)")
            #expect(chapters.map(\.slug) == [vector.slug], "\(vector.heading.debugDescription)")
        }
    }
    /// A book saved as UTF-8 with a byte order mark, that starts right away with its first chapter. The app reads both
    /// chapters; the engine must too (its reader drops the mark): the same vector is in its tests.
    @Test func aBookThatStartsWithAByteOrderMarkKeepsItsFirstChapter() throws {
        let temp = try TempFolder()
        try (Data([0xEF, 0xBB, 0xBF]) + Data("# Chapter 1 — First\nOne.\n\n# Chapter 2 — Second\nTwo.\n".utf8)).write(to: temp.url.appendingPathComponent("bom.md"))
        let config = try temp.write("book.toml", BookTOML.encode(BookSpec(title: "B", author: "A", language: "English", source: "bom.md", voice: VoiceSettings(model: .customvoice, voice: "ryan"))))
        let book = try BookWorkspace.load(config)
        #expect(book.chapters.map(\.number) == [1, 2])
        #expect(book.chapters.map(\.title) == ["First", "Second"])
        #expect(book.chapters.map(\.slug) == ["01_first", "02_second"])
    }
    @Test func aChapterWithALinkOrAnImageInItsTitleIsCheckedOff() throws {
        // A finished chapter is one whose report exists under the engine's name for it.
        let temp = try TempFolder()
        try temp.write("story.md", "# Chapter 1 — [[Hero|The hero]]\nOne.\n\n# Chapter 2 — The map ![a map](x.png)\nTwo.\n\n# Chapter 3 — Plain\nThree.\n")
        let config = try temp.write("book.toml", BookTOML.encode(BookSpec(title: "Story", author: "A", language: "English", source: "story.md", voice: VoiceSettings(model: .customvoice, voice: "ryan"))))
        let book = try BookWorkspace.load(config)
        for name in ["01_hero", "02_the-map", "03_plain"] { try temp.write("audio/chapters/\(name).md", "- duration: 12.0 s\n") }
        let progress = ProgressReader.read(document: book)
        #expect(progress.chapters.map(\.chapter.slug) == ["01_hero", "02_the-map", "03_plain"])
        #expect(progress.completedCount == 3)
    }
    @Test func testBookRoundTripWithEscapesAndAbsoluteReference() throws {
        var book = BookSpec(title: "A \"book\" #1\nNext", author: "A\\B", language: "English", source: "../A.md", voice: VoiceSettings(model: .base, refAudio: "/tmp/ref.wav", refText: "Hello\nworld"))
        book.cover = "../cover.png"
        #expect(try BookTOML.parse(BookTOML.encode(book)) == book)
    }
    @Test func testLiteralAndMultilineTOML() throws {
        let doc = try TOMLDocument("title = 'A # book' # comment\n[voice]\nref_text = \"\"\"\nHello\n[pauses]\nworld\"\"\"\n")
        #expect(doc.string("title") == "A # book")
        #expect(doc.string("ref_text", in: "voice") == "Hello\n[pauses]\nworld")
    }
    @Test func testMalformedTOMLRejected() {
        #expect(throws: (any Error).self) { try TOMLDocument("title = \"unterminated") }
        #expect(throws: (any Error).self) { try TOMLDocument("title = \"one\"\ntitle = \"two\"") }
        #expect(throws: (any Error).self) { try BookTOML.parse("title = \"only title\"") }
    }
}
