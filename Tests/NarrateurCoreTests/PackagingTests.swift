import Foundation
import Testing
import AVFoundation
@testable import NarrateurCore
struct PackagingTests {
    var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    @Test func bundleIdentityAndBundledFonts() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("assets/Narrateur-Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["CFBundleIdentifier"] as? String == "com.valx.valxos.narrateur")
        #expect(plist["CFBundleName"] as? String == "Narrateur")
        #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
        #expect(plist["CFBundleExecutable"] as? String == "Narrateur")
        for name in ["SpaceGrotesk", "JetBrainsMono"] {
            let font = try Data(contentsOf: root.appendingPathComponent("assets/Fonts/\(name).ttf"))
            #expect(Array(font.prefix(4)) == [0, 1, 0, 0])
            #expect(try String(contentsOf: root.appendingPathComponent("assets/Fonts/\(name)-OFL.txt"), encoding: .utf8).contains("SIL OPEN FONT LICENSE"))
        }
        let icon = try Data(contentsOf: root.appendingPathComponent("assets/AppIcon.icns"))
        #expect(String(decoding: icon.prefix(4), as: UTF8.self) == "icns")
    }
    @Test func aboutCarriesVersionLicenseAddressAndDedication() throws {
        #expect(AboutInfo.dedication == "Finished with love for Patricia and Ocean.")
        #expect(AboutInfo.creditLines.last == AboutInfo.dedication)
        #expect(AboutInfo.creditLines.filter { $0 == AboutInfo.dedication }.count == 1)
        // The authors sign: who built the app, and who finished it. The dedication has its own line, after them.
        #expect(AboutInfo.creditLines.first == "A voice for the books of the table.")
        let credit = try #require(AboutInfo.creditLines.firstIndex(of: "Built by HAL and Fable with Valentin · VALX OS"))
        let dedication = try #require(AboutInfo.creditLines.firstIndex(of: AboutInfo.dedication))
        #expect(credit < dedication)
        #expect(AboutInfo.creditLines.filter { $0.hasPrefix("Built by") }.count == 1)
        #expect(AboutInfo.creditLines.contains { $0.contains("MIT License") })
        #expect(AboutInfo.creditLines.contains(ProjectInfo.repository))
        #expect(ProjectInfo.repository == "https://github.com/valx-vex/narrateur")
        #expect(AboutInfo.name == "VALX OS Narrateur")
        // The version is written once, in the bundle's Info.plist; the panel and the release script both read it there.
        let data = try Data(contentsOf: root.appendingPathComponent("assets/Narrateur-Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(ProjectInfo.version(plist) == "1.0.0")
        #expect(ProjectInfo.version(nil) == "development build")
        #expect(plist["NSHumanReadableCopyright"] as? String == "Copyright © 2026 Valentin Passera and the valx table. MIT License.")
        let sources = try String(contentsOf: root.appendingPathComponent("Sources/Narrateur/NarrateurApp.swift"), encoding: .utf8)
        #expect(!sources.contains("applicationVersion: \"1"), "the About panel must not carry its own version number")
    }
    @Test func licenseAndThirdPartyNotices() throws {
        func text(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        let license = try text("LICENSE")
        #expect(license.hasPrefix("MIT License\n\nCopyright (c) 2026 Valentin Passera and the valx table\n"))
        #expect(license.contains("Permission is hereby granted, free of charge")); #expect(license.contains("WITHOUT WARRANTY OF ANY KIND"))
        let notices = try text("THIRD_PARTY.md")
        // Every bundled font is named with the copyright line of its own license file.
        for name in ["SpaceGrotesk", "JetBrainsMono"] {
            let copyright = try #require(try text("assets/Fonts/\(name)-OFL.txt").components(separatedBy: .newlines).first)
            #expect(copyright.hasPrefix("Copyright ")); #expect(notices.contains(copyright)); #expect(notices.contains("assets/Fonts/\(name)-OFL.txt"))
        }
        for needle in ["SIL Open Font License", "Qwen3-TTS", "Apache-2.0", "Hugging Face", "ffmpeg", ProjectInfo.engineRepository] { #expect(notices.contains(needle), "THIRD_PARTY.md does not mention \(needle)") }
        // The license travels inside the app, next to the fonts' own.
        let build = try text("scripts/build-app.sh")
        #expect(build.contains("cp LICENSE THIRD_PARTY.md \"$APP/Contents/Resources/\""))
    }
    func run(_ script: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent(script).path] + arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
    @Test func releaseBuildsBesideTheSourcesAndNeverInstalls() throws {
        func text(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        let release = try text("scripts/release.sh")
        #expect(!release.contains("Applications"), "release.sh must not know the install folder")
        #expect(release.contains("scripts/build-app.sh --output build/release"))
        // One place for the version: the bundle's Info.plist.
        #expect(release.contains("CFBundleShortVersionString")); #expect(!release.contains("1.0.0"))
        #expect(release.contains("Narrateur-$VERSION-macos-arm64.zip")); #expect(release.contains("shasum -a 256"))
        // With --output, build-app.sh stops before the part that installs.
        let build = try text("scripts/build-app.sh")
        let stop = try #require(build.range(of: "if [[ -n \"$OUTPUT\" ]]; then echo \"Built $APP\"; exit 0; fi"))
        let install = try #require(build.range(of: "INSTALL=\"$HOME/Applications/Narrateur.app\""))
        #expect(stop.upperBound < install.lowerBound)
        // A wrong option stops at once, before anything is built or installed.
        for arguments in [["--bogus"], ["--output"]] {
            let result = try run("scripts/build-app.sh", arguments)
            #expect(result.status == 2, "\(arguments): \(result.output)")
        }
        #expect(try run("scripts/release.sh", ["unexpected"]).status == 2)
    }
    @Test func readmeSaysWhatTheAppSays() throws {
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        // The two install lines, the addresses and the voices folder are the ones the app itself uses.
        for command in EngineSetup.commands { #expect(readme.contains("\n\(command)\n"), "README lacks the line: \(command)") }
        #expect(readme.contains(ProjectInfo.repository)); #expect(readme.contains(ProjectInfo.engineRepository))
        #expect(readme.contains("~/Library/Application Support/Narrateur/Voices"))
        #expect(AppPreferences.defaultVoicesFolder(home: URL(fileURLWithPath: "/h")) == "/h/Library/Application Support/Narrateur/Voices")
        for id in [StarterVoices.presetID, StarterVoices.designedID] { #expect(readme.contains(id)) }
        // What the app does with an empty or mistyped "Voices folder" field is said where the field is described.
        let field = try #require(readme.components(separatedBy: "\n").first { $0.hasPrefix("- **Voices folder.**") })
        #expect(field.contains("empty") && field.contains("existing folder") && field.contains("`~/Library/Application Support/Narrateur/Voices`"), "\(field)")
        // The nine preset voices and the ten languages are the ones the app checks, as the engine does.
        #expect(EngineRules.presetSpeakers.sorted() == ["aiden", "dylan", "eric", "ono_anna", "ryan", "serena", "sohee", "uncle_fu", "vivian"])
        for speaker in EngineRules.presetSpeakers { #expect(readme.contains("`\(speaker)`"), "README does not list \(speaker)") }
        #expect(EngineRules.languages == ["Chinese", "English", "French", "German", "Italian", "Japanese", "Korean", "Portuguese", "Russian", "Spanish"])
        let languages = try #require(readme.components(separatedBy: "\n").first { $0.hasPrefix("`language` is one of") }, "README does not list the languages")
        for language in EngineRules.languages + ["auto"] { #expect(languages.contains("`\(language)`"), "README does not list \(language)") }
        // First opening of an app that is not notarized: both roads, the old one and the one since macOS 15.
        #expect(readme.contains("Open Anyway")); #expect(readme.contains("Privacy & Security")); #expect(readme.contains("macOS 14"))
        #expect(readme.contains("Narrateur-<version>-macos-arm64.zip")); #expect(readme.contains("scripts/release.sh"))
        // The heading forms the README promises are read by the app.
        for heading in ["# Chapter 1 — The North Wind and the Sun", "# Chapter 1 - Title", "# Chapter 1: Title", "# Chapter 1. Title", "# Chapter 11"] {
            #expect(readme.contains("`\(heading)`") || readme.contains("\n\(heading)\n"), "README does not show \(heading)")
            #expect(try ChapterIndex.parse(heading + "\n").count == 1)
        }
        // And the README says which near misses are not chapters; the app refuses each of them.
        for heading in ["# Chapter 1.5 Title", "# Chapter Three", "# Chapter 3 Title"] {
            #expect(readme.contains("`\(heading)`"), "README does not show \(heading)")
            #expect(throws: NarrateurError.self) { try ChapterIndex.parse(heading + "\n") }
        }
        #expect(readme.contains("Two chapters cannot have the same number"))
        // The dedication closes the page, and nothing in it names a place on the machine it was written on.
        let last = readme.components(separatedBy: .newlines).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(last == AboutInfo.dedication)
        #expect(!readme.contains("/" + "Users/"), "README names a personal folder")
    }
    @Test func readmeSaysWhatToDoWhenTerminalDoesNotFindTheEngine() throws {
        // `uv tool install` puts book-audio in ~/.local/bin, where the Terminal of a new account does not look:
        // "book-audio doctor" answers "command not found" there, though the app finds the engine.
        let lines = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8).components(separatedBy: "\n")
        // Step 2 sends the reader to `book-audio doctor`: the same paragraph says what to do when Terminal does not find it.
        let step = try #require(lines.first { $0.contains("`book-audio doctor` tells you") })
        for needle in ["command not found: book-audio", "`uv tool update-shell`", "new Terminal window"] { #expect(step.contains(needle), "step 2 does not say: \(needle)") }
        // The list of troubles has its own entry, with the form of the command that always works.
        let entry = try #require(lines.first { $0.hasPrefix("- **Terminal answers `command not found: book-audio`.**") })
        for needle in ["`uv tool update-shell`", "new Terminal window", "`~/.local/bin/book-audio doctor`"] { #expect(entry.contains(needle), "the entry does not say: \(needle)") }
        // Where the reader is already lost (the sheet keeps coming back), the command is given with its whole path.
        let sheet = try #require(lines.first { $0.hasPrefix("- **The Engine setup sheet keeps coming back.**") })
        #expect(sheet.contains("`~/.local/bin/book-audio doctor`"))
        // The README never sends to `book-audio doctor` before it has said what to do when Terminal does not find it.
        let firstUse = try #require(lines.firstIndex { $0.contains("book-audio doctor`") }), firstHelp = try #require(lines.firstIndex { $0.contains("uv tool update-shell") })
        #expect(firstHelp <= firstUse)
    }
    @Test func theSheetAndTheReadmeSayThePathWarningOfUvCanBeIgnored() throws {
        // On a new Mac, `uv tool install` ends with a warning: ~/.local/bin is not on your PATH, run
        // `uv tool update-shell`. The app finds the engine there all the same: both places say the warning can be
        // ignored, and what the command is for.
        for needle in ["~/.local/bin", "not on your PATH", "ignore that warning", "uv tool update-shell", "only needed to type book-audio in Terminal"] {
            #expect(EngineSetup.pathNote.contains(needle), "the sheet does not say: \(needle)")
        }
        let sheet = try String(contentsOf: root.appendingPathComponent("Sources/Narrateur/EngineSetupSheet.swift"), encoding: .utf8)
        #expect(sheet.contains("Text(EngineSetup.pathNote)"), "the sheet does not show the note")
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let install = try #require(readme.components(separatedBy: "## 2. Install the engine").dropFirst().first?.components(separatedBy: "\n## ").first)
        let paragraph = install.components(separatedBy: "\n\n").first { $0.contains("not on your PATH") } ?? ""
        for needle in ["`~/.local/bin`", "ignore that warning", "`uv tool update-shell`", "only needed to type `book-audio` in Terminal"] {
            #expect(paragraph.contains(needle), "the README's step 2 does not say: \(needle)")
        }
    }
    @Test func editingSettingsInvalidatesOldAudio() throws {
        let temp = try TempFolder()
        try temp.write("story.md", "# Chapter 1 — One\nHello")
        let config = try temp.write("book.toml", BookTOML.encode(BookSpec(title: "Story", author: "A", language: "English", source: "story.md", voice: VoiceSettings(model: .customvoice, voice: "Ryan"))))
        let book = try BookWorkspace.load(config)
        try temp.write("audio/chapters/01_one.md", "- duration: 12.0 s\n")
        let audio = try temp.write("audio/Story.m4b", "audio")
        let report = try temp.write("audio/REPORT.md", "report")
        #expect(ProgressReader.read(document: book).output == audio)
        let old = Date().addingTimeInterval(-100)
        for path in [audio, report, temp.url.appendingPathComponent("audio/chapters/01_one.md")] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path.path)
        }
        let changed = try BookWorkspace.updateVoice(VoiceSettings(model: .voicedesign, instruct: "Another voice"), in: book)
        #expect(ProgressReader.read(document: changed).output == nil)
        #expect(ProgressReader.read(document: changed).completedCount == 0)
    }
    @Test func changedSourceOrReferenceInvalidatesReports() throws {
        for changedPath in ["story.md", "reference.wav"] {
            let temp = try TempFolder()
            try temp.write("story.md", "# Chapter 1 — One\nHello")
            try temp.write("reference.wav", "reference")
            let config = try temp.write("book.toml", BookTOML.encode(BookSpec(title: "Story", author: "A", language: "English", source: "story.md", voice: VoiceSettings(model: .base, refAudio: "reference.wav", refText: "Hello"))))
            let book = try BookWorkspace.load(config)
            try temp.write("audio/chapters/01_one.md", "- duration: 12.0 s\n")
            try temp.write("audio/Story.m4b", "audio")
            try temp.write("audio/REPORT.md", "report")
            #expect(ProgressReader.read(document: book).completedCount == 1)
            #expect(ProgressReader.read(document: book).output != nil)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: temp.url.appendingPathComponent(changedPath).path)
            #expect(ProgressReader.read(document: book).completedCount == 0)
            #expect(ProgressReader.read(document: book).output == nil)
        }
    }
    @Test @MainActor func syntheticSmokeFixtureThroughRunner() async throws {
        let temp = try TempFolder()
        let setup = Process()
        setup.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        setup.arguments = [root.appendingPathComponent("scripts/make-smoke-fixture.py").path, temp.url.path]
        try setup.run(); setup.waitUntilExit()
        #expect(setup.terminationStatus == 0)
        let document = try BookWorkspace.load(temp.url.appendingPathComponent("book.toml"))
        let voices = VoiceLibrary.load(from: temp.url.appendingPathComponent("voices"))
        #expect(VoiceSelection.match(document.spec.voice, folder: document.folder, voices: voices)?.id == "house")
        let command = try EngineLocator.resolve(path: temp.url.appendingPathComponent("bin").path, home: temp.url, project: temp.url)
        let runner = JobRunner(pollInterval: 0.05)
        defer { runner.shutdown() }
        try runner.start(RenderJob(document: document), command: command, environment: ["PATH": "/usr/bin:/bin", "BOOK_AUDIO_BACKEND": "must-be-removed"])
        for _ in 0..<200 {
            if !runner.state.isActive { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(runner.state == .succeeded(document.outputURL), "Fake smoke log: \(runner.log)")
        #expect(runner.progress.completedCount == 10)
        #expect(runner.progress.cachedUnits == 12)
        let result = try #require(runner.progress.result)
        let duration = try await AVURLAsset(url: result).load(.duration)
        #expect(duration.seconds >= 0.9 && duration.seconds <= 1.2)
    }
}
