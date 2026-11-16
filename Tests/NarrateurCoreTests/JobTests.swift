import Foundation
import Testing
@testable import NarrateurCore
@MainActor struct JobTests {
    func fixture(_ script: String) throws -> (TempFolder, RenderJob, EngineCommand) {
        let temp = try TempFolder()
        try temp.write("book with spaces/story.md", "# Chapter 1 — One\nHello")
        let config = try temp.write("book with spaces/book.toml", BookTOML.encode(BookSpec(title: "Story", author: "A", language: "English", source: "story.md", voice: VoiceSettings(model: .customvoice, voice: "Ryan"))))
        let engine = try temp.write("bin/book-audio", "#!/bin/sh\n" + script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: engine.path)
        return try (temp, RenderJob(document: BookWorkspace.load(config)), EngineLocator.resolve(path: engine.deletingLastPathComponent().path, home: temp.url, project: temp.url))
    }
    func finished(_ runner: JobRunner) async throws {
        // Generous on purpose: on a busy Mac the first launch of a freshly written script can take seconds.
        for _ in 0..<400 { if !runner.state.isActive { return }; try await Task.sleep(for: .milliseconds(50)) }
        runner.cancel(); Issue.record("Job did not finish in twenty seconds")
    }
    @Test func argumentsEnvironmentLogPollAndSuccess() async throws {
        let (temp, job, command) = try fixture("""
        test "$1" = all || exit 2
        test -f "$2" || exit 2
        test -z "${BOOK_AUDIO_BACKEND+x}" || exit 4
        echo "input=$2"
        mkdir -p audio/chapters .book-audio/cache
        printf '%s\\n' '- duration: 12.0 s' '- retries: 0' > audio/chapters/01_one.md
        printf audio > .book-audio/cache/test.wav
        sleep 0.2
        printf audio > audio/Story.m4b
        printf report > audio/REPORT.md
        """)
        defer { _ = temp }
        let runner = JobRunner(pollInterval: 0.05)
        try runner.start(job, command: command, environment: ["PATH": "/usr/bin:/bin", "BOOK_AUDIO_BACKEND": "fake"])
        try await finished(runner)
        #expect(runner.state == .succeeded(job.document.outputURL))
        #expect(runner.progress.completedCount == 1); #expect(runner.progress.cachedUnits == 1)
        #expect(runner.log.contains(job.document.configURL.path))
    }
    @Test(arguments: [Int32(2), 3, 4]) func engineErrors(_ code: Int32) async throws {
        let (temp, job, command) = try fixture("echo 'loading noise'; echo 'book-audio: exact failure' >&2; exit \(code)")
        defer { _ = temp }
        let runner = JobRunner(); try runner.start(job, command: command); try await finished(runner)
        #expect(runner.state == .failed("book-audio: exact failure", code))
    }
    @Test func singleFlightCancelChildrenAndResume() async throws {
        let (temp, job, command) = try fixture("(trap '' TERM; sleep 2; echo survived > child-survived) &\nwait\n")
        let runner = JobRunner(pollInterval: 0.05)
        try runner.start(job, command: command)
        #expect(throws: (any Error).self) { try runner.start(job, command: command) }
        try await Task.sleep(for: .milliseconds(150)); runner.cancel(); try await finished(runner)
        #expect(runner.state == .cancelled)
        try await Task.sleep(for: .seconds(2.1))
        #expect(!FileManager.default.fileExists(atPath: job.document.folder.appendingPathComponent("child-survived").path))
        try "#!/bin/sh\necho 'book-audio: resumed' >&2\nexit 2\n".write(to: command.executable, atomically: false, encoding: .utf8)
        try runner.start(job, command: command); try await finished(runner)
        #expect(runner.state == .failed("book-audio: resumed", 2))
        _ = temp
    }
    @Test func successWithoutFreshResultIsFailure() async throws {
        let (temp, job, command) = try fixture("exit 0")
        try temp.write("book with spaces/audio/Story.m4b", "old"); try temp.write("book with spaces/audio/REPORT.md", "old")
        let runner = JobRunner(); try runner.start(job, command: command); try await finished(runner)
        if case .failed = runner.state {} else { Issue.record("Stale output accepted as success") }
    }
}
