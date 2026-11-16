import Foundation
import Testing
@testable import NarrateurCore
struct PresentationTests {
    @Test func renderGates() {
        #expect(RenderReadiness.reason(hasBook: false, chapters: 0, voiceAvailable: false, engineAvailable: false, active: false) != nil)
        #expect(RenderReadiness.reason(hasBook: true, chapters: 0, voiceAvailable: true, engineAvailable: true, active: false) == "No chapters found. Use headings such as # Chapter 1 — Title.")
        #expect(RenderReadiness.reason(hasBook: true, chapters: 1, voiceAvailable: true, engineAvailable: true, active: false) == nil)
        #expect(RenderReadiness.reason(hasBook: true, chapters: 1, voiceAvailable: true, engineAvailable: true, active: true) != nil)
        #expect(RenderReadiness.reason(hasBook: true, chapters: 1, voiceAvailable: false, engineAvailable: true, active: false) != nil)
        #expect(RenderReadiness.reason(hasBook: true, chapters: 1, voiceAvailable: true, engineAvailable: false, active: false) != nil)
    }
    @Test func preferencesRoundTrip() throws {
        var preferences = AppPreferences()
        preferences.lastVoice = "table-voice"; preferences.engineOverride = "/tmp/book audio"; preferences.author = "The table"
        #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
        #expect(preferences.voicesFolder.hasSuffix("/Library/Application Support/Narrateur/Voices"))
    }
    @Test func defaultsBelongToWhoeverRunsTheApp() {
        let home = URL(fileURLWithPath: "/tmp/someone")
        #expect(AppPreferences.defaultVoicesFolder(home: home) == "/tmp/someone/Library/Application Support/Narrateur/Voices")
        #expect(AppPreferences.defaultAuthor(fullName: "Ada Lovelace", userName: "ada") == "Ada Lovelace")
        #expect(AppPreferences.defaultAuthor(fullName: "  ", userName: "ada") == "ada")
        #expect(AppPreferences.defaultAuthor(fullName: "", userName: "") == "Anonymous")
        #expect(AppPreferences().author == AppPreferences.defaultAuthor())
        #expect(!AppPreferences().author.isEmpty)
    }
    @Test func savedSettingsKeepTheirValues() throws {
        // What an earlier version wrote: every saved value survives, whatever the defaults have become.
        let saved = #"{"engineOverride":"/opt/tools/book-audio","voicesFolder":"/somewhere/else/voices","author":"Someone & friends","lastVoice":"my-voice"}"#
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(saved.utf8))
        #expect(preferences.engineOverride == "/opt/tools/book-audio")
        #expect(preferences.voicesFolder == "/somewhere/else/voices")
        #expect(preferences.author == "Someone & friends")
        #expect(preferences.lastVoice == "my-voice")
        // A value that was never saved takes today's default instead of discarding the others.
        let partial = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"voicesFolder":"/somewhere/else/voices"}"#.utf8))
        #expect(partial.voicesFolder == "/somewhere/else/voices")
        #expect(partial.author == AppPreferences.defaultAuthor()); #expect(partial.engineOverride.isEmpty); #expect(partial.lastVoice == nil)
    }
    @Test func existingBookKeepsItsOwnVoice() throws {
        let temp = try TempFolder()
        try temp.write("voice/voice.toml", "name='House'\nowner='table'\nlanguage='English'\nmodel='customvoice'\nvoice='Ryan'")
        let voices = VoiceLibrary.load(from: temp.url)
        #expect(VoiceSelection.match(VoiceSettings(model: .customvoice, voice: "Ryan"), folder: temp.url, voices: voices)?.id == "voice")
        #expect(VoiceSelection.match(VoiceSettings(model: .customvoice, voice: "Other"), folder: temp.url, voices: voices) == nil)
    }
    @Test func clonedVoiceMatchesIdenticalReferenceAtAnotherPath() throws {
        let temp = try TempFolder()
        try temp.write("library/house/voice.toml", "name='House'\nowner='table'\nlanguage='English'\nmodel='base'")
        try temp.write("library/house/reference.wav", "identical reference bytes")
        try temp.write("library/house/reference.txt", "A quiet voice.\n")
        try temp.write("book/voice/narrator.wav", "identical reference bytes")
        let voices = VoiceLibrary.load(from: temp.url.appendingPathComponent("library"))
        let settings = VoiceSettings(model: .base, refAudio: "voice/narrator.wav", refText: "A quiet voice.")
        let folder = temp.url.appendingPathComponent("book")
        #expect(VoiceSelection.match(settings, folder: folder, voices: voices)?.id == "house")
        try temp.write("book/voice/narrator.wav", "different reference bytes")
        #expect(VoiceSelection.match(settings, folder: folder, voices: voices) == nil)
        try temp.write("book/voice/narrator.wav", "identical reference bytes")
        var changedTranscript = settings
        changedTranscript.refText = "An unrelated transcript."
        #expect(VoiceSelection.match(changedTranscript, folder: folder, voices: voices) == nil)
    }
}
