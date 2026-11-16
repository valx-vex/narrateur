import Foundation
public enum JobState: Equatable, Sendable {
    case idle, running, cancelling, cancelled
    case succeeded(URL)
    case failed(String, Int32)
    public var isActive: Bool { self == .running || self == .cancelling }
    public var label: String {
        switch self {
        case .idle: "Ready"
        case .running: "Rendering"
        case .cancelling: "Stopping…"
        case .cancelled: "Paused · ready to resume"
        case .succeeded: "Ready to listen"
        case .failed: "Needs attention"
        }
    }
}
public struct JobItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let complete: Bool
    public let duration: Double?
    public let warnings: Int
}
public struct JobProgress: Equatable, Sendable {
    public var items: [JobItem] = []
    public var cachedUnits = 0
    public var result: URL?
    public var completedCount: Int { items.filter(\.complete).count }
    public init(items: [JobItem] = [], cachedUnits: Int = 0, result: URL? = nil) { self.items = items; self.cachedUnits = cachedUnits; self.result = result }
}
public protocol Job: Sendable {
    var id: UUID { get }
    var title: String { get }
    var arguments: [String] { get }
    var workingDirectory: URL { get }
    var logURL: URL { get }
    func progress(since: Date?) -> JobProgress
}
public struct RenderJob: Job {
    public let id = UUID()
    public let document: BookDocument
    public init(document: BookDocument) { self.document = document }
    public var title: String { document.spec.title }
    public var arguments: [String] { ["all", document.configURL.path] }
    public var workingDirectory: URL { document.folder }
    public var logURL: URL { document.folder.appendingPathComponent("narrateur.log") }
    public func progress(since: Date?) -> JobProgress {
        let p = ProgressReader.read(document: document, since: since)
        return JobProgress(items: p.chapters.map { JobItem(id: String($0.chapter.number), title: $0.chapter.title.isEmpty ? "Chapter \($0.chapter.number)" : $0.chapter.title, complete: $0.isComplete, duration: $0.duration, warnings: $0.warningCount) }, cachedUnits: p.cachedClips, result: p.output)
    }
}
public struct JobRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public var state: JobState
    public init(id: UUID, title: String, state: JobState) { self.id = id; self.title = title; self.state = state }
}
