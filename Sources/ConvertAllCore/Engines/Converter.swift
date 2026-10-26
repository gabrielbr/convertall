#if os(macOS)
import Foundation
import ImageIO

public enum ConversionError: LocalizedError {
    case unreadable(String)
    case engineMissing(FileFormat)
    case writeFailed(String)
    case noText

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn't read “\(name)”."
        case .engineMissing(let format): "\(format.displayName) conversion needs an extra component."
        case .writeFailed(let detail): "Conversion failed: \(detail)"
        case .noText: "This PDF has no selectable text (it may be a scan)."
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
    public static func convert(
        _ url: URL, from source: FileFormat, to target: FileFormat, task: ConversionTask = ConversionTask()
    ) throws -> [URL] {
        try task.checkCancelled()
        switch ConversionMatrix.engine(from: source, to: target) {
        case .image:
            let out = try ImageConverter.convert(url, to: target)
            task.report(1)
            return [out]
        case .media:
            return [try MediaEngine.convert(url, from: source, to: target, task: task)]
        case .document:
            return try DocumentEngine.convert(url, from: source, to: target, task: task)
        case .office:
            return try OfficeEngine.convert(url, from: source, to: target, task: task)
        }
    }
}
#endif
