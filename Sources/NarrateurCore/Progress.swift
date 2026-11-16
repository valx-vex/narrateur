import Foundation
public struct ChapterProgress: Identifiable, Equatable, Sendable {
    public let chapter: Chapter
    public let duration: Double?
    public let warningCount: Int
    public let retries: Int
    public var id: Int { chapter.id }
    public var isComplete: Bool { duration != nil }
}
public struct BookProgress: Equatable, Sendable {
    public var chapters: [ChapterProgress] = []
    public var cachedClips: Int = 0
    public var output: URL?
    public var completedCount: Int { chapters.filter(\.isComplete).count }
    public init(chapters: [ChapterProgress] = [], cachedClips: Int = 0, output: URL? = nil) { self.chapters = chapters; self.cachedClips = cachedClips; self.output = output }
}
public enum ProgressReader {
    public static func read(document: BookDocument, since: Date? = nil) -> BookProgress {
        // Read current attributes on every poll; a loaded document can outlive an external edit.
        var inputs = [document.configURL, document.sourceURL]
        if let reference = document.spec.voice.refAudio { inputs.append(resolvePath(reference, relativeTo: document.folder)) }
        if let cover = document.coverURL { inputs.append(cover) }
        let inputDate = inputs.map { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantFuture
        }.max() ?? .distantPast
        let earliest = max(inputDate, since ?? .distantPast)
        func recentFile(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]), values.isRegularFile == true else { return false }
            return (values.contentModificationDate ?? .distantPast) >= earliest
        }
        let chapters = document.chapters.map { chapter in
            let url = document.folder.appendingPathComponent("audio/chapters/\(chapter.slug).md")
            let report = recentFile(url) ? ((try? String(contentsOf: url, encoding: .utf8)) ?? "") : ""
            let lines = report.components(separatedBy: .newlines)
            func number(_ prefix: String) -> Double? {
                lines.first(where: { $0.hasPrefix(prefix) }).flatMap { Double($0.dropFirst(prefix.count).split(separator: " ").first ?? "") }
            }
            let duration = number("- duration: ").flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            return ChapterProgress(chapter: chapter, duration: duration, warningCount: lines.filter { $0.hasPrefix("- WARNING:") }.count, retries: Int(number("- retries: ") ?? 0))
        }
        let cache = document.folder.appendingPathComponent(".book-audio/cache")
        let clips = ((try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.isRegularFileKey])) ?? []).filter { $0.pathExtension == "wav" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.count
        let report = document.folder.appendingPathComponent("audio/REPORT.md")
        let output = recentFile(document.outputURL) && recentFile(report) && ((try? document.outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 ? document.outputURL : nil
        return BookProgress(chapters: chapters, cachedClips: clips, output: output)
    }
    public static func logTail(_ url: URL, bytes: Int = 16_384) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > UInt64(bytes) ? end - UInt64(bytes) : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }
}
