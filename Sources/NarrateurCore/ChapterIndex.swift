import Foundation

public struct Chapter: Identifiable, Equatable, Sendable {
    public let number: Int
    public let title: String
    public var id: Int { number }
    public var slug: String {
        let clean = title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(format: "%02d_%@", number, clean.isEmpty ? "chapter-\(number)" : clean)
    }
}
public enum ChapterIndex {
    public static func title(_ text: String, fallback: String) -> String {
        text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") }).map { String($0.dropFirst(2)) } ?? fallback
    }
    // The engine reads a book with Python's regular expressions. Three of Python's notions are spelled out here,
    // so that Apple's library reads the same characters the same way: a space (`\s`), a word character (`\w`),
    // and the end of a line (only "\n": a pasted "line separator" or a form feed is a space like another).
    private static let space = #"[\t\n\x0B\f\r\x1C-\x1F\x85\p{Z}]"#
    private static let notSpace = #"[^\t\n\x0B\f\r\x1C-\x1F\x85\p{Z}]"#
    private static let word = #"[\p{L}\p{N}_]"#
    private static func expression(_ pattern: String) -> NSRegularExpression {
        // The patterns are written in this file and every one is run by the tests.
        try! NSRegularExpression(pattern: pattern, options: .useUnixLineSeparators)
    }
    /// After the heading text: a number, then nothing, or a dash, a colon or a full stop and the title.
    /// A full stop counts only before a space or at the end of the line: "1.5" is not chapter 1 with the title "5".
    /// The book-audio engine reads headings with the same expression: a form is never accepted on one side only.
    private static let headingExpression = expression(#"^\#(space)*(\d+)\#(space)*(?:(?:[—–:-]|\.(?=\#(space)|$))+\#(space)*(.*?))?\#(space)*$"#)
    private static let codeMark = expression("^" + space + "*(?:```|~~~)")
    private static let commentStart = expression("^" + space + "*<!--")
    private static let cleaningSteps: [(expression: NSRegularExpression, replacement: String)] = [
        (#"!\[\[[^\]]*\]\]"#, ""),                                                        // ![[embedded file]]
        (#"!\[[^\]]*\]\([^)]*\)"#, ""),                                                    // ![image](file)
        (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),                                                 // [text](address)
        (#"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]"#, "$1"),                                        // [[Page]] and [[Page|shown]]
        (#"\*\*"#, ""), ("__", ""),
        (#"(?<!\#(word))\*(?=\#(notSpace))(.+?)(?<=\#(notSpace))\*(?!\#(word))"#, "$1"),    // *emphasis*
        (#"(?<!\#(word))_(?=\#(notSpace))(.+?)(?<=\#(notSpace))_(?!\#(word))"#, "$1"),      // _emphasis_
        (#"[*`]"#, ""),
        (#"\.{4,}"#, " "),                                                                  // dot leaders
        (#"«\#(space)*"#, "\""), (#"\#(space)*»"#, "\""),
        (#"\#(space)+"#, " "),
    ].map { (expression($0.0), $0.1) }
    /// A title without its Markdown, exactly as the engine reads it (`clean_inline` in its reader, step for step):
    /// the engine names a chapter's files after this text, and the app looks for them under the same name.
    static func cleanInline(_ text: String) -> String {
        cleaningSteps.reduce(text) { title, step in
            step.expression.stringByReplacingMatches(in: title, range: NSRange(title.startIndex..., in: title), withTemplate: step.replacement)
        }.trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }
    public static func parse(_ text: String, heading: String = "# Chapter ") throws -> [Chapter] {
        guard !heading.isEmpty else { throw NarrateurError("The chapter heading cannot be empty.") }
        var chapters: [Chapter] = [], inCode = false, inComment = false
        let expression = headingExpression
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{a0}", with: " ")
        for line in normalized.components(separatedBy: "\n") {
            // Compared character code by character code, as the engine does: an accent typed after the heading text does not hide the line.
            if !inCode && line.unicodeScalars.starts(with: heading.unicodeScalars) {
                let rest = String(String.UnicodeScalarView(line.unicodeScalars.dropFirst(heading.unicodeScalars.count)))
                guard let match = expression.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)), let range = Range(match.range(at: 1), in: rest), let number = Int(rest[range]) else {
                    throw NarrateurError("Cannot read the chapter heading “\(line.trimmingCharacters(in: .whitespaces))”: after “\(heading)” it needs a number, then a title if you want one, like “\(heading)3 — Title”.")
                }
                guard !chapters.contains(where: { $0.number == number }) else { throw NarrateurError("Chapter \(number) appears twice: each chapter needs its own number.") }
                let title = cleanInline(Range(match.range(at: 2), in: rest).map { String(rest[$0]) } ?? "")
                chapters.append(Chapter(number: number, title: title))
                inComment = false
            } else if !chapters.isEmpty {
                // The engine's order: inside a comment nothing counts but its end; inside a code block nothing
                // counts but its closing mark. A heading is hidden by a code block, never by a comment.
                let starts = { (mark: NSRegularExpression) in mark.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
                let endsComment = line.range(of: "-->", options: .literal) != nil
                if inComment { if endsComment { inComment = false } }
                else if inCode { if starts(codeMark) { inCode = false } }
                else if starts(codeMark) { inCode = true }
                else if starts(commentStart), !endsComment { inComment = true }
            }
        }
        return chapters
    }
}
