import Foundation

/// Ranks formats against what the user typed in the chip.
///
/// Designed for 1–4 keystrokes: "p" → PNG first, "jp" → JPEG, "fav" → ICO,
/// "hdr" → EXR. Non-matching formats are dropped; ties keep the input order
/// (which is already personalised by recent use).
public enum FormatSearch {
    public static func rank(_ formats: [FileFormat], query: String) -> [FileFormat] {
        let q = normalize(query)
        guard !q.isEmpty else { return formats }

        return formats.enumerated()
            .compactMap { index, format -> (FileFormat, Int, Int)? in
                let s = score(format, q)
                return s > 0 ? (format, s, index) : nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    static func score(_ format: FileFormat, _ q: String) -> Int {
        let name = normalize(format.displayName)
        if name == q { return 1000 }
        if format.fileExtensions.contains(q) { return 900 }
        if name.hasPrefix(q) { return 800 }
        if format.fileExtensions.contains(where: { $0.hasPrefix(q) }) { return 700 }

        let words = format.searchAliases.flatMap { $0.split(separator: " ").map(String.init) }
        if format.searchAliases.contains(q) { return 600 }
        if words.contains(where: { $0.hasPrefix(q) }) { return 500 }
        if name.contains(q) { return 400 }
        if isSubsequence(q, of: name) { return 200 }
        if format.searchAliases.contains(where: { $0.contains(q) }) { return 100 }
        return 0
    }

    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        outer: for c in needle {
            while let h = it.next() { if h == c { continue outer } }
            return false
        }
        return true
    }
}
