#if os(macOS)
import ConvertAllCore
import Foundation

/// One pill in the chip: convert to a format, make the file smaller in its own
/// format, or combine the whole selection into one file.
enum ChipAction: Hashable, Identifiable {
    case convert(FileFormat)
    case compress(FileFormat)
    case combine(FileFormat)

    var id: String {
        switch self {
        case .convert(let f): "convert-\(f.rawValue)"
        case .compress(let f): "compress-\(f.rawValue)"
        case .combine(let f): "combine-\(f.rawValue)"
        }
    }

    var format: FileFormat {
        switch self {
        case .convert(let f), .compress(let f), .combine(let f): f
        }
    }

    func label(fileCount: Int) -> String {
        switch self {
        case .convert(let f): f.displayName
        case .compress: "Smaller"
        case .combine(.pdf): fileCount > 1 ? "One PDF" : "PDF"
        case .combine(let f): "Join \(f.displayName)"
        }
    }

    func blurb(fileCount: Int) -> String {
        switch self {
        case .convert(let f): f.blurb
        case .compress: "Same format, smaller file"
        case .combine(.pdf): fileCount > 1 ? "All pages in one PDF, in this order" : "Image as a PDF page"
        case .combine(let f) where f.category == .video: "One video, clips back to back"
        case .combine: "One track, back to back"
        }
    }

    /// What the chip says while working: "Converting to MP4…", "Making it smaller…".
    var verb: String {
        switch self {
        case .convert(let f): "Converting to \(f.displayName)"
        case .compress: "Making it smaller"
        case .combine(.pdf): "Building the PDF"
        case .combine: "Joining"
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
        }
        return words.contains { $0.hasPrefix(q) } ? 850 : formatScore / 2
    }
}
#endif
