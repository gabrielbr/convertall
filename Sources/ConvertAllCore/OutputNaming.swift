import Foundation

public enum OutputNaming {
    /// Where a converted file goes: next to the original, same base name, new
    /// extension. Never overwrites — appends " 2", " 3"… like Finder does.
    ///
    /// `photo.jpg` → `photo.png`; if that exists → `photo 2.png`.
    /// `suffix` names derived outputs: `photo.jpg` → `photo (no background).png`.
    public static func destination(
        for source: URL,
        format: FileFormat,
        in directory: URL? = nil,
        suffix: String? = nil,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let dir = directory ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + (suffix.map { " (\($0))" } ?? "")
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

    /// Folder for multi-page output: `report.pdf` → `report (PNG)/`, `report (PNG) 2/`, …
    public static func folder(
        for source: URL,
        format: FileFormat,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let dir = source.deletingLastPathComponent()
        let name = "\(source.deletingPathExtension().lastPathComponent) (\(format.displayName))"
        var candidate = dir.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fileExists(candidate) {
            candidate = dir.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// Moves finished results (files or multi-page folders) into `folder`, never overwriting:
    /// `photo.png` → `folder/photo.png`, or `folder/photo 2.png` if that exists.
    public static func relocate(_ outputs: [URL], to folder: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return try outputs.map { output in
            guard output.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL else { return output }
            let dest = uniqueURL(named: output.lastPathComponent, in: folder)
            try fm.moveItem(at: output, to: dest)
            return dest
        }
    }

    /// `name.ext`, else `name 2.ext`, `name 3.ext`… in `folder`.
    public static func uniqueURL(
        named name: String, in folder: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while fileExists(candidate) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// Page files inside that folder, zero-padded so they sort: `report 01.png` … `report 12.png`.
    public static func pageFiles(for source: URL, format: FileFormat, count: Int, in folder: URL) -> [URL] {
        let base = source.deletingPathExtension().lastPathComponent
        let digits = String(count).count
        return (1...max(count, 1)).map { i in
            let number = String(repeating: "0", count: digits - String(i).count) + String(i)
            return folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(format.preferredExtension)
        }
    }

    /// Output of "Combine": `holiday.jpg` + others → `holiday (combined).pdf`, never overwriting.
    public static func combined(
        for first: URL, format: FileFormat,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let named = first.deletingLastPathComponent()
            .appendingPathComponent("\(first.deletingPathExtension().lastPathComponent) (combined)")
            .appendingPathExtension(first.pathExtension)
        return destination(for: named, format: format, fileExists: fileExists)
    }
}
