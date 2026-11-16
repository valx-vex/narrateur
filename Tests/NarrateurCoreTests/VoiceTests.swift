import Foundation
import Testing
@testable import NarrateurCore
struct VoiceTests {
    let manifest = "name = \"House voice\"\nowner = \"the table\"\nlanguage = \"English\"\nmodel = \"base\"\nreference = \"reference.wav\"\ntranscript = \"reference.txt\"\n"
    @Test func validBrokenAndNonVoiceFolders() throws {
        let temp = try TempFolder()
        try temp.write("valid/voice.toml", manifest); try temp.write("valid/reference.wav", "wave"); try temp.write("valid/reference.txt", "Hello table.\n")
        try temp.write("broken/voice.toml", manifest); try temp.write("unrelated/readme.md")
        let voices = VoiceLibrary.load(from: temp.url)
        #expect(voices.count == 2)
        let good = try #require(voices.first { $0.id == "valid" })
        #expect(good.unavailableReason == nil)
        #expect(try good.engineVoice().refAudio == temp.url.appendingPathComponent("valid/reference.wav").path)
        #expect(try good.engineVoice().refText == "Hello table.")
        #expect(good.settings?.refText == "Hello table.")
        #expect(voices.first { $0.id == "broken" }?.unavailableReason != nil)
    }
    @Test func otherVoiceModelsAndSelection() throws {
        let temp = try TempFolder()
        try temp.write("preset/voice.toml", "name='Preset'\nowner='table'\nlanguage='French'\nmodel='customvoice'\nvoice='Ryan'")
        try temp.write("designed/voice.toml", "name='Design'\nowner='table'\nlanguage='English'\nmodel='voicedesign'\ndescription='Warm and calm.'")
        let voices = VoiceLibrary.load(from: temp.url)
        #expect(voices.count == 2)
        #expect(try voices.first { $0.id == "preset" }?.engineVoice().voice == "Ryan")
        #expect(try voices.first { $0.id == "designed" }?.engineVoice().instruct == "Warm and calm.")
        #expect(VoiceLibrary.preferred(voices, lastUsed: "preset")?.id == "preset")
        #expect(VoiceLibrary.preferred(voices, lastUsed: "missing") != nil)
    }
    /// The narrator on the card when no book is open: the one last chosen, then the one already shown, then the first
    /// that can read; each only while it is listed and can read. Reading the folder again never moves the card by itself.
    @Test func theNarratorOnTheCardStaysWhileItIsListedAndCanRead() throws {
        let temp = try TempFolder()
        try StarterVoices.installIfNeeded(in: temp.url)
        try temp.write("house/voice.toml", manifest); try temp.write("house/reference.wav", "wave"); try temp.write("house/reference.txt", "Hello table.")
        try temp.write("broken/voice.toml", manifest)   // its recording is missing: it cannot read
        let voices = VoiceLibrary.load(from: temp.url)
        #expect(voices.map(\.id) == ["broken", "house", "narrator-ryan", "narrator-warm"])
        // A launch with no choice made: the first voice that can read.
        #expect(VoiceLibrary.preferred(voices, lastUsed: nil)?.id == "house")
        // A voice added before the one on the card (here, the cloned House voice) does not take its place.
        #expect(VoiceLibrary.preferred(voices, lastUsed: nil, shown: "narrator-ryan")?.id == "narrator-ryan")
        // The narrator last chosen comes first; a choice that is gone, or cannot read, leaves the card as it is.
        #expect(VoiceLibrary.preferred(voices, lastUsed: "narrator-warm", shown: "narrator-ryan")?.id == "narrator-warm")
        #expect(VoiceLibrary.preferred(voices, lastUsed: "gone", shown: "narrator-ryan")?.id == "narrator-ryan")
        #expect(VoiceLibrary.preferred(voices, lastUsed: "broken", shown: "narrator-ryan")?.id == "narrator-ryan")
        // The voice on the card gone, or unable to read: the first voice that can.
        #expect(VoiceLibrary.preferred(voices, lastUsed: nil, shown: "gone")?.id == "house")
        #expect(VoiceLibrary.preferred(voices, lastUsed: nil, shown: "broken")?.id == "house")
        #expect(VoiceLibrary.preferred([], lastUsed: "house", shown: "house") == nil)
    }
    /// The engine refuses these before it downloads anything; the app says the same next to the voice, in the engine's words.
    @Test func aVoiceTheEngineWouldRefuseIsUnavailableWithTheEnginesReason() throws {
        let temp = try TempFolder()
        // A preset voice name kept with another kind of voice: a starter folder copied and changed to a described voice, or to a clone.
        try temp.write("ryan-described/voice.toml", "name='Ryan, described'\nowner='table'\nlanguage='English'\nmodel='voicedesign'\nvoice='ryan'\ndescription='Warm and calm.'")
        try temp.write("ryan-cloned/voice.toml", "name='Ryan, cloned'\nowner='table'\nlanguage='English'\nmodel='base'\nvoice='ryan'")
        try temp.write("ryan-cloned/reference.wav", "wave"); try temp.write("ryan-cloned/reference.txt", "Hello table.")
        // A language outside the ten the speech model reads.
        try temp.write("short-language/voice.toml", "name='Short'\nowner='table'\nlanguage='fr'\nmodel='customvoice'\nvoice='ryan'")
        try temp.write("own-language/voice.toml", "name='Own'\nowner='table'\nlanguage='Français'\nmodel='voicedesign'\ndescription='Warm and calm.'")
        try temp.write("quoted-language/voice.toml", "name='Quoted'\nowner='table'\nlanguage=\"it's\"\nmodel='customvoice'\nvoice='ryan'")
        // A described voice is then read by the default model, even when it is invented by a model of your own.
        try temp.write("own-designer/voice.toml", "name='Own designer'\nowner='table'\nlanguage='Slovak'\nmodel='voicedesign'\nmodel_id='someone/designer'\ndescription='Warm and calm.'")
        // A preset voice the model does not have.
        try temp.write("unknown-speaker/voice.toml", "name='Unknown'\nowner='table'\nlanguage='English'\nmodel='customvoice'\nvoice='Ryan Smith'")
        // What the engine reads: any case of the ten languages and of the nine names, "auto", and a model of your own,
        // whose voices and languages the engine does not know and does not check.
        try temp.write("upper/voice.toml", "name='Upper'\nowner='table'\nlanguage='FRENCH'\nmodel='customvoice'\nvoice='Uncle_Fu'")
        try temp.write("guess/voice.toml", "name='Guess'\nowner='table'\nlanguage='auto'\nmodel='voicedesign'\ndescription='Warm and calm.'")
        try temp.write("own-model/voice.toml", "name='Own model'\nowner='table'\nlanguage='Slovak'\nmodel='customvoice'\nmodel_id='someone/my-model'\nvoice='Jano'")
        try temp.write("default-id/voice.toml", "name='Default id'\nowner='table'\nlanguage='English'\nmodel='customvoice'\nmodel_id='mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16'\nvoice='Jano'")
        let voices = VoiceLibrary.load(from: temp.url)
        func reason(_ id: String) -> String? { voices.first { $0.id == id }?.unavailableReason }
        #expect(reason("ryan-described") == "'voice' names a preset voice and only goes with model 'customvoice'; with model 'voicedesign', remove the 'voice' line")
        #expect(reason("ryan-cloned") == "'voice' names a preset voice and only goes with model 'customvoice'; with model 'base', remove the 'voice' line")
        let ten = "the speech model reads Chinese, English, French, German, Italian, Japanese, Korean, Portuguese, Russian and Spanish (or \"auto\" to let it guess)"
        #expect(reason("short-language") == "unknown language 'fr'; " + ten)
        #expect(reason("own-language") == "unknown language 'Français'; " + ten)
        #expect(reason("quoted-language") == "unknown language \"it's\"; " + ten)   // quoted as the engine quotes it
        #expect(reason("own-designer") == "unknown language 'Slovak'; " + ten)
        let nine = "supported: aiden, dylan, eric, ono_anna, ryan, serena, sohee, uncle_fu, vivian"
        #expect(reason("unknown-speaker") == "unknown preset speaker 'Ryan Smith'; " + nine)
        #expect(reason("default-id") == "unknown preset speaker 'Jano'; " + nine)
        for id in ["upper", "guess", "own-model"] { #expect(reason(id) == nil, "\(id): \(reason(id) ?? "")") }
        // An unavailable voice is never picked for a new book, and never handed to the engine.
        #expect(throws: NarrateurError.self) { try voices.first { $0.id == "short-language" }?.engineVoice() }
        #expect(VoiceLibrary.preferred(voices.filter { $0.id == "short-language" || $0.id == "upper" }, lastUsed: "short-language")?.id == "upper")
    }
    /// The engine reads the recording of a cloned voice before it loads anything, and refuses it in one line when it is
    /// not there, cannot be read or is empty. The app says why next to the voice, in a reader's words: the recording by
    /// its file name, then where it is. ("ref_audio" is the engine's key in book.toml, not a word a reader knows.)
    @Test func aClonedVoiceWhoseRecordingTheEngineRefusesIsUnavailableWithItsReason() throws {
        let temp = try TempFolder()
        for id in ["empty", "unreadable", "missing", "folder", "not-a-sound"] {
            try temp.write("\(id)/voice.toml", manifest); try temp.write("\(id)/reference.txt", "Hello table.\n")
        }
        try temp.write("empty/reference.wav", "")
        let locked = try temp.write("unreadable/reference.wav", "wave")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("folder/reference.wav"), withIntermediateDirectories: true)
        try temp.write("not-a-sound/reference.wav", "The exact words.\n")
        let voices = VoiceLibrary.load(from: temp.url)
        func reason(_ id: String) -> String? { voices.first { $0.id == id }?.unavailableReason }
        func recording(_ id: String) -> String { temp.url.appendingPathComponent("\(id)/reference.wav").path }
        #expect(reason("empty") == "The recording reference.wav is empty: \(recording("empty"))")
        #expect(reason("unreadable") == "The recording reference.wav cannot be read (Permission denied): \(recording("unreadable"))")
        // (A name that does not exist keeps the /private in front of the temporary folder: Foundation takes it away
        // only when the shorter name exists.)
        #expect(reason("missing")?.hasPrefix("The recording reference.wav was not found: /") == true && reason("missing")?.hasSuffix("/missing/reference.wav") == true, "\(reason("missing") ?? "")")
        #expect(reason("folder") == "The recording reference.wav was not found: \(recording("folder"))")
        for id in ["empty", "unreadable", "missing", "folder"] { #expect(reason(id)?.contains("ref_audio") == false, "\(id): \(reason(id) ?? "")") }
        // Whether the file is a sound is left to the engine, which asks ffprobe and says it in one line before any
        // download: the system's own reader opens fewer formats than ffprobe does (not WebM), and would turn away a
        // recording the engine reads.
        #expect(reason("not-a-sound") == nil)
        #expect(throws: NarrateurError.self) { try voices.first { $0.id == "empty" }?.engineVoice() }
    }
    /// voice.toml names its recording with `reference` and its words with `transcript`, from the voice's folder; without
    /// them, reference.wav and reference.txt. A `ref_audio` line, the engine's key in book.toml, is not read there: the
    /// voice waits for reference.wav and says so next to its name. The README says it where it shows a cloned voice.
    @Test func aRefAudioLineInVoiceTomlIsNotReadAndTheReadmeSaysSo() throws {
        let temp = try TempFolder()
        let base = "name='Mine'\nowner='me'\nlanguage='English'\nmodel='base'\n"
        try temp.write("engine-key/voice.toml", base + "ref_audio = 'take.wav'\nref_text = 'Hello there.'\n")
        try temp.write("engine-key/take.wav", "wave"); try temp.write("engine-key/reference.txt", "Hello there.")
        try temp.write("own-names/voice.toml", base + "reference = 'take.wav'\ntranscript = 'take.txt'\n")
        try temp.write("own-names/take.wav", "wave"); try temp.write("own-names/take.txt", "Hello there.")
        let voices = VoiceLibrary.load(from: temp.url)
        let ignored = try #require(voices.first { $0.id == "engine-key" }?.unavailableReason)
        #expect(ignored.hasPrefix("The recording reference.wav was not found: /") && ignored.hasSuffix("/engine-key/reference.wav"), "\(ignored)")
        let named = try #require(voices.first { $0.id == "own-names" })
        #expect(named.unavailableReason == nil)
        #expect(try named.engineVoice().refAudio == temp.url.appendingPathComponent("own-names/take.wav").path)
        #expect(try named.engineVoice().refText == "Hello there.")
        // A recording named by a `reference` line is named that way in the reason too, whether the engine would find it
        // missing, empty or unreadable: take-2.wav, as in the README.
        let take = base + "reference = 'take-2.wav'\ntranscript = 'take-2.txt'\n"
        for id in ["take-missing", "take-empty", "take-locked"] { try temp.write("\(id)/voice.toml", take); try temp.write("\(id)/take-2.txt", "Hello there.") }
        try temp.write("take-empty/take-2.wav", "")
        let locked = try temp.write("take-locked/take-2.wav", "wave")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        let takes = VoiceLibrary.load(from: temp.url)
        func reason(_ id: String) -> String { takes.first { $0.id == id }?.unavailableReason ?? "no reason" }
        #expect(reason("take-missing").hasPrefix("The recording take-2.wav was not found: /") && reason("take-missing").hasSuffix("/take-missing/take-2.wav"), "\(reason("take-missing"))")
        #expect(reason("take-empty") == "The recording take-2.wav is empty: \(temp.url.appendingPathComponent("take-empty/take-2.wav").path)")
        #expect(reason("take-locked") == "The recording take-2.wav cannot be read (Permission denied): \(locked.path)")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let cloned = try #require(readme.components(separatedBy: "**A voice cloned from a recording.**").dropFirst().first?.components(separatedBy: "`owner`, `language` and `model` are required").first)
        for needle in ["`reference.wav`", "`reference.txt`", "`reference = ", "`transcript = ", "`ref_audio`", "is not read in `voice.toml`"] {
            #expect(cloned.contains(needle), "the README's cloned voice does not say: \(needle)")
        }
    }
    /// A voice folder added in the Finder while Narrateur is open used to appear only after Apply or a new launch.
    /// The app now reads its folder again when it comes back to the front, and changes its list only when the disk did.
    @Test func aVoiceAddedWhileTheAppIsOpenIsFoundWhenTheFolderIsReadAgain() throws {
        let temp = try TempFolder()
        try temp.write("ryan/voice.toml", "name='Ryan'\nowner='me'\nlanguage='English'\nmodel='customvoice'\nvoice='ryan'")
        let listed = VoiceLibrary.load(from: temp.url)
        // Nothing changed on the disk: nothing to redraw.
        #expect(VoiceLibrary.reload(listed, from: temp.url) == nil)
        // A copied and renamed starter folder.
        try temp.write("serena/voice.toml", "name='Serena'\nowner='me'\nlanguage='English'\nmodel='customvoice'\nvoice='serena'")
        let added = try #require(VoiceLibrary.reload(listed, from: temp.url))
        #expect(added.map(\.id) == ["ryan", "serena"])
        #expect(added.allSatisfy { $0.unavailableReason == nil })
        #expect(VoiceLibrary.reload(added, from: temp.url) == nil)
        // A voice.toml edited, and a voice folder taken away, are seen the same way.
        try temp.write("ryan/voice.toml", "name='Ryan'\nowner='me'\nlanguage='French'\nmodel='customvoice'\nvoice='ryan'")
        let edited = try #require(VoiceLibrary.reload(added, from: temp.url))
        #expect(edited.first { $0.id == "ryan" }?.language == "French")
        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("serena"))
        #expect(try #require(VoiceLibrary.reload(edited, from: temp.url)).map(\.id) == ["ryan"])
        // Reading again writes nothing: an emptied folder stays empty until Apply or a new launch.
        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("ryan"))
        #expect(VoiceLibrary.reload(edited, from: temp.url) == [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.url.path).isEmpty)
        // The app asks for it each time it becomes active again, for the folder in use: AppModelTests drives the
        // model itself that way. The README says so.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("Narrateur reads the folder again each time you come back to it from another app"), "the README does not say when the folder is read")
    }
    @Test func malformedManifestsStayVisibleAndMissingFolderIsEmpty() throws {
        let temp = try TempFolder(); try temp.write("bad/voice.toml", "name = [invalid")
        #expect(VoiceLibrary.load(from: temp.url).first?.unavailableReason != nil)
        #expect(VoiceLibrary.load(from: temp.url.appendingPathComponent("absent")).isEmpty)
    }
}
