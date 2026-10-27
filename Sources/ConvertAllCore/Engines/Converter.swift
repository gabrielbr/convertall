#if os(macOS)
import Foundation
import ImageIO

public enum ConversionError: LocalizedError {
    case unreadable(String)
    case engineMissing(FileFormat)
    case writeFailed(String)
    case noText
    case alreadyOptimized

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn't read “\(name)”."
        case .engineMissing(let format): "\(format.displayName) conversion needs an extra component."
        case .writeFailed(let detail): "Conversion failed: \(detail)"
        case .noText: "This PDF has no selectable text (it may be a scan)."
        case .alreadyOptimized: "Already as small as it gets — no smaller version was saved."
        }
    }
}

/// What must happen before a conversion can run.
public enum Requirement: Equatable, Sendable {
    case ready
    /// The FFmpeg media engine — a one-time download (`MediaPack`).
    case mediaEngine
    /// LibreOffice — installed by the user (free).
    case libreOffice
}

/// Single entry point for every conversion: routes each source → target pair to an engine.
public enum Converter {
    public static func sourceFormat(of url: URL) -> FileFormat? {
        if let f = FileFormat(url: url) { return f }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(src) as String?
        else { return nil }
        return FileFormat(typeIdentifier: uti)
    }

    public static func requirement(from source: FileFormat, to target: FileFormat) -> Requirement {
        switch ConversionMatrix.engine(from: source, to: target) {
        case .image:
            return ImageConverter.needsMediaEngine(target) ? .mediaEngine : .ready
        case .media:
            return MediaEngine.ffmpegURL == nil ? .mediaEngine : .ready
        case .document:
            return ImageConverter.needsMediaEngine(target) ? .mediaEngine : .ready
        case .office:
            if OfficeEngine.sofficeURL == nil { return .libreOffice }
            return ImageConverter.needsMediaEngine(target) ? .mediaEngine : .ready
        }
    }

    /// Converts one file. Returns the created file(s) — several for multi-page
    /// documents exported as images (placed together in a folder).
    /// `source == target` compresses the file in its own format.
    public static func convert(
        _ url: URL, from source: FileFormat, to target: FileFormat,
        options: ConversionOptions = ConversionOptions(), task: ConversionTask = ConversionTask()
    ) throws -> [URL] {
        try task.checkCancelled()
        let outputs: [URL]
        switch ConversionMatrix.engine(from: source, to: target) {
        case .image:
            outputs = [try ImageConverter.convert(url, to: target, options: options)]
            task.report(1)
        case .media:
            outputs = [try MediaEngine.convert(url, from: source, to: target, options: options, task: task)]
        case .document:
            outputs = try DocumentEngine.convert(url, from: source, to: target, options: options, task: task)
        case .office:
            outputs = try OfficeEngine.convert(url, from: source, to: target, options: options, task: task)
        }

        // A "Compress" that didn't shrink anything isn't worth keeping.
        if source == target, outputs.count == 1,
           ImageConverter.fileSize(outputs[0]) >= ImageConverter.fileSize(url) {
            try? FileManager.default.removeItem(at: outputs[0])
            throw ConversionError.alreadyOptimized
        }
        return outputs
    }

    /// Bytes on disk, counting folder contents (multi-page output).
    public static func totalSize(of urls: [URL]) -> Int64 {
        let fm = FileManager.default
        return urls.reduce(Int64(0)) { sum, url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return sum }
            if !isDir.boolValue { return sum + Int64(ImageConverter.fileSize(url)) }
            let files = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
            return sum + files.reduce(Int64(0)) { $0 + Int64(ImageConverter.fileSize($1)) }
        }
    }
}
#endif
