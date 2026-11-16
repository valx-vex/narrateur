import Foundation
import Testing
@testable import NarrateurCore
struct EngineTests {
    func book(_ temp: TempFolder) throws -> BookDocument {
        try temp.write("story.md", (1...4).map { "# Chapter \($0) — Part \($0)\nHello." }.joined(separator: "\n"))
        return try BookWorkspace.load(temp.write("book.toml", BookTOML.encode(BookSpec(title: "A:B/Story", author: "A", language: "English", source: "story.md", voice: VoiceSettings(model: .customvoice, voice: "Ryan")))))
    }
    @Test func threeReportsTwelveClipsAndOutput() throws {
        let temp = try TempFolder(), doc = try book(temp)
        for chapter in doc.chapters.prefix(3) { try temp.write("audio/chapters/\(chapter.slug).md", "# Chapter \(chapter.number)\n- duration: 42.5 s\n- retries: 2\n- WARNING: short clip\n") }
        for n in 1...12 { try temp.write(".book-audio/cache/\(n).wav", "audio") }
        try temp.write(".book-audio/cache/12.warning", "warning")
        try temp.write("audio/chapters/99_unrelated.md", "- duration: 10 s")
        try temp.write("audio/A-B-Story.m4b", "audio"); try temp.write("audio/REPORT.md", "report")
        let progress = ProgressReader.read(document: doc)
        #expect(progress.completedCount == 3); #expect(progress.cachedClips == 12)
        #expect(progress.chapters[0].duration == 42.5); #expect(progress.chapters[0].warningCount == 1)
        #expect(progress.chapters[0].retries == 2); #expect(progress.output == doc.outputURL)
        #expect(ProgressReader.read(document: doc, since: Date().addingTimeInterval(60)).completedCount == 0)
        #expect(ProgressReader.read(document: doc, since: Date().addingTimeInterval(60)).output == nil)
    }
    @Test func emptyAndPartialReportsNeverInventProgress() throws {
        let temp = try TempFolder(), doc = try book(temp)
        try temp.write("audio/chapters/01_part-1.md", "# Chapter 1\n- duration:")
        try temp.write("audio/unrelated.m4b", "audio")
        #expect(ProgressReader.read(document: doc).completedCount == 0)
        #expect(ProgressReader.read(document: doc).output == nil)
    }
    func executable(_ temp: TempFolder, _ path: String) throws -> URL {
        let url = try temp.write(path, "#!/bin/sh\nexit 0\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path); return url
    }
    @Test func engineResolutionOrderAndEnvironment() throws {
        let temp = try TempFolder()
        let pathBin = try executable(temp, "bin/book-audio"), local = try executable(temp, ".local/bin/book-audio")
        let command = try EngineLocator.resolve(path: temp.url.appendingPathComponent("bin").path, home: temp.url, project: nil)
        #expect(command.executable == pathBin)
        #expect(try EngineLocator.resolve(path: "", home: temp.url, project: nil).executable == local)
        #expect(try EngineLocator.resolve(override: local.path, path: pathBin.deletingLastPathComponent().path, home: temp.url, project: nil).executable == local)
        let env = command.environment(["BOOK_AUDIO_BACKEND": "fake", "PATH": "/usr/bin"])
        #expect(env["BOOK_AUDIO_BACKEND"] == nil); #expect(env["PATH"]!.contains("/opt/homebrew/bin"))
    }
    @Test func installedEngineWinsOverDeveloperProject() throws {
        let temp = try TempFolder(), local = try executable(temp, ".local/bin/book-audio")
        _ = try executable(temp, ".local/bin/uv")
        try temp.write("project/pyproject.toml", "[project]\nname='book-audio'")
        let command = try EngineLocator.resolve(path: "", home: temp.url, project: temp.url.appendingPathComponent("project"))
        #expect(command.executable == local); #expect(command.prefixArguments.isEmpty)
    }
    @Test func developerProjectAndInvalidOverride() throws {
        let temp = try TempFolder(), uv = try executable(temp, ".local/bin/uv")
        try temp.write("project/pyproject.toml", "[project]\nname='book-audio'")
        let project = temp.url.appendingPathComponent("project")
        let command = try EngineLocator.resolve(path: "", home: temp.url, project: project)
        #expect(command.executable == uv)
        #expect(command.prefixArguments == ["run", "--project", project.path, "book-audio"])
        #expect(throws: (any Error).self) { try EngineLocator.resolve(override: "/absent/engine", path: "", home: temp.url, project: project) }
        #expect(throws: (any Error).self) { try EngineLocator.resolve(path: "", home: temp.url, project: temp.url.appendingPathComponent("absent")) }
    }
    @Test func anEngineInstalledAsALinkIsFound() throws {
        // `uv tool install` puts a symbolic link in ~/.local/bin, pointing into its own tools folder.
        let temp = try TempFolder(), real = try executable(temp, "tools/book-audio/bin/book-audio")
        let link = temp.url.appendingPathComponent(".local/bin/book-audio")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(try EngineLocator.resolve(path: "", home: temp.url, project: nil).executable.path == link.path)
        #expect(try EngineLocator.resolve(override: link.path, path: "", home: temp.url, project: nil).executable.path == link.path)
        // A link to nothing, or to a folder, is not an engine.
        try FileManager.default.removeItem(at: real)
        #expect(throws: (any Error).self) { try EngineLocator.resolve(path: "", home: temp.url, project: nil) }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temp.url.appendingPathComponent("tools"))
        #expect(throws: (any Error).self) { try EngineLocator.resolve(path: "", home: temp.url, project: nil) }
    }
    @Test func noEngineAnywhereIsAnErrorEvenWithUv() throws {
        // uv alone is not an engine: without an install or a named developer project there is nothing to run.
        let temp = try TempFolder()
        _ = try executable(temp, ".local/bin/uv")
        #expect(throws: (any Error).self) { try EngineLocator.resolve(path: "", home: temp.url, project: nil) }
    }
    @Test func developerProjectComesOnlyFromItsVariable() throws {
        let temp = try TempFolder()
        #expect(EngineLocator.developerProject([:]) == nil)
        #expect(EngineLocator.developerProject(["BOOK_AUDIO_PROJECT": "  "]) == nil)
        #expect(EngineLocator.developerProject(["BOOK_AUDIO_PROJECT": " " + temp.url.path + "\n"])?.path == resolvePath(temp.url.path, relativeTo: temp.url).path)
    }
    @Test func sourcesCarryNoPersonalPath() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        #expect(files.count >= 15)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            // Written in two pieces so that this file passes the same check.
            let needle = "/" + "Users/"
            #expect(!text.contains(needle), "\(file.lastPathComponent) contains \(needle)")
        }
    }
}
