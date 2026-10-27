#if os(macOS)
import ConvertAllCore
import Foundation

/// One pill in the chip: convert to a format, make the file smaller in its own
/// format, combine the whole selection into one file, or an on-device "smart" action.
enum ChipAction: Hashable, Identifiable {
    case convert(FileFormat)
    case compress(FileFormat)
    case combine(FileFormat)
    /// OCR: the text in a photo, screenshot or scan → .txt
    case extractText
    /// The subject on a transparent background.
    case removeBackground

    var id: String {
        switch self {
        case .convert(let f): "convert-\(f.rawValue)"
        case .compress(let f): "compress-\(f.rawValue)"
        case .combine(let f): "combine-\(f.rawValue)"
        case .extractText: "extract-text"
        case .removeBackground: "remove-background"
        }
    }

    var format: FileFormat {
        switch self {
        case .convert(let f), .compress(let f), .combine(let f): f
        case .extractText: .txt
        case .removeBackground: .png
        }
    }

    func label(fileCount: Int) -> String {
        switch self {
        case .convert(let f): f.displayName
        case .compress: "Smaller"
        case .combine(.pdf): fileCount > 1 ? "One PDF" : "PDF"
        case .combine(let f): "Join \(f.displayName)"
        case .extractText: "Text"
        case .removeBackground: "Cutout"
        }
    }

    func blurb(fileCount: Int) -> String {
        switch self {
        case .convert(let f): f.blurb
        case .compress: "Same format, smaller file"
        case .combine(.pdf): fileCount > 1 ? "All pages in one PDF, in this order" : "Image as a PDF page"
        case .combine(let f) where f.category == .video: "One video, clips back to back"
        case .combine: "One track, back to back"
        case .extractText: "Recognise the text (OCR) → .txt"
        case .removeBackground: "Subject on a transparent background"
        }
    }

    /// What the chip says while working: "Converting to MP4…", "Making it smaller…".
    var verb: String {
        switch self {
        case .convert(let f): "Converting to \(f.displayName)"
        case .compress: "Making it smaller"
        case .combine(.pdf): "Building the PDF"
        case .combine: "Joining"
        case .extractText: "Reading the text"
        case .removeBackground: "Cutting out"
        }
    }

    /// Search relevance, so "smaller", "merge" or "join" find the special pills.
    func score(_ query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return 1 }
        let formatScore = FormatSearch.score(format, query: q)
        let words: [String]
        switch self {
        case .convert: return formatScore
        case .compress: words = ["smaller", "compress", "shrink", "reduce", "optimize", "optimise", "lighter"]
        case .combine: words = ["combine", "merge", "join", "together", "one", "stitch", "concat"]
        case .extractText: words = ["text", "ocr", "scan", "read", "extract", "words"]
        case .removeBackground: words = ["cutout", "background", "remove", "transparent", "subject", "isolate"]
        }
        return words.contains { $0.hasPrefix(q) } ? 850 : formatScore / 2
    }
}
#endif
