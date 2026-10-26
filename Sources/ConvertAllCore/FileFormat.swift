import Foundation

/// The chip's sections. Order here is the order sections appear in.
public enum FormatCategory: String, CaseIterable, Codable, Sendable {
    case image, video, audio, document, spreadsheet, presentation

    public var title: String {
        switch self {
        case .image: "Images"
        case .video: "Video"
        case .audio: "Audio"
        case .document: "Documents"
        case .spreadsheet: "Spreadsheets"
        case .presentation: "Presentations"
        }
    }

    /// Plural noun for multi-file headers ("3 videos").
    public var noun: String {
        switch self {
        case .image: "images"
        case .video: "videos"
        case .audio: "audio files"
        case .document: "documents"
        case .spreadsheet: "spreadsheets"
        case .presentation: "presentations"
        }
    }
}

/// Every format ConvertAll knows about — the full list from convt.app/formats.
public enum FileFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    // Images
    case jpeg, png, webp, heic, avif, gif, tiff, bmp, ico, tga, pnm, qoi, exr, svg
    // Video
    case mp4, mov, webm, mkv, avi
    // Audio
    case mp3, wav, flac, aac, m4a, ogg, opus
    // Documents
    case pdf, docx, doc, odt, rtf, txt, html
    // Spreadsheets
    case xlsx, xls, ods, csv
    // Presentations
    case pptx, ppt, odp

    public var id: String { rawValue }

    public var category: FormatCategory {
        switch self {
        case .jpeg, .png, .webp, .heic, .avif, .gif, .tiff, .bmp, .ico, .tga, .pnm, .qoi, .exr, .svg: .image
        case .mp4, .mov, .webm, .mkv, .avi: .video
        case .mp3, .wav, .flac, .aac, .m4a, .ogg, .opus: .audio
        case .pdf, .docx, .doc, .odt, .rtf, .txt, .html: .document
        case .xlsx, .xls, .ods, .csv: .spreadsheet
        case .pptx, .ppt, .odp: .presentation
        }
    }

    /// Short label shown on the chip's pills.
    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .webp: "WebP"
        case .heic: "HEIC"
        case .avif: "AVIF"
        case .gif: "GIF"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        case .ico: "ICO"
        case .tga: "TGA"
        case .pnm: "PPM"
        case .qoi: "QOI"
        case .exr: "EXR"
        case .svg: "SVG"
        case .mp4: "MP4"
        case .mov: "MOV"
        case .webm: "WebM"
        case .mkv: "MKV"
        case .avi: "AVI"
        case .mp3: "MP3"
        case .wav: "WAV"
        case .flac: "FLAC"
        case .aac: "AAC"
        case .m4a: "M4A"
        case .ogg: "OGG"
        case .opus: "Opus"
        case .pdf: "PDF"
        case .docx: "DOCX"
        case .doc: "DOC"
        case .odt: "ODT"
        case .rtf: "RTF"
        case .txt: "TXT"
        case .html: "HTML"
        case .xlsx: "XLSX"
        case .xls: "XLS"
        case .ods: "ODS"
        case .csv: "CSV"
        case .pptx: "PPTX"
        case .ppt: "PPT"
        case .odp: "ODP"
        }
    }

    /// One-line hint shown under the grid, so users know what they're picking.
    public var blurb: String {
        switch self {
        case .jpeg: "Photos · small, universal"
        case .png: "Lossless · keeps transparency"
        case .webp: "Web · small with transparency"
        case .heic: "Apple photos · very small"
        case .avif: "Next-gen web · smallest"
        case .gif: "Simple graphics · 256 colors"
        case .tiff: "Print & archival · lossless"
        case .bmp: "Uncompressed bitmap"
        case .ico: "Windows & favicon icon"
        case .tga: "Games & 3D textures"
        case .pnm: "Netpbm · plain pixels"
        case .qoi: "Quite OK Image · fast lossless"
        case .exr: "HDR · VFX pipelines"
        case .svg: "Vector graphics"
        case .mp4: "Plays everywhere · H.264"
        case .mov: "QuickTime · Apple apps"
        case .webm: "Web video · VP9 + Opus"
        case .mkv: "Flexible container · keeps all tracks"
        case .avi: "Legacy Windows video"
        case .mp3: "Universal audio"
        case .wav: "Uncompressed · editing"
        case .flac: "Lossless · half the size of WAV"
        case .aac: "Small, good quality"
        case .m4a: "Apple Music & iPhone"
        case .ogg: "Open format · Vorbis"
        case .opus: "Best quality per byte · voice & music"
        case .pdf: "Looks the same everywhere"
        case .docx: "Microsoft Word"
        case .doc: "Word 97–2003"
        case .odt: "LibreOffice / OpenDocument"
        case .rtf: "Rich text · opens in any editor"
        case .txt: "Just the words"
        case .html: "Web page"
        case .xlsx: "Microsoft Excel"
        case .xls: "Excel 97–2003"
        case .ods: "LibreOffice Calc"
        case .csv: "Plain table · first sheet"
        case .pptx: "Microsoft PowerPoint"
        case .ppt: "PowerPoint 97–2003"
        case .odp: "LibreOffice Impress"
        }
    }

    /// File extensions, preferred one first.
    public var fileExtensions: [String] {
        switch self {
        case .jpeg: ["jpg", "jpeg", "jfif", "jpe"]
        case .png: ["png"]
        case .webp: ["webp"]
        case .heic: ["heic", "heif", "hif"]
        case .avif: ["avif"]
        case .gif: ["gif"]
        case .tiff: ["tiff", "tif"]
        case .bmp: ["bmp", "dib"]
        case .ico: ["ico"]
        case .tga: ["tga", "targa"]
        case .pnm: ["ppm", "pgm", "pbm", "pnm"]
        case .qoi: ["qoi"]
        case .exr: ["exr"]
        case .svg: ["svg"]
        case .mp4: ["mp4", "m4v"]
        case .mov: ["mov", "qt"]
        case .webm: ["webm"]
        case .mkv: ["mkv"]
        case .avi: ["avi"]
        case .mp3: ["mp3"]
        case .wav: ["wav", "wave"]
        case .flac: ["flac"]
        case .aac: ["aac"]
        case .m4a: ["m4a"]
        case .ogg: ["ogg", "oga"]
        case .opus: ["opus"]
        case .pdf: ["pdf"]
        case .docx: ["docx"]
        case .doc: ["doc"]
        case .odt: ["odt"]
        case .rtf: ["rtf"]
        case .txt: ["txt", "text"]
        case .html: ["html", "htm"]
        case .xlsx: ["xlsx"]
        case .xls: ["xls"]
        case .ods: ["ods"]
        case .csv: ["csv"]
        case .pptx: ["pptx"]
        case .ppt: ["ppt"]
        case .odp: ["odp"]
        }
    }

    public var preferredExtension: String { fileExtensions[0] }

    /// Uniform Type Identifiers (ImageIO uses these for images).
    public var typeIdentifiers: [String] {
        switch self {
        case .jpeg: ["public.jpeg"]
        case .png: ["public.png"]
        case .webp: ["org.webmproject.webp", "public.webp"]
        case .heic: ["public.heic", "public.heif"]
        case .avif: ["public.avif"]
        case .gif: ["com.compuserve.gif"]
        case .tiff: ["public.tiff"]
        case .bmp: ["com.microsoft.bmp"]
        case .ico: ["com.microsoft.ico"]
        case .tga: ["com.truevision.tga-image"]
        case .pnm: ["public.pbm", "public.pgm", "public.ppm", "public.pnm"]
        case .qoi: ["org.qoiformat.qoi"]
        case .exr: ["com.ilm.openexr-image"]
        case .svg: ["public.svg-image"]
        case .mp4: ["public.mpeg-4", "com.apple.m4v-video"]
        case .mov: ["com.apple.quicktime-movie"]
        case .webm: ["org.webmproject.webm"]
        case .mkv: ["org.matroska.mkv"]
        case .avi: ["public.avi"]
        case .mp3: ["public.mp3"]
        case .wav: ["com.microsoft.waveform-audio"]
        case .flac: ["org.xiph.flac"]
        case .aac: ["public.aac-audio"]
        case .m4a: ["com.apple.m4a-audio"]
        case .ogg: ["org.xiph.ogg-audio", "org.xiph.ogg"]
        case .opus: ["org.xiph.opus"]
        case .pdf: ["com.adobe.pdf"]
        case .docx: ["org.openxmlformats.wordprocessingml.document"]
        case .doc: ["com.microsoft.word.doc"]
        case .odt: ["org.oasis-open.opendocument.text"]
        case .rtf: ["public.rtf"]
        case .txt: ["public.plain-text"]
        case .html: ["public.html"]
        case .xlsx: ["org.openxmlformats.spreadsheetml.sheet"]
        case .xls: ["com.microsoft.excel.xls"]
        case .ods: ["org.oasis-open.opendocument.spreadsheet"]
        case .csv: ["public.comma-separated-values-text"]
        case .pptx: ["org.openxmlformats.presentationml.presentation"]
        case .ppt: ["com.microsoft.powerpoint.ppt"]
        case .odp: ["org.oasis-open.opendocument.presentation"]
        }
    }

    /// Extra words people type when they look for a format.
    public var searchAliases: [String] {
        switch self {
        case .jpeg: ["jpg", "photo", "joint photographic"]
        case .png: ["portable network graphics", "lossless", "transparent"]
        case .webp: ["web", "google"]
        case .heic: ["heif", "iphone", "apple", "live"]
        case .avif: ["av1"]
        case .gif: ["animation", "graphics interchange", "meme"]
        case .tiff: ["tif", "print", "scan"]
        case .bmp: ["bitmap", "windows"]
        case .ico: ["icon", "favicon"]
        case .tga: ["targa", "texture", "truevision"]
        case .pnm: ["ppm", "pgm", "pbm", "netpbm", "portable pixmap"]
        case .qoi: ["quite ok"]
        case .exr: ["openexr", "hdr", "vfx"]
        case .svg: ["vector"]
        case .mp4: ["m4v", "h264", "video", "mpeg"]
        case .mov: ["quicktime", "apple video"]
        case .webm: ["vp9", "web video"]
        case .mkv: ["matroska"]
        case .avi: ["divx", "xvid"]
        case .mp3: ["mpeg audio", "song", "music"]
        case .wav: ["wave", "uncompressed", "pcm"]
        case .flac: ["lossless audio", "free lossless"]
        case .aac: ["advanced audio"]
        case .m4a: ["itunes", "apple audio"]
        case .ogg: ["vorbis", "oga"]
        case .opus: ["voice", "podcast"]
        case .pdf: ["acrobat", "portable document", "print"]
        case .docx: ["word", "microsoft word"]
        case .doc: ["word 97", "old word"]
        case .odt: ["opendocument text", "libreoffice writer"]
        case .rtf: ["rich text", "wordpad"]
        case .txt: ["text", "plain"]
        case .html: ["htm", "web page", "website"]
        case .xlsx: ["excel", "spreadsheet"]
        case .xls: ["old excel"]
        case .ods: ["calc", "opendocument spreadsheet"]
        case .csv: ["comma", "table", "data"]
        case .pptx: ["powerpoint", "slides", "keynote"]
        case .ppt: ["old powerpoint"]
        case .odp: ["impress", "opendocument presentation"]
        }
    }

    // MARK: Image-specific traits

    /// Whether the encoded file can carry an alpha channel. Used to flatten
    /// transparent pixels onto white when exporting to formats that can't.
    public var supportsAlpha: Bool {
        switch self {
        case .jpeg, .pnm: false
        default: true
        }
    }

    /// Lossy formats get a quality setting.
    public var isLossy: Bool {
        switch self {
        case .jpeg, .webp, .heic, .avif: true
        default: false
        }
    }

    /// Formats implemented in pure Swift (no ImageIO needed).
    public var hasBuiltInCodec: Bool {
        switch self {
        case .qoi, .pnm, .tga: true
        default: false
        }
    }

    // MARK: Lookup

    /// Resolve a format from a file extension (case-insensitive, leading dot allowed).
    public init?(fileExtension ext: String) {
        let ext = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let match = FileFormat.allCases.first(where: { $0.fileExtensions.contains(ext) }) else {
            return nil
        }
        self = match
    }

    public init?(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }

    /// Resolve from a UTI string (e.g. what ImageIO reports for a source).
    public init?(typeIdentifier: String) {
        guard let match = FileFormat.allCases.first(where: { $0.typeIdentifiers.contains(typeIdentifier) }) else {
            return nil
        }
        self = match
    }
}
