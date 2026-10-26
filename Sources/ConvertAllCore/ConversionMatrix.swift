import Foundation

/// Which engine performs a conversion. Decides what (if anything) must be installed first.
public enum EngineKind: Equatable, Sendable {
    /// ImageIO + built-in codecs. WebP/AVIF output may borrow the media engine.
    case image
    /// FFmpeg — video, audio, GIF ↔ video.
    case media
    /// Cocoa text system + PDFKit — DOCX, DOC, ODT, RTF, TXT, HTML, PDF.
    case document
    /// LibreOffice — spreadsheets and presentations.
    case office
}

/// What converts to what, mirroring convt.app/formats.
public enum ConversionMatrix {
    /// Output formats per category, most popular first (this is the grid order).
    public static let imageOutputs: [FileFormat] = [
        .png, .jpeg, .webp, .heic, .avif, .gif, .tiff, .ico, .bmp, .tga, .exr, .qoi, .pnm,
    ]
    public static let videoOutputs: [FileFormat] = [.mp4, .mov, .webm, .mkv, .avi]
    public static let audioOutputs: [FileFormat] = [.mp3, .m4a, .wav, .flac, .aac, .ogg, .opus]
    public static let textDocumentOutputs: [FileFormat] = [.docx, .txt, .rtf, .html, .odt, .doc]
    public static let spreadsheetOutputs: [FileFormat] = [.xlsx, .csv, .ods, .xls]
    public static let presentationOutputs: [FileFormat] = [.pptx, .odp, .ppt]

    /// Every format a single file of `source` format can become, in display order.
    public static func targets(for source: FileFormat) -> [FileFormat] {
        let list: [FileFormat]
        switch source.category {
        case .image:
            list = imageOutputs + (source == .gif ? videoOutputs : [])
        case .video:
            list = videoOutputs + audioOutputs + imageOutputs
        case .audio:
            list = audioOutputs
        case .document:
            list = source == .pdf
                ? textDocumentOutputs + imageOutputs
                : [.pdf] + textDocumentOutputs + imageOutputs
        case .spreadsheet:
            list = spreadsheetOutputs + [.pdf] + imageOutputs
        case .presentation:
            list = presentationOutputs + [.pdf] + imageOutputs
        }
        return list.filter { $0 != source }
    }

    /// Targets every file in a selection can reach, grouped into the chip's sections.
    /// Section order follows the first file's natural order (its own category first).
    public static func sections(for sources: [FileFormat]) -> [(category: FormatCategory, formats: [FileFormat])] {
        guard let first = sources.first else { return [] }
        var common = targets(for: first)
        for source in sources.dropFirst() {
            let other = Set(targets(for: source))
            common = common.filter(other.contains)
        }
        var order: [FormatCategory] = []
        for f in common where !order.contains(f.category) { order.append(f.category) }
        return order.map { cat in (cat, common.filter { $0.category == cat }) }
    }

    public static func engine(from source: FileFormat, to target: FileFormat) -> EngineKind {
        switch (source.category, target.category) {
        case (.image, .image): .image
        case (.video, _), (.audio, _), (.image, .video): .media
        case (.spreadsheet, _), (.presentation, _): .office
        default: .document
        }
    }
}
