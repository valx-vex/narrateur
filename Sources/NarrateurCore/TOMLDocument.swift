import Foundation

/// The scalar TOML dialect used by book-audio. Retains original line ranges for surgical edits.
/// Bare keys, tables, array tables, basic/literal strings (including multiline), and numbers.
/// Other value forms fail explicitly; this is deliberately not a general TOML implementation.
public struct TOMLDocument {
    struct Entry { var section: String; var key: String; var value: String; var isString: Bool; var lines: Range<Int> }
    let lines: [String]
    var entries: [Entry] = []
    var sections: [(name: String, line: Int)] = []
    public init(_ text: String) throws {
        lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0, section = ""
        while index < lines.count {
            let start = index
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                let header = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
                guard header.hasSuffix("]"), header.range(of: #"^\[\[?[A-Za-z0-9_-]+\]\]?$"#, options: .regularExpression) != nil else { throw NarrateurError("Unsupported TOML table on line \(start + 1).") }
                let name = header.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                section = header.hasPrefix("[[") ? "\(name)#\(start)" : name
                guard !sections.contains(where: { $0.name == section }) else { throw NarrateurError("Duplicate TOML table: \(section).") }
                sections.append((section, start)); continue
            }
            guard let equals = line.firstIndex(of: "=") else { throw NarrateurError("Expected a TOML assignment on line \(start + 1).") }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { throw NarrateurError("Unsupported TOML key: \(key).") }
            var token = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            let triple = token.hasPrefix("\"\"\"") ? "\"\"\"" : (token.hasPrefix("'''") ? "'''" : nil)
            if let triple {
                while Self.closingQuote(in: token, delimiter: triple) == nil {
                    guard index < lines.count else { throw NarrateurError("Unclosed TOML string: \(key).") }
                    token += "\n" + lines[index]; index += 1
                }
            }
            let delimiter = triple ?? (token.hasPrefix("\"") ? "\"" : (token.hasPrefix("'") ? "'" : ""))
            let value: String
            if !delimiter.isEmpty {
                guard let end = Self.closingQuote(in: token, delimiter: delimiter) else { throw NarrateurError("Unclosed TOML string: \(key).") }
                let trailing = token[end.upperBound...].trimmingCharacters(in: .whitespaces)
                guard trailing.isEmpty || trailing.hasPrefix("#") else { throw NarrateurError("Unexpected TOML text after \(key).") }
                var body = String(token[token.index(token.startIndex, offsetBy: delimiter.count)..<end.lowerBound])
                if triple != nil && body.hasPrefix("\n") { body.removeFirst() }
                value = delimiter.hasPrefix("\"") ? try Self.unescape(body) : body
            } else {
                value = token.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
                guard Double(value) != nil || value == "true" || value == "false" else { throw NarrateurError("Unsupported TOML value for \(key); use a quoted string or a number.") }
            }
            guard !entries.contains(where: { $0.section == section && $0.key == key }) else { throw NarrateurError("Duplicate TOML key: \(key).") }
            entries.append(Entry(section: section, key: key, value: value, isString: !delimiter.isEmpty, lines: start..<index))
        }
    }
    private static func closingQuote(in token: String, delimiter: String) -> Range<String.Index>? {
        var pos = token.index(token.startIndex, offsetBy: delimiter.count)
        while pos < token.endIndex {
            if token[pos...].hasPrefix(delimiter) { return pos..<token.index(pos, offsetBy: delimiter.count) }
            if delimiter.hasPrefix("\""), token[pos] == "\\" {
                pos = token.index(after: pos)
                if pos == token.endIndex { break }
            }
            pos = token.index(after: pos)
        }
        return nil
    }
    private static func unescape(_ text: String) throws -> String {
        var result = "", iterator = text.makeIterator()
        while let c = iterator.next() {
            guard c == "\\" else { result.append(c); continue }
            guard let next = iterator.next() else { throw NarrateurError("Incomplete TOML escape.") }
            switch next {
            case "n": result += "\n"
            case "r": result += "\r"
            case "t": result += "\t"
            case "b": result += "\u{8}"
            case "f": result += "\u{c}"
            case "\"", "\\": result.append(next)
            case "u", "U":
                var hex = ""
                for _ in 0..<(next == "u" ? 4 : 8) { if let c = iterator.next() { hex.append(c) } }
                guard let number = UInt32(hex, radix: 16), let scalar = UnicodeScalar(number) else { throw NarrateurError("Invalid TOML Unicode escape.") }
                result.unicodeScalars.append(scalar)
            default: throw NarrateurError("Unsupported TOML escape: \\(next).")
            }
        }
        return result
    }
    public func string(_ key: String, in section: String = "") -> String? { entries.first { $0.section == section && $0.key == key && $0.isString }?.value }
    public func raw(_ key: String, in section: String = "") -> String? { entries.first { $0.section == section && $0.key == key }?.value }
}
