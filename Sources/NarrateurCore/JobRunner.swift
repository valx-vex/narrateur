import Foundation
import Observation
import Darwin

/// One process group at a time, no shell interpolation, no pipe backpressure.
/// The generic job owns its disk projection; the runner owns lifecycle, logging and cancellation.
@MainActor @Observable public final class JobRunner {
    public private(set) var state: JobState = .idle
    public private(set) var progress = JobProgress()
    public private(set) var log = ""
    public private(set) var currentJobID: UUID?
    @ObservationIgnored private var pid: pid_t = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var job: (any Job)?
    @ObservationIgnored private var started = Date.distantPast
    @ObservationIgnored private var cancelledAt: Date?
    @ObservationIgnored private var logStart: UInt64 = 0
    @ObservationIgnored private let pollInterval: TimeInterval
    public init(pollInterval: TimeInterval = 2) { self.pollInterval = max(0.05, pollInterval) }
    public func start(_ job: any Job, command: EngineCommand, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard !state.isActive else { throw NarrateurError("A job is already running. Stop it before starting another.") }
        let fd = Darwin.open(job.logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { throw NarrateurError("Cannot open narrateur.log: \(String(cString: strerror(errno)))") }
        defer { Darwin.close(fd) }
        logStart = UInt64(max(0, lseek(fd, 0, SEEK_END)))
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, fd, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fd, STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, job.workingDirectory.path)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let args = [command.executable.path] + command.prefixArguments + job.arguments
        let env = command.environment(environment).map { "\($0.key)=\($0.value)" }
        let argv = args.map { strdup($0) } + [nil], envp = env.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        let startTime = Date()
        let result = posix_spawn(&child, command.executable.path, &actions, &attributes, argv, envp)
        guard result == 0 else { throw NarrateurError("Could not start book-audio: \(String(cString: strerror(result)))") }
        self.job = job; pid = child; started = startTime; currentJobID = job.id; cancelledAt = nil
        state = .running; log = ""; progress = job.progress(since: started)
        task = Task { [weak self] in
            var nextPoll = Date.distantPast
            var reapedStatus: Int32?
            while let self, self.state.isActive {
                if Date() >= nextPoll { self.refresh(); nextPoll = Date().addingTimeInterval(self.pollInterval) }
                if reapedStatus == nil {
                    var status: Int32 = 0
                    let waited = waitpid(child, &status, WNOHANG)
                    if waited == child { reapedStatus = status }
                    else if waited < 0 && errno != EINTR { reapedStatus = 1 << 8 }
                }
                if let cancelled = self.cancelledAt {
                    if Date().timeIntervalSince(cancelled) >= 0.5 {
                        // Descendants may outlive the leader; always kill the entire owned group.
                        kill(-child, SIGKILL)
                        if reapedStatus != nil { self.refresh(); self.state = .cancelled; self.pid = 0; break }
                    }
                } else if let status = reapedStatus {
                    self.finish(status: status); break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    public func reset() {
        guard !state.isActive else { return }
        task?.cancel(); task = nil; job = nil; currentJobID = nil
        state = .idle; progress = JobProgress(); log = ""
    }
    public func cancel() {
        guard state == .running, pid > 0 else { return }
        state = .cancelling; cancelledAt = Date(); kill(-pid, SIGTERM)
    }
    /// Called on app termination: don't leave the model or an ffmpeg child running.
    public func shutdown() {
        if pid > 0 { kill(-pid, SIGKILL); var status: Int32 = 0; _ = waitpid(pid, &status, 0); pid = 0 }
        task?.cancel(); task = nil
        if state.isActive { state = .cancelled }
    }
    private func refresh() {
        guard let job else { return }
        progress = job.progress(since: started)
        guard let handle = try? FileHandle(forReadingFrom: job.logURL) else { return }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: max(logStart, end > 16_384 ? end - 16_384 : 0))
        log = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }
    private func finish(status: Int32) {
        refresh(); pid = 0
        let signal = status & 0x7f
        let code = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        if code == 0, let result = progress.result { state = .succeeded(result) }
        else {
            let error = log.components(separatedBy: .newlines).last { $0.hasPrefix("book-audio: ") }
            let fallback = code == 0 ? "The engine finished without a new audiobook and report. Open the log for details." : "book-audio stopped (exit \(code)). Open the log for details."
            state = .failed(error ?? fallback, code)
        }
    }
}
