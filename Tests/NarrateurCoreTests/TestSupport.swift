import Foundation
final class TempFolder {
    let url: URL
    init() throws { url = FileManager.default.temporaryDirectory.appendingPathComponent("narrateur-test-\(UUID())"); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
    @discardableResult func write(_ path: String, _ content: String = "") throws -> URL {
        let target = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: target, atomically: true, encoding: .utf8); return target
    }
}
