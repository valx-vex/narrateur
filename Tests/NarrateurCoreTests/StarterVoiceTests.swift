import Foundation
import Testing
@testable import NarrateurCore

struct StarterVoiceTests {
    /// Preset speakers of the CustomVoice model, as listed in its public configuration.
    let presetSpeakers = ["serena", "vivian", "uncle_fu", "ryan", "aiden", "ono_anna", "sohee", "eric", "dylan"]
    func files(_ folder: URL) throws -> [String] {
        (try FileManager.default.subpathsOfDirectory(atPath: folder.path)).sorted()
    }
    @Test func missingFolderGetsTwoVoicesThatNeedNoAudioFile() throws {
        let temp = try TempFolder(), folder = temp.url.appendingPathComponent("Application Support/Narrateur/Voices")
        #expect(try StarterVoices.installIfNeeded(in: folder) == ["narrator-ryan", "narrator-warm"])
        #expect(try files(folder) == ["narrator-ryan", "narrator-ryan/voice.toml", "narrator-warm", "narrator-warm/voice.toml"])
        let voices = VoiceLibrary.load(from: folder)
        #expect(voices.map(\.id) == ["narrator-ryan", "narrator-warm"])
        #expect(voices.allSatisfy { $0.unavailableReason == nil && !$0.owner.isEmpty && $0.language == "English" })
        let preset = try #require(voices.first { $0.id == StarterVoices.presetID }).engineVoice()
        #expect(preset.model == .customvoice); #expect(preset.voice == "ryan"); #expect(preset.refAudio == nil); #expect(preset.instruct == nil)
        #expect(presetSpeakers.contains(try #require(preset.voice)))
        let designed = try #require(voices.first { $0.id == StarterVoices.designedID }).engineVoice()
        #expect(designed.model == .voicedesign); #expect(designed.refAudio == nil)
        #expect(designed.instruct == StarterVoices.designedDescription)
        #expect(StarterVoices.designedDescription.count > 60)
        // One download instead of two: a first launch starts on the preset voice.
        #expect(VoiceLibrary.preferred(voices, lastUsed: nil)?.id == StarterVoices.presetID)
    }
    @Test func emptyFolderIsFilledAndRepeatingChangesNothing() throws {
        let temp = try TempFolder(), folder = temp.url.appendingPathComponent("Voices")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try temp.write("Voices/notes.txt", "mine")
        #expect(try StarterVoices.installIfNeeded(in: folder).count == 2)
        let manifests = [StarterVoices.presetID, StarterVoices.designedID].map { folder.appendingPathComponent("\($0)/voice.toml") }
        let old = Date().addingTimeInterval(-3600)
        for url in manifests { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path) }
        let before = try manifests.map { try Data(contentsOf: $0) }
        let listing = try files(folder)
        #expect(try StarterVoices.installIfNeeded(in: folder).isEmpty)
        #expect(try manifests.map { try Data(contentsOf: $0) } == before)
        #expect(try files(folder) == listing)
        for url in manifests {
            let date = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            #expect(abs(date.timeIntervalSince(old)) < 2)
        }
        #expect(try String(contentsOf: folder.appendingPathComponent("notes.txt"), encoding: .utf8) == "mine")
    }
    @Test func aFolderThatAlreadyHoldsAVoiceIsLeftAlone() throws {
        // Even a voice that cannot be used yet is somebody's voice: nothing is added beside it.
        for manifest in ["name='Mine'\nowner='me'\nlanguage='English'\nmodel='customvoice'\nvoice='Ryan'", "name = [broken"] {
            let temp = try TempFolder()
            try temp.write("mine/voice.toml", manifest)
            #expect(try StarterVoices.installIfNeeded(in: temp.url).isEmpty)
            #expect(try files(temp.url) == ["mine", "mine/voice.toml"])
            #expect(try String(contentsOf: temp.url.appendingPathComponent("mine/voice.toml"), encoding: .utf8) == manifest)
        }
    }
    @Test func nothingIsEverOverwritten() throws {
        let temp = try TempFolder()
        // A file where a starter folder would go, and a folder of that name holding something else.
        try temp.write("narrator-ryan", "a file, not a folder")
        try temp.write("narrator-warm/reference.txt", "kept")
        #expect(try StarterVoices.installIfNeeded(in: temp.url) == ["narrator-warm"])
        #expect(try String(contentsOf: temp.url.appendingPathComponent("narrator-ryan"), encoding: .utf8) == "a file, not a folder")
        #expect(try String(contentsOf: temp.url.appendingPathComponent("narrator-warm/reference.txt"), encoding: .utf8) == "kept")
        #expect(VoiceLibrary.load(from: temp.url).map(\.id) == ["narrator-warm"])
    }
    @Test func aBookCanBePreparedWithEachStarterVoice() throws {
        let temp = try TempFolder(), folder = temp.url.appendingPathComponent("Voices")
        try StarterVoices.installIfNeeded(in: folder)
        for (index, voice) in VoiceLibrary.load(from: folder).enumerated() {
            let input = try temp.write("book\(index)/Fables.md", "# Two fables\n\n# Chapter 1 — One\nHello.\n\n# Chapter 2 — Two\nGoodbye.")
            let book = try BookWorkspace.prepare(input: input, voice: voice, author: "A reader")
            #expect(book.chapters.count == 2); #expect(book.spec.language == "English")
            #expect(VoiceSelection.available(book.spec.voice, folder: book.folder))
            #expect(VoiceSelection.match(book.spec.voice, folder: book.folder, voices: VoiceLibrary.load(from: folder))?.id == voice.id)
        }
    }
    @Test func engineSetupGivesTheTwoCommandsAndTheDownloadSize() {
        #expect(EngineSetup.commands == ["brew install ffmpeg uv", "uv tool install --python 3.12 git+https://github.com/valx-vex/book-audio"])
        #expect(EngineSetup.commands[1].hasSuffix(ProjectInfo.engineRepository))
        #expect(EngineSetup.downloadNote.contains("4.5 GB"))
        #expect(EngineSetup.downloadNote.contains("first render"))
        let reason = RenderReadiness.reason(hasBook: true, chapters: 1, voiceAvailable: true, engineAvailable: false, active: false)
        #expect(reason?.contains(EngineSetup.title) == true)
        #expect(EngineSetup.title == "Engine setup")
    }
    @Test func anEmptyOrUnusableVoicesFolderFallsBackToTheDefaultFolder() throws {
        let temp = try TempFolder(), home = temp.url.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let fallback = URL(fileURLWithPath: AppPreferences.defaultVoicesFolder(home: home), isDirectory: true)
        let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        // An emptied field, or a path that does not start at the top of the disk or at the home folder,
        // used to mean "the folder the app was started from". It now means Narrateur's own folder, even when
        // the path, read from the current folder, names a folder that exists: the current folder itself, or another.
        let existing = temp.url.appendingPathComponent("Existing Voices")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let fromHere = String(repeating: "../", count: here.pathComponents.count - 1) + existing.path.dropFirst()
        #expect(FileManager.default.fileExists(atPath: fromHere), "\(fromHere) is not a folder that exists, read from \(here.path)")
        for field in ["", "   ", "\n", "Voices", "./Voices", "../elsewhere", "~someone/Voices", ".", "./", fromHere] {
            let resolved = VoicesFolder.resolve(field, home: home)
            #expect(resolved.url.path == fallback.path, "“\(field)” gave \(resolved.url.path)")
            #expect(!resolved.url.standardizedFileURL.path.hasPrefix(here.path), "“\(field)” leads into the current folder")
            #expect(resolved.note?.contains(fallback.path) == true, "“\(field)”: \(resolved.note ?? "no note")")
        }
        // The starter voices then go to that folder, which the app may create.
        let empty = VoicesFolder.resolve("", home: home)
        if empty.url.path == fallback.path {
            #expect(try StarterVoices.installIfNeeded(in: empty.url) == [StarterVoices.presetID, StarterVoices.designedID])
            #expect(VoiceLibrary.load(from: fallback).map(\.id) == [StarterVoices.presetID, StarterVoices.designedID])
        }
        // A mistyped path used to be created, folder after folder, with two voices at the end of it.
        let mistyped = temp.url.appendingPathComponent("Documnets/Voices")
        let wrong = VoicesFolder.resolve(mistyped.path, home: home)
        #expect(wrong.url.path == fallback.path, "\(wrong.url.path)")
        #expect(wrong.note?.contains(mistyped.path) == true && wrong.note?.contains(fallback.path) == true, "\(wrong.note ?? "no note")")
        if wrong.url.path == fallback.path { _ = try StarterVoices.installIfNeeded(in: wrong.url) }
        #expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("Documnets").path), "the mistyped folder was created")
        // A file is not a folder.
        let file = try temp.write("voices.txt", "not a folder")
        #expect(VoicesFolder.resolve(file.path, home: home).url.path == fallback.path)
        #expect(VoicesFolder.resolve(file.path, home: home).note?.contains(file.path) == true)
    }
    @Test func aVoicesFolderThatExistsIsUsedAsItIs() throws {
        let temp = try TempFolder(), home = temp.url.appendingPathComponent("home")
        let mine = home.appendingPathComponent("My Voices")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        // A full path, a path from the home folder, spaces around: the folder that is there, and nothing to say.
        for field in [mine.path, "~/My Voices", "  ~/My Voices/ \n"] {
            let resolved = VoicesFolder.resolve(field, home: home)
            #expect(resolved.url.standardizedFileURL.path == mine.standardizedFileURL.path, "“\(field)” gave \(resolved.url.path)")
            #expect(resolved.note == nil)
        }
        // Narrateur's own folder is the one folder it creates: it is used before it exists, and nothing is said.
        let own = AppPreferences.defaultVoicesFolder(home: home)
        #expect(!FileManager.default.fileExists(atPath: own))
        for field in [own, "~/Library/Application Support/Narrateur/Voices"] {
            #expect(VoicesFolder.resolve(field, home: home).url.path == own); #expect(VoicesFolder.resolve(field, home: home).note == nil)
        }
        // A saved folder that is missing today (a disk that is not plugged in) is not forgotten: only the folder in use changes.
        var preferences = AppPreferences(); preferences.voicesFolder = "/Volumes/Not Plugged In/Voices"
        #expect(VoicesFolder.resolve(preferences.voicesFolder, home: home).url.path == own)
        #expect(preferences.voicesFolder == "/Volumes/Not Plugged In/Voices")
    }
    @Test func aVoiceGivenAsTheVoicesFolderSendsToTheFolderThatHoldsIt() throws {
        // The Choose… panel opens on the voices folder, where every folder is a voice. One picked by mistake became the
        // voices folder; holding no voice folder, it got the two starter voices written into it. A voice's own folder
        // (a voice.toml, and no voice in it), picked or typed, now sends to the folder that holds it, and says so.
        let temp = try TempFolder(), home = temp.url.appendingPathComponent("home"), folder = home.appendingPathComponent("My Voices")
        try StarterVoices.installIfNeeded(in: folder)
        let ryan = folder.appendingPathComponent(StarterVoices.presetID)
        for field in [ryan.path, ryan.path + "/", "~/My Voices/narrator-ryan"] {
            let resolved = VoicesFolder.resolve(field, home: home)
            #expect(resolved.url.standardizedFileURL.path == folder.standardizedFileURL.path, "“\(field)” gave \(resolved.url.path)")
            #expect(resolved.note == "“\(URL(fileURLWithPath: ryan.path).standardizedFileURL.path)” is a voice: it holds a voice.toml. Narrateur is using the folder that holds it: \(resolved.url.path)", "“\(field)”: \(resolved.note ?? "no note")")
        }
        // What Apply does next writes nothing in the voice, and the menu lists the voices of the folder.
        let resolved = VoicesFolder.resolve(ryan.path, home: home)
        #expect(try StarterVoices.installIfNeeded(in: resolved.url).isEmpty)
        #expect(try files(ryan) == ["voice.toml"])
        #expect(VoiceLibrary.load(from: resolved.url).map(\.id) == [StarterVoices.presetID, StarterVoices.designedID])
        // A folder of voices that also holds a voice.toml of its own stays the folder of voices.
        try temp.write("home/My Voices/voice.toml", "name = \"stray\"")
        #expect(VoicesFolder.resolve(folder.path, home: home).url.standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(VoicesFolder.resolve(folder.path, home: home).note == nil)
        // The README says it where it explains the field.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let line = try #require(try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8).components(separatedBy: "\n").first { $0.hasPrefix("- **Voices folder.**") })
        #expect(line.contains("If the field names a single voice"), "\(line)")
    }
    @Test func aMissingEngineErrorPointsToTheSetup() throws {
        let temp = try TempFolder()
        #expect { try EngineLocator.resolve(path: "", home: temp.url, project: nil) } throws: { error in
            error.localizedDescription == EngineSetup.notFound && EngineSetup.notFound.contains(EngineSetup.title)
        }
        // Inside the setup sheet the same failure is said without sending the reader back to the sheet.
        #expect(!EngineSetup.stillMissing.contains(EngineSetup.title))
        #expect(EngineSetup.stillMissing.contains("~/.local/bin"))
    }
    @Test func eachButtonOfTheSetupSheetCarriesAnIdentifier() throws {
        // A SwiftUI button's name (its title, or its accessibility label) lands in AXAttributedDescription, which
        // VoiceOver reads. SwiftUI declares neither AXTitle nor AXDescription, so System Events, which reads only the
        // attributes an element declares, shows it with no name and "button" as its description. An identifier is
        // declared: each button of the sheet carries one, so that a script can find it.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sheet = try String(contentsOf: root.appendingPathComponent("Sources/Narrateur/EngineSetupSheet.swift"), encoding: .utf8)
        func count(_ pattern: String) -> Int { (try? NSRegularExpression(pattern: pattern)).map { $0.numberOfMatches(in: sheet, range: NSRange(sheet.startIndex..., in: sheet)) } ?? -1 }
        // Three buttons are written (the Copy button once, shown for each command), each with its identifier.
        #expect(count("(?<![A-Za-z])Button\\(") == 3)
        #expect(count("\\.accessibilityIdentifier\\(") == 3)
        for identifier in ["\"engine-setup-copy-\\(index + 1)\"", "\"engine-setup-later\"", "\"engine-setup-check-again\""] {
            #expect(sheet.contains(".accessibilityIdentifier(\(identifier))"), "no identifier \(identifier)")
        }
        // The names VoiceOver reads stay: the Copy buttons say which command.
        #expect(sheet.contains(".accessibilityLabel(\"Copy command \\(index + 1)\")"))
    }
    @Test func theChooseButtonOpensOnTheVoicesFolderInUse() throws {
        // The panel of the Choose… button opened on the last folder a panel had shown. It opens on the voices folder in
        // use: the one the settings count the voices of, which the launch or the last Apply resolved.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        let settings = try source("Sources/Narrateur/SettingsView.swift")
        let choose = try #require(settings.components(separatedBy: "Button(\"Choose…\")").dropFirst().first?.components(separatedBy: "panel.runModal()").first)
        #expect(choose.contains("panel.directoryURL = model.voicesFolderURL"), "the panel is not told where to open")
        #expect(try source("Sources/Narrateur/AppModel.swift").contains("voicesFolderURL = folder"))
        let field = try #require(try source("README.md").components(separatedBy: "\n").first { $0.hasPrefix("- **Voices folder.**") })
        #expect(field.contains("opens a panel on the folder in use"), "\(field)")
    }
    @Test func inTheSettingsWindowAMissingEngineSendsToTheFieldAbove() throws {
        // The Settings window shows the failure under the field where the executable is set: there it says "above",
        // not "in Settings", which is where the reader already is.
        let line = EngineSetup.inSettings(EngineSetup.notFound)
        #expect(line == "book-audio was not found. Open \(EngineSetup.title) to install it, or set its executable above.", "\(line)")
        #expect(!line.contains("in Settings"))
        // Elsewhere the text stays as it was.
        #expect(EngineSetup.notFound == "book-audio was not found. Open Engine setup to install it, or set its executable in Settings.")
        // Another problem, such as an override that is not a program, is shown as it is.
        let other = "The engine override is not an executable file: /nowhere/book-audio"
        #expect(EngineSetup.inSettings(other) == other)
        // And the Settings window says it that way.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/Narrateur/SettingsView.swift"), encoding: .utf8)
        #expect(settings.contains("model.engineProblem.map(EngineSetup.inSettings)"), "SettingsView does not say it that way")
    }
}
