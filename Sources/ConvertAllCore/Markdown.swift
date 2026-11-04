import Foundation

/// A compact Markdown → HTML converter (CommonMark's everyday subset: headings, paragraphs,
/// emphasis, code, links, images, lists, quotes, rules). Markdown files then convert like
/// web pages — to DOCX, PDF, RTF… with their structure kept.
public enum Markdown {
    public static func html(from markdown: String, title: String = "") -> String {
        let body = blocks(markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"))
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>body{font-family:Helvetica,Arial,sans-serif;font-size:12pt;line-height:1.4}
        code,pre{font-family:Menlo,monospace;font-size:10.5pt}pre{background:#f4f4f4;padding:8px}
        blockquote{color:#555;border-left:3px solid #ccc;margin-left:0;padding-left:12px}</style></head>
        <body>
        \(body)
        </body></html>
        """
    }

    // MARK: Blocks

    static func blocks(_ lines: [String]) -> String {
        var out: [String] = []
        var paragraph: [String] = []
        var i = 0

        func flush() {
            if !paragraph.isEmpty { out.append("<p>\(inline(paragraph.joined(separator: " ")))</p>") }
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flush(); i += 1; continue }

            // Fenced code
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i]); i += 1
                }
                out.append("<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>")
                i += 1
                continue
            }

            // Headings
            if let level = headingLevel(trimmed) {
                flush()
                let text = trimmed.dropFirst(level).trimmingCharacters(in: CharacterSet(charactersIn: " #"))
                out.append("<h\(level)>\(inline(text))</h\(level)>")
                i += 1
                continue
            }

            // Horizontal rule
            if isRule(trimmed) { flush(); out.append("<hr>"); i += 1; continue }

            // Block quote (consecutive > lines, parsed recursively)
            if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var q = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    if q.hasPrefix(" ") { q = q.dropFirst() }
                    quoted.append(String(q)); i += 1
                }
                out.append("<blockquote>\(blocks(quoted))</blockquote>")
                continue
            }

            // Lists
            if let ordered = listMarker(trimmed) {
                flush()
                var items: [String] = []
                while i < lines.count, let kind = listMarker(lines[i].trimmingCharacters(in: .whitespaces)), kind == ordered {
                    items.append("<li>\(inline(stripMarker(lines[i].trimmingCharacters(in: .whitespaces))))</li>")
                    i += 1
                }
                let tag = ordered ? "ol" : "ul"
                out.append("<\(tag)>\(items.joined())</\(tag)>")
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flush()
        return out.joined(separator: "\n")
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.hasPrefix(" ") ? hashes : nil
    }

    private static func isRule(_ line: String) -> Bool {
        let chars = line.filter { $0 != " " }
        guard chars.count >= 3, let first = chars.first, "-*_".contains(first) else { return false }
        return chars.allSatisfy { $0 == first }
    }

    /// true = ordered ("1."), false = bullet ("-", "*", "+"), nil = not a list item.
    private static func listMarker(_ line: String) -> Bool? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().hasPrefix(" ") { return false }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return true }
        }
        return nil
    }

    private static func stripMarker(_ line: String) -> String {
        if let first = line.first, "-*+".contains(first) { return String(line.dropFirst(2)) }
        let digits = line.prefix { $0.isNumber }
        return String(line.dropFirst(digits.count + 2))
    }

    // MARK: Inline

    static func inline(_ text: String) -> String {
        var s = escape(text)
        // Code spans first, so their contents aren't formatted.
        var codes: [String] = []
        s = replace(s, #"`([^`]+)`"#) { m in
            codes.append("<code>\(m[1])</code>")
            return "\u{0}\(codes.count - 1)\u{0}"
        }
        s = replace(s, #"!\[([^\]]*)\]\(([^)\s]+)\)"#) { "<img alt=\"\($0[1])\" src=\"\($0[2])\">" }
        s = replace(s, #"\[([^\]]+)\]\(([^)\s]+)\)"#) { "<a href=\"\($0[2])\">\($0[1])</a>" }
        s = replace(s, #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#) { "<strong>\($0[2])</strong>" }
        s = replace(s, #"(\*|_)(?=\S)(.+?)(?<=\S)\1"#) { "<em>\($0[2])</em>" }
        s = replace(s, #"~~(?=\S)(.+?)(?<=\S)~~"#) { "<del>\($0[1])</del>" }
        for (i, code) in codes.enumerated() { s = s.replacingOccurrences(of: "\u{0}\(i)\u{0}", with: code) }
        return s
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func replace(_ text: String, _ pattern: String, _ make: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[last..<range.lowerBound]
            let groups = (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
            result += make(groups)
            last = range.upperBound
        }
        return result + text[last...]
    }
}
