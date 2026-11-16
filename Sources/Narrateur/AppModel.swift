import AppKit
import Observation
import UniformTypeIdentifiers
import UserNotifications
import NarrateurCore

@MainActor @Observable final class AppModel {
    var preferences: AppPreferences
    var voices: [Voice] = []
    var selectedVoiceID: String?
    var book: BookDocument?
    var title = ""
    var author = ""
    var engine: EngineCommand?
    var engineProblem: String?
    var error: String?
    var notificationNote: String?
    var voicesFolderNote: String?
    /// The folder the voices are read from, as the launch or the last Apply resolved it.
    private(set) var voicesFolderURL: URL?
    var diskProgress = JobProgress()
    var jobs: [JobRecord] = []
    var showLog = false
    var showEngineSetup = false
    let runner = JobRunner()
    var isPreview = false
    var smokeDirectory: URL?
    private var smokeEngine: String?
    private var handledJob: UUID?
    private let defaults: UserDefaults
    /// The home folder that holds Narrateur's own voices folder. A test gives one of its own, so that nothing it does
    /// reaches the voices of the Mac it runs on.
    private let home: URL

    init(defaults: UserDefaults = .standard, preferences saved: AppPreferences? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.home = home
        preferences = saved ?? defaults.data(forKey: "Narrateur.preferences").flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? AppPreferences()
        // A smoke run works on its own fixture and must not write into the user's library.
        isPreview = CommandLine.arguments.contains("--smoke-directory")
        reloadSettings()
    }
    var active: Bool { runner.state.isActive }
    var selectedVoice: Voice? { voices.first { $0.id == selectedVoiceID } }
    var progress: JobProgress { runner.currentJobID != nil ? runner.progress : diskProgress }
    var result: URL? {
        if case .succeeded(let url) = runner.state { return url }
        return runner.currentJobID == nil ? diskProgress.result : nil
    }
    var disabledReason: String? {
        RenderReadiness.reason(hasBook: book != nil, chapters: book?.chapters.count ?? 0,
            voiceAvailable: book.map { VoiceSelection.available($0.spec.voice, folder: $0.folder) } ?? false,
            engineAvailable: engine != nil, active: active)
    }
    var voiceName: String { selectedVoice?.name ?? (book != nil ? "Book’s narrator" : "Choose a narrator") }
    var voiceDetail: String { selectedVoice.map { "\($0.owner) · \($0.language)" } ?? book.map { $0.spec.language } ?? "Add a voice folder in Settings" }
    var status: String { runner.currentJobID == nil ? (diskProgress.result == nil ? "Ready" : "Existing audiobook") : runner.state.label }
    var log: String { runner.currentJobID == nil ? book.map { ProgressReader.logTail($0.folder.appendingPathComponent("narrateur.log")) } ?? "" : runner.log }

