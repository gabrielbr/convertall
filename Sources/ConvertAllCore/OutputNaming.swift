import Foundation

public enum OutputNaming {
    /// Where a converted file goes: next to the original, same base name, new
    /// extension. Never overwrites — appends " 2", " 3"… like Finder does.
    ///
    /// `photo.jpg` → `photo.png`; if that exists → `photo 2.png`.
    public static func destination(
        for source: URL,
        format: ImageFormat,
        in directory: URL? = nil,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let dir = directory ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let ext = format.preferredExtension

        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        // The source itself counts as taken (e.g. PNG → PNG re-encode).
        while fileExists(candidate) || candidate.standardizedFileURL == source.standardizedFileURL {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
