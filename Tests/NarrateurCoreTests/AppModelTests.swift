import Foundation
import AppKit
import Testing
@testable import NarrateurCore
@testable import Narrateur

/// The window's model itself, driven the way the app drives it: launched on a voices folder, then brought back to the
/// front. Each model works in a folder of the test, with a home folder of its own there, so that nothing it reads or
/// writes reaches the voices of the Mac the tests run on. (Nothing here calls savePreferences or selectVoice: they
/// write the app's defaults.)
@MainActor struct AppModelTests {
    let temp: TempFolder
    init() throws { temp = try TempFolder() }
    /// A model launched on the folder `name` of the test, as the app launches it.
    func launch(_ name: String = "Voices", lastVoice: String? = nil) throws -> AppModel {
        let folder = temp.url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var preferences = AppPreferences(); preferences.voicesFolder = folder.path; preferences.lastVoice = lastVoice
        let model = AppModel(preferences: preferences, home: temp.url.appendingPathComponent("home"))
        try #require(model.voicesFolderURL?.standardizedFileURL.path == folder.standardizedFileURL.path)
        return model
    }
    /// What AppKit does when the app comes back to the front: it tells its delegate, if the delegate listens.
    func comeBack(to model: AppModel) {
        let delegate = AppDelegate(); delegate.model = model
        (delegate as NSApplicationDelegate).applicationDidBecomeActive?(Notification(name: NSApplication.didBecomeActiveNotification))
    }
    func preset(_ name: String, _ speaker: String) -> String {
        "name = \"\(name)\"\nowner = \"me\"\nlanguage = \"English\"\nmodel = \"customvoice\"\nvoice = \"\(speaker)\"\n"
    }
    func move(_ from: String, to: String) throws {
        try FileManager.default.moveItem(at: temp.url.appendingPathComponent(from), to: temp.url.appendingPathComponent(to))
    }
    /// What Apply does, without writing the app's defaults: the field set to the folder `name`, then the settings read again.
    func apply(_ model: AppModel, _ name: String) throws {
        let folder = temp.url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        model.preferences.voicesFolder = folder.path
        model.reloadSettings()
        try #require(model.voicesFolderURL?.standardizedFileURL.path == folder.standardizedFileURL.path)
    }
    /// The cloned voice of the README, "My voice", with its recording and its words, added to the folder Voices.
    func addMyVoice() throws {
        try temp.write("Voices/my-voice/voice.toml", "name = \"My voice\"\nowner = \"me\"\nlanguage = \"English\"\nmodel = \"base\"\n")
        try temp.write("Voices/my-voice/reference.wav", "wave"); try temp.write("Voices/my-voice/reference.txt", "Hello.")
    }
    /// Back in the app, the narrator menu lists the folder in use as the disk holds it now: the voices read again are
    /// the ones the menu lists, and the narrator on the card is chosen again among them.
    @Test func backInTheAppTheMenuListsTheFolderAsTheDiskHoldsIt() throws {
        let model = try launch()
        // A first launch writes the two starter voices and shows Ryan.
        #expect(model.voices.map(\.id) == ["narrator-ryan", "narrator-warm"])
        #expect(model.voiceName == "Ryan")
        // A voice added in the Finder is in the menu when the app comes back.
        try temp.write("Voices/serena/voice.toml", preset("Serena", "serena"))
        comeBack(to: model)
        #expect(model.voices.map(\.id) == ["narrator-ryan", "serena", "narrator-warm"])
        #expect(model.voiceName == "Ryan")
        // The folder of the narrator on the card, renamed in the Finder: the card shows a narrator of the menu, never
        // one that is gone.
        try move("Voices/narrator-ryan", to: "Voices/my-ryan")
        comeBack(to: model)
        #expect(model.voices.map(\.id) == ["my-ryan", "serena", "narrator-warm"])
        #expect(model.selectedVoice?.id == "my-ryan")
        #expect(model.voiceName == "Ryan")
        // Nothing changed on the disk: nothing changes.
        let listed = model.voices
        comeBack(to: model)
        #expect(model.voices == listed)
        // A folder typed in the field without Apply is not read: the folder in use is.
        try temp.write("Typed/eric/voice.toml", preset("Eric", "eric"))
        model.preferences.voicesFolder = temp.url.appendingPathComponent("Typed").path
        comeBack(to: model)
        #expect(model.voices == listed)
        // Reading again writes nothing: a folder emptied in the Finder stays empty until Apply or a new launch.
        for id in ["my-ryan", "serena", "narrator-warm"] { try FileManager.default.removeItem(at: temp.url.appendingPathComponent("Voices/\(id)")) }
        comeBack(to: model)
        #expect(model.voices.isEmpty)
        #expect(model.selectedVoice == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.url.appendingPathComponent("Voices").path).isEmpty)
    }
    /// With a book open, the card shows the book's narrator, found again in the menu each time the folder is read.
    @Test func withABookOpenTheCardFollowsTheBooksNarratorWhenTheFolderIsReadAgain() throws {
        let model = try launch()
        model.openBook(try temp.write("Books/Fables.md", "# Two fables\n\n# Chapter 1 — One\nHello.\n\n# Chapter 2 — Two\nGoodbye."))
        #expect(model.error == nil)
        #expect(model.book?.spec.voice.voice == "ryan")
        #expect(model.selectedVoice?.id == "narrator-ryan")
        // A voice added in the Finder is in the menu; the book keeps its narrator.
        try temp.write("Voices/serena/voice.toml", preset("Serena", "serena"))
        comeBack(to: model)
        #expect(model.voices.map(\.id) == ["narrator-ryan", "serena", "narrator-warm"])
        #expect(model.selectedVoice?.id == "narrator-ryan")
        // The book's narrator, renamed in the Finder, is found in its new folder.
        try move("Voices/narrator-ryan", to: "Voices/my-ryan")
        comeBack(to: model)
        #expect(model.selectedVoice?.id == "my-ryan")
        #expect(model.voiceName == "Ryan")
        // Taken away, it is no voice of the menu: the card says the book's narrator.
        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("Voices/my-ryan"))
        comeBack(to: model)
        #expect(model.selectedVoiceID == nil)
        #expect(model.voiceName == "Book\u{2019}s narrator")
    }
    /// With no narrator chosen, a voice added in the Finder that sorts before the one on the card (the README's own
    /// cloned voice, "My voice") took the card when the app came back, and the next book with it.
    @Test func theNarratorOnTheCardStaysWhenAVoiceIsAddedAndNoneWasChosen() throws {
        let model = try launch()
        #expect(model.voiceName == "Ryan")
        try addMyVoice()
        comeBack(to: model)
        #expect(model.voices.map(\.id) == ["my-voice", "narrator-ryan", "narrator-warm"])
        #expect(model.voiceName == "Ryan")
        // The next book is read by Ryan: one speech model, not the Base model of the cloned voice.
        model.openBook(try temp.write("Books/Fables.md", "# Two fables\n\n# Chapter 1 — One\nHello.\n\n# Chapter 2 — Two\nGoodbye."))
        #expect(model.book?.spec.voice.model == .customvoice)
        #expect(model.book?.spec.voice.voice == "ryan")
    }
    /// A narrator chosen stays on the card: back from the Finder, and back in its folder after Apply on another one.
    @Test func aNarratorChosenStaysOnTheCard() throws {
        let ryan = try launch(lastVoice: "narrator-ryan")
        try addMyVoice()
        comeBack(to: ryan)
        #expect(ryan.voiceName == "Ryan")
        // Zoe chosen in a folder that holds Ryan too; Apply on another folder, where Ryan is on the card; then Apply
        // on the first folder again: Zoe, not the Ryan of the folder before.
        try StarterVoices.installIfNeeded(in: temp.url.appendingPathComponent("Mine"))
        try temp.write("Mine/zoe/voice.toml", preset("Zoe", "vivian"))
        let model = try launch("Mine", lastVoice: "zoe")
        #expect(model.voiceName == "Zoe")
        try apply(model, "Elsewhere")
        #expect(model.voices.map(\.id) == ["narrator-ryan", "narrator-warm"])
        #expect(model.voiceName == "Ryan")
        try apply(model, "Mine")
        #expect(model.voiceName == "Zoe")
    }
    /// The Choose… panel opens on the voices folder, where every folder is a voice. One picked there by mistake became
    /// the voices folder: the two starter voices were written into it, and the menu lost the voices beside it.
    @Test func aVoicePickedAsTheVoicesFolderLeavesTheVoiceAndTheMenuAsTheyWere() throws {
        let model = try launch()
        try addMyVoice()
        comeBack(to: model)
        #expect(model.voices.map(\.id) == ["my-voice", "narrator-ryan", "narrator-warm"])
        // What Choose… does with the folder picked, without writing the app's defaults: the field, then the settings.
        let ryan = temp.url.appendingPathComponent("Voices/narrator-ryan")
        model.preferences.voicesFolder = ryan.path
        model.reloadSettings()
        #expect(model.voicesFolderURL?.standardizedFileURL.path == temp.url.appendingPathComponent("Voices").standardizedFileURL.path)
        #expect(model.voices.map(\.id) == ["my-voice", "narrator-ryan", "narrator-warm"])
        #expect(model.voicesFolderNote?.contains("narrator-ryan” is a voice") == true, "\(model.voicesFolderNote ?? "no note")")
        #expect(try FileManager.default.subpathsOfDirectory(atPath: ryan.path) == ["voice.toml"])
        #expect(model.voiceName == "Ryan")
    }
}
