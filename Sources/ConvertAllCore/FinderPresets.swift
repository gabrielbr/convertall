import Foundation

/// The Finder menu's presets: which one-click actions "ConvertAll ▸" offers per kind of file.
/// Shared by the app (Settings) and the sandboxed Finder extension, which can't read the
/// app's settings — the app sends the choice over as a distributed notification.
public enum FinderPresets {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case image, video, audio, pdf, document

        public var title: String {
            switch self {
            case .image: "Images"
            case .video: "Video"
            case .audio: "Audio"
            case .pdf: "PDF"
            case .document: "Documents"
            }
        }
    }

    /// kind → preset ids, in menu order.
    public typealias Config = [String: [String]]

    public static let notificationName = "app.convertall.FinderPresets"
    public static let requestNotificationName = "app.convertall.FinderPresets.request"

    /// Every preset id, in a fixed order: a Finder menu item's tag is its index here (Finder
    /// keeps only an item's title, action, image and tag when it shows the menu).
    public static let all: [String] =
        ["open", "compress-same", "combine-pdf", "combine-mp4", "extract-text", "remove-background"]
            + FileFormat.allCases.map { "convert-\($0.rawValue)" }

    public static func candidates(for kind: Kind) -> [String] {
        switch kind {
        case .image:
            ["compress-same"] + [FileFormat.png, .jpeg, .heic, .webp, .avif, .gif, .tiff, .ico].map(convert)
                + ["combine-pdf", "extract-text", "remove-background"]
        case .video:
            ["compress-same"] + [FileFormat.mp4, .mov, .webm, .gif, .mp3, .m4a].map(convert) + ["combine-mp4"]
        case .audio:
            ["compress-same"] + [FileFormat.mp3, .m4a, .wav, .flac, .aac, .ogg, .opus].map(convert)
        case .pdf:
            ["compress-same"] + [FileFormat.docx, .png, .jpeg, .txt].map(convert) + ["combine-pdf", "extract-text"]
        case .document:
            [FileFormat.pdf, .png, .docx, .txt, .html].map(convert)
        }
    }

    public static let defaults: Config = [
        Kind.image.rawValue: ["compress-same", "convert-png", "convert-jpeg", "convert-heic", "convert-webp",
                              "combine-pdf", "extract-text", "remove-background"],
        Kind.video.rawValue: ["compress-same", "convert-mp4", "convert-gif", "convert-mp3", "combine-mp4"],
        Kind.audio.rawValue: ["compress-same", "convert-mp3", "convert-m4a", "convert-wav"],
        Kind.pdf.rawValue: ["compress-same", "convert-docx", "convert-png", "convert-txt", "combine-pdf"],
        Kind.document.rawValue: ["convert-pdf", "convert-png"],
    ]

    private static func convert(_ f: FileFormat) -> String { "convert-\(f.rawValue)" }

    public static func kind(of format: FileFormat) -> Kind? {
        switch format.category {
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .document: format == .pdf ? .pdf : .document
        case .spreadsheet, .presentation: .document
        }
    }

    /// Menu title for a preset, or nil when it doesn't apply to this selection.
    public static func title(for id: String, fileCount: Int, singleFormat: FileFormat?) -> String? {
        switch id {
        case "open": return "Convert…"
        case "compress-same":
            guard let f = singleFormat, ConversionMatrix.compressible.contains(f) else { return nil }
            return "Make Smaller"
        case "combine-pdf": return fileCount > 1 ? "Combine into One PDF" : "→ PDF"
        case "combine-mp4": return fileCount > 1 ? "Join into One MP4" : nil
        case "extract-text": return "Extract Text"
        case "remove-background": return "Remove Background"
        default:
            guard id.hasPrefix("convert-"), let f = FileFormat(rawValue: String(id.dropFirst(8))) else { return nil }
            if f == singleFormat { return nil }
            let pages = singleFormat.map { $0.category != .image && $0.category != .video && f.category == .image } ?? false
            return "→ \(f.displayName)" + (pages ? " (pages)" : f == .mp3 && singleFormat?.category == .video ? " (audio)" : "")
        }
    }

    /// The submenu items (title, preset id) for a selection, using the user's configuration.
    public static func items(for urls: [URL], isFolder: Bool, config: Config?) -> [(title: String, id: String)] {
        if isFolder {
            return [("All Images → JPEG", "convert-jpeg"), ("All Images → PNG", "convert-png"), ("All Videos → MP4", "convert-mp4")]
        }
        let formats = urls.compactMap { FileFormat(url: $0) }
        guard formats.count == urls.count, let first = formats.first, let kind = kind(of: first),
              formats.allSatisfy({ Self.kind(of: $0) == kind })
        else { return [] }
        let single = Set(formats).count == 1 ? first : nil
        let ids = (config ?? defaults)[kind.rawValue] ?? defaults[kind.rawValue] ?? []
        return ids.compactMap { id in title(for: id, fileCount: urls.count, singleFormat: single).map { ($0, id) } }
    }

    // MARK: Wire format (a distributed notification's object must be a string)

    public static func encode(_ config: Config) -> String {
        (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public static func decode(_ string: String) -> Config? {
        string.data(using: .utf8).flatMap { try? JSONDecoder().decode(Config.self, from: $0) }
    }
}