    func savePreferences() {
        if !isPreview { defaults.set(try? JSONEncoder().encode(preferences), forKey: "Narrateur.preferences") }
        reloadSettings()
    }
    func reloadSettings() {
        // An empty or unusable field falls back to Narrateur's own folder; the settings say so.
        let resolved = VoicesFolder.resolve(preferences.voicesFolder, home: home)
        let folder = resolved.url
        voicesFolderNote = resolved.note
        voicesFolderURL = folder
        if !isPreview {
            // A first launch, or an empty folder, gets two voices to start with. Existing voices are never touched.
            do { try StarterVoices.installIfNeeded(in: folder) }
            catch { self.error = "The starter voices could not be written to \(folder.path): \(error.localizedDescription)" }
        }
        voices = VoiceLibrary.load(from: folder)
        selectVoiceAfterReading()
        do { engine = try EngineLocator.resolve(override: smokeEngine ?? preferences.engineOverride); engineProblem = nil }
        catch { engine = nil; engineProblem = error.localizedDescription }
    }
    /// Reads the voices folder in use again, as the disk holds it now: a voice folder added in the Finder is in the
    /// narrator menu when the app comes back to the front. Nothing is written, and nothing changes when the disk did not.
    func refreshVoices() {
        guard let folder = voicesFolderURL, let current = VoiceLibrary.reload(voices, from: folder) else { return }
        voices = current
        selectVoiceAfterReading()
    }
    private func selectVoiceAfterReading() {
        if let book { selectedVoiceID = VoiceSelection.match(book.spec.voice, folder: book.folder, voices: voices)?.id }
        else { selectedVoiceID = VoiceLibrary.preferred(voices, lastUsed: preferences.lastVoice, shown: selectedVoiceID)?.id }
    }
    func chooseBook() {
        guard !active else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a book"; panel.prompt = "Choose book"
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!, UTType(filenameExtension: "toml")!]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { openBook(url) }
    }
    func openBook(_ url: URL) {
        guard !active else { return }
        do {
            let loaded = try BookWorkspace.prepare(input: url, voice: selectedVoice, author: preferences.author)
            book = loaded; title = loaded.spec.title; author = loaded.spec.author
            selectedVoiceID = VoiceSelection.match(loaded.spec.voice, folder: loaded.folder, voices: voices)?.id
            runner.reset(); handledJob = nil; error = nil
            diskProgress = RenderJob(document: loaded).progress(since: nil)
        } catch { self.error = error.localizedDescription }
    }
    func selectVoice(_ voice: Voice) {
        guard !active, !isPreview, voice.id != selectedVoiceID else { return }
        if book != nil, diskProgress.completedCount > 0, !confirmNarratorChange(to: voice) { return }
        do {
            if let book { self.book = try BookWorkspace.updateVoice(voice, in: book); diskProgress = RenderJob(document: self.book!).progress(since: nil); runner.reset() }
            selectedVoiceID = voice.id; preferences.lastVoice = voice.id
            defaults.set(try? JSONEncoder().encode(preferences), forKey: "Narrateur.preferences")
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func confirmNarratorChange(to voice: Voice) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Change the narrator?"
        let count = diskProgress.completedCount
        alert.informativeText = "\(count) chapter\(count == 1 ? " is" : "s are") already rendered with \(voiceName). Rendering again with \(voice.name) will read every chapter anew; the current audiobook stays until then."
        alert.addButton(withTitle: "Change narrator")
        alert.addButton(withTitle: "Keep \(voiceName)")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func saveMetadata() {
        guard let book, !active, !isPreview else { return }
        guard title != book.spec.title || author != book.spec.author else { return }
        do { self.book = try BookWorkspace.updateMetadata(title: title, author: author, in: book); diskProgress = RenderJob(document: self.book!).progress(since: nil); runner.reset(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func render() {
        guard disabledReason == nil, let engine, !isPreview || smokeEngine != nil else { return }
        error = nil
        saveMetadata()
        guard error == nil, let book else { return }
        do {
            // Re-read source headings and settings immediately before a run.
            let refreshed = try BookWorkspace.load(book.configURL)
            guard !refreshed.chapters.isEmpty else { throw NarrateurError("No chapters found. Choose a book with chapter headings.") }
            self.book = refreshed
            let job = RenderJob(document: refreshed)
            try runner.start(job, command: engine)
            jobs.append(JobRecord(id: job.id, title: job.title, state: .running))
            if !isPreview {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        } catch { self.error = error.localizedDescription }
    }
    func jobChanged() {
        guard let id = runner.currentJobID else { return }
        if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].state = runner.state }
        guard !active, handledJob != id else { return }
        handledJob = id
        if case .failed(let message, _) = runner.state { error = message }
        if case .succeeded = runner.state, !isPreview {
            let content = UNMutableNotificationContent()
            content.title = "Your audiobook is ready"
            content.body = book?.spec.title ?? "Narrateur"; content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil)) { [weak self] failure in
                if failure != nil { Task { @MainActor in self?.notificationNote = "Audiobook ready. Notifications are unavailable; enable them in System Settings." } }
            }
        }
        if let smokeDirectory {
            try? "\(runner.state)\n".write(to: smokeDirectory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        }
    }
    func bootstrap() {
        let args = CommandLine.arguments
        func argument(_ key: String) -> String? { args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        if let path = argument("--smoke-directory") {
            isPreview = true; smokeDirectory = URL(fileURLWithPath: path)
            if let voices = argument("--smoke-voices") { preferences.voicesFolder = voices }
            smokeEngine = argument("--smoke-engine"); reloadSettings()
        }
        if engine == nil, !isPreview { showEngineSetup = true }
        if let path = argument("--open-book") { openBook(URL(fileURLWithPath: path)) }
        if smokeEngine != nil, isPreview, args.contains("--smoke-render") { render() }
    }
    /// Looks for the engine again; the setup sheet closes by itself once it is found.
    func recheckEngine() {
        reloadSettings()
        if engine != nil { showEngineSetup = false }
    }
    func reveal() { if let result { NSWorkspace.shared.activateFileViewerSelecting([result]) } }
    func play() { if let result, !NSWorkspace.shared.open(result) { error = "macOS could not open this audiobook. Use Open in Finder to choose a player." } }
}
