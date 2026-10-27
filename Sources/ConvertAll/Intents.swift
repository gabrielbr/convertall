#if os(macOS)
import AppIntents
import ConvertAllCore
import Foundation

// Shortcuts actions. They run inside ConvertAll (no window) and use the same engines
// as the chip. Converted files are saved next to the originals and handed back to the
// shortcut, so they can be chained into further actions.

/// Set as soon as a Shortcuts action runs, so a background launch doesn't pop the welcome window.
enum IntentActivity {
    static var started = false
}

/// Output formats as Shortcuts sees them.
enum ShortcutFormat: String, AppEnum {
    case jpeg
    case png
    case webp
    case heic
    case avif
    case gif
    case tiff
    case bmp
    case ico
    case tga
    case pnm
    case qoi
    case exr
    case mp4
    case mov
    case webm
    case mkv
    case avi
    case mp3
    case wav
    case flac
    case aac
    case m4a
    case ogg
    case opus
    case pdf
    case docx
    case doc
    case odt
    case rtf
    case txt
    case html
    case xlsx
    case xls
    case ods
    case csv
    case pptx
    case ppt
    case odp

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Format"
    static var caseDisplayRepresentations: [ShortcutFormat: DisplayRepresentation] = [
        .jpeg: "JPEG",
        .png: "PNG",
        .webp: "WebP",
        .heic: "HEIC",
        .avif: "AVIF",
        .gif: "GIF",
        .tiff: "TIFF",
        .bmp: "BMP",
        .ico: "ICO",
        .tga: "TGA",
        .pnm: "PPM",
        .qoi: "QOI",
        .exr: "EXR",
        .mp4: "MP4",
        .mov: "MOV",
        .webm: "WebM",
        .mkv: "MKV",
        .avi: "AVI",
        .mp3: "MP3",
        .wav: "WAV",
        .flac: "FLAC",
        .aac: "AAC",
        .m4a: "M4A",
        .ogg: "OGG",
        .opus: "Opus",
        .pdf: "PDF",
        .docx: "DOCX",
        .doc: "DOC",
        .odt: "ODT",
        .rtf: "RTF",
        .txt: "TXT",
        .html: "HTML",
        .xlsx: "XLSX",
        .xls: "XLS",
        .ods: "ODS",
        .csv: "CSV",
        .pptx: "PPTX",
        .ppt: "PPT",
        .odp: "ODP",
    ]

    var format: FileFormat { FileFormat(rawValue: rawValue)! }
}

enum ShortcutQuality: String, AppEnum {
    case smaller, balanced, best

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Quality"
    static var caseDisplayRepresentations: [ShortcutQuality: DisplayRepresentation] = [
        .smaller: "Smaller",
        .balanced: "Balanced",
        .best: "Best",
    ]
}

enum ShortcutCombineFormat: String, AppEnum {
    case pdf, mp4, mp3, m4a

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Combined format"
    static var caseDisplayRepresentations: [ShortcutCombineFormat: DisplayRepresentation] = [
        .pdf: "PDF",
        .mp4: "MP4",
        .mp3: "MP3",
        .m4a: "M4A",
    ]
}

/// Shortcuts may hand over files without a stable location; give each one a real URL.
private func localURLs(_ files: [IntentFile]) throws -> [URL] {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertAll-Shortcuts-\(UUID().uuidString)")
    return try files.map { file in
        if let url = file.fileURL, FileManager.default.isReadableFile(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file.filename)
        try file.data.write(to: url)
        return url
    }
}

private func intentFiles(_ urls: [URL]) -> [IntentFile] {
    urls.map { IntentFile(fileURL: $0, filename: $0.lastPathComponent) }
}

private func sourceFormat(_ url: URL) throws -> FileFormat {
    guard let f = Converter.sourceFormat(of: url) else { throw ConversionError.unreadable(url.lastPathComponent) }
    return f
}

/// Runs blocking engine work off the main thread.
private func background<T>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { c in
        DispatchQueue.global(qos: .userInitiated).async { c.resume(with: Result { try body() }) }
    }
}

struct ConvertFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Files"
    static var description = IntentDescription("Converts images, video, audio and documents to another format. Files are saved next to the originals.")

    @Parameter(title: "Files") var files: [IntentFile]
    @Parameter(title: "Format", default: .png) var format: ShortcutFormat
    @Parameter(title: "Quality", default: .balanced) var quality: ShortcutQuality

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$files) to \(\.$format)") { \.$quality }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        IntentActivity.started = true
        let urls = try localURLs(files)
        let target = format.format
        var options = ConversionOptions()
        options.quality = ConversionOptions.Quality(rawValue: quality.rawValue) ?? .balanced
        let opts = options
        var outputs: [URL] = []
        for url in urls {
            let source = try sourceFormat(url)
            outputs += try await background { try Converter.convert(url, from: source, to: target, options: opts) }
        }
        return .result(value: intentFiles(outputs))
    }
}

struct MakeSmallerIntent: AppIntent {
    static var title: LocalizedStringResource = "Make Files Smaller"
    static var description = IntentDescription("Re-encodes images, video, audio and PDFs in their own format at a smaller size.")

    @Parameter(title: "Files") var files: [IntentFile]
    @Parameter(title: "Quality", default: .balanced) var quality: ShortcutQuality

    static var parameterSummary: some ParameterSummary {
        Summary("Make \(\.$files) smaller") { \.$quality }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        IntentActivity.started = true
        var options = ConversionOptions()
        options.quality = ConversionOptions.Quality(rawValue: quality.rawValue) ?? .balanced
        let opts = options
        var outputs: [URL] = []
        for url in try localURLs(files) {
            let source = try sourceFormat(url)
            outputs += try await background { try Converter.convert(url, from: source, to: source, options: opts) }
        }
        return .result(value: intentFiles(outputs))
    }
}

struct CombineFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Combine Files"
    static var description = IntentDescription("Images and PDFs into one PDF, videos into one MP4, or audio into one track.")

    @Parameter(title: "Files") var files: [IntentFile]
    @Parameter(title: "Into", default: .pdf) var format: ShortcutCombineFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Combine \(\.$files) into one \(\.$format)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        IntentActivity.started = true
        let urls = try localURLs(files)
        let sources = try urls.map(sourceFormat)
        let target = FileFormat(rawValue: format.rawValue)!
        let out = try await background { try Combiner.combine(urls, sources: sources, to: target) }
        return .result(value: IntentFile(fileURL: out, filename: out.lastPathComponent))
    }
}

struct ExtractTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Extract Text (OCR)"
    static var description = IntentDescription("Recognises the text in images and scanned PDFs, on device.")

    @Parameter(title: "Image or PDF") var file: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        IntentActivity.started = true
        let url = try localURLs([file])[0]
        let source = try sourceFormat(url)
        let txt = try await background { try VisionEngine.extractText(url, from: source) }
        let text = (try? String(contentsOf: txt, encoding: .utf8)) ?? ""
        return .result(value: text)
    }
}

@available(macOS 14.0, *)
struct RemoveBackgroundIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove Background"
    static var description = IntentDescription("Keeps the subject of a photo on a transparent background.")

    @Parameter(title: "Image") var file: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        IntentActivity.started = true
        let url = try localURLs([file])[0]
        let source = try sourceFormat(url)
        let out = try await background { try VisionEngine.removeBackground(url, from: source) }
        return .result(value: IntentFile(fileURL: out, filename: out.lastPathComponent))
    }
}
#endif
