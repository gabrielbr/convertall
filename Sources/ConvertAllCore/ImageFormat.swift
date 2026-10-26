import Foundation

/// Every image format ConvertAll knows about (the "Images" column of convt.app/formats).
///
/// A format can be readable, writable, or both. Whether a given format is actually
/// available on this Mac is decided at runtime by `ImageConverter` (ImageIO support
/// varies across macOS versions; WebP/AVIF encoding may come from a helper tool).
public enum ImageFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case jpeg, png, webp, heic, avif, gif, tiff, bmp, ico, tga, pnm, qoi, exr, svg

    public var id: String { rawValue }

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
        }
    }

    /// One-line hint shown under the selected pill, so users know what they're picking.
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
        }
    }

    public var preferredExtension: String { fileExtensions[0] }

    /// Uniform Type Identifiers used by ImageIO for this format.
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
        case .gif: ["animation", "graphics interchange"]
        case .tiff: ["tif", "print", "scan"]
        case .bmp: ["bitmap", "windows"]
        case .ico: ["icon", "favicon"]
        case .tga: ["targa", "texture", "truevision"]
        case .pnm: ["ppm", "pgm", "pbm", "netpbm", "portable pixmap"]
        case .qoi: ["quite ok"]
        case .exr: ["openexr", "hdr", "vfx"]
        case .svg: ["vector"]
        }
    }

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

    /// SVG is input-only, matching convt.app.
    public var isOutputCandidate: Bool { self != .svg }

    /// Formats implemented in pure Swift (no ImageIO needed).
    public var hasBuiltInCodec: Bool {
        switch self {
        case .qoi, .pnm, .tga: true
        default: false
        }
    }

    /// Default output ordering: the formats people pick most come first.
    public static let popularityOrder: [ImageFormat] = [
        .png, .jpeg, .webp, .heic, .avif, .gif, .tiff, .ico, .bmp, .tga, .exr, .qoi, .pnm,
    ]

    /// Resolve a format from a file URL's extension (case-insensitive).
    public init?(fileExtension ext: String) {
        let ext = ext.lowercased()
        guard let match = ImageFormat.allCases.first(where: { $0.fileExtensions.contains(ext) }) else {
            return nil
        }
        self = match
    }

    public init?(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }

    /// Resolve from a UTI string (e.g. what ImageIO reports for a source).
    public init?(typeIdentifier: String) {
        guard let match = ImageFormat.allCases.first(where: { $0.typeIdentifiers.contains(typeIdentifier) }) else {
            return nil
        }
        self = match
    }
}
