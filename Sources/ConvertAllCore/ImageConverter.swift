#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import Foundation
import ImageIO
#if canImport(AppKit)
import AppKit
#endif

public enum ConversionError: LocalizedError {
    case unreadable(String)
    case encoderUnavailable(ImageFormat)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn't read “\(name)” as an image."
        case .encoderUnavailable(let format):
            "\(format.displayName) export isn't available on this Mac. "
                + (ImageConverter.installHint(for: format) ?? "")
        case .writeFailed(let detail): "Saving failed: \(detail)"
        }
    }
}

/// Quick facts shown in the chip header.
public struct ImageInfo: Sendable {
    public let format: ImageFormat?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let byteCount: Int?
}

/// Decodes any supported image and re-encodes it in the target format.
///
/// Encoder resolution order:
///   1. Pure-Swift codecs (QOI, PPM, TGA) — always available.
///   2. ImageIO, if this macOS can write the format (JPEG, PNG, HEIC, TIFF, GIF, BMP, ICO, EXR, …).
///   3. A Homebrew command-line encoder for formats ImageIO can only read (WebP via
///      `cwebp`, AVIF via `avifenc`).
public enum ImageConverter {
    public static let defaultQuality = 0.85

    enum Encoder {
        case builtIn
        case imageIO(typeIdentifier: String)
        case external(executable: URL, arguments: (_ input: String, _ output: String, _ quality: Int) -> [String])
    }

    private static let imageIOWritable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func encoder(for format: ImageFormat) -> Encoder? {
        if format.hasBuiltInCodec { return .builtIn }
        if let uti = format.typeIdentifiers.first(where: imageIOWritable.contains) {
            return .imageIO(typeIdentifier: uti)
        }
        switch format {
        case .webp:
            if let tool = findTool("cwebp") {
                return .external(executable: tool) { input, output, q in ["-quiet", "-q", "\(q)", input, "-o", output] }
            }
        case .avif:
            if let tool = findTool("avifenc") {
                return .external(executable: tool) { input, output, q in ["-q", "\(q)", input, output] }
            }
        default: break
        }
        return nil
    }

    public static func canWrite(_ format: ImageFormat) -> Bool { encoder(for: format) != nil }

    /// Shown on a dimmed pill so users know how to unlock it.
    public static func installHint(for format: ImageFormat) -> String? {
        switch format {
        case .webp: "Install the encoder with: brew install webp"
        case .avif: "Install the encoder with: brew install libavif"
        default: nil
        }
    }

    private static func findTool(_ name: String) -> URL? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Inspecting

    public static func sourceFormat(of url: URL) -> ImageFormat? {
        if let f = ImageFormat(url: url) { return f }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(src) as String?
        else { return nil }
        return ImageFormat(typeIdentifier: uti)
    }

    public static func info(for url: URL) -> ImageInfo {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        var w: Int?, h: Int?
        if let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            w = props[kCGImagePropertyPixelWidth] as? Int
            h = props[kCGImagePropertyPixelHeight] as? Int
            if let o = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(o) { swap(&w, &h) }
        }
        return ImageInfo(format: sourceFormat(of: url), pixelWidth: w, pixelHeight: h, byteCount: size)
    }

    // MARK: - Converting

    /// Converts `source` and returns the URL of the new file (next to the original
    /// unless `destination` is given). Never overwrites existing files.
    @discardableResult
    public static func convert(
        _ source: URL,
        to format: ImageFormat,
        quality: Double = defaultQuality,
        destination: URL? = nil
    ) throws -> URL {
        guard let encoder = encoder(for: format) else { throw ConversionError.encoderUnavailable(format) }
        let (decoded, metadata) = try loadImage(at: source)
        var image = decoded
        if !format.supportsAlpha { image = try flattened(image) }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ConvertAll-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let tmp = work.appendingPathComponent("out").appendingPathExtension(format.preferredExtension)

        switch encoder {
        case .builtIn:
            let rgba = try rgbaImage(from: image)
            let bytes: [UInt8] = switch format {
            case .qoi: QOI.encode(rgba)
            case .tga: TGA.encode(rgba)
            default: PNM.encode(rgba)
            }
            try Data(bytes).write(to: tmp)

        case .imageIO(let uti):
            try writeWithImageIO(image, typeIdentifier: uti, format: format, metadata: metadata, quality: quality, to: tmp)

        case .external(let executable, let arguments):
            let png = work.appendingPathComponent("in.png")
            try writeWithImageIO(image, typeIdentifier: "public.png", format: .png, metadata: [:], quality: 1, to: png)
            try run(executable, arguments(png.path, tmp.path, Int((quality * 100).rounded())))
        }

        let dest = destination ?? OutputNaming.destination(for: source, format: format)
        do {
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            throw ConversionError.writeFailed(error.localizedDescription)
        }
        return dest
    }

    // MARK: - Decoding

    /// Returns the first frame, upright (EXIF orientation applied), plus the
    /// metadata worth carrying over.
    static func loadImage(at url: URL) throws -> (CGImage, [CFString: Any]) {
        let name = url.lastPathComponent

        if let format = ImageFormat(url: url), format.hasBuiltInCodec,
           let bytes = try? [UInt8](Data(contentsOf: url)) {
            let decoded: RGBAImage? = switch format {
            case .qoi: try? QOI.decode(bytes)
            case .tga: try? TGA.decode(bytes)
            default: try? PNM.decode(bytes)
            }
            if let decoded { return (try cgImage(from: decoded), [:]) }
            // Fall through: ImageIO might still understand it.
        }

        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 {
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            var image: CGImage?
            if orientation != 1 {
                let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(w, h),
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            }
            if image == nil {
                image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary)
            }
            if let image { return (image, preservedMetadata(props)) }
        }

        #if canImport(AppKit)
        // SVG and anything else AppKit can draw.
        if let ns = NSImage(contentsOf: url), ns.size.width > 0, ns.size.height > 0 {
            let longest = max(ns.size.width, ns.size.height)
            let scale = min(max(2, 2048 / longest), 8192 / longest)
            let w = Int((ns.size.width * scale).rounded()), h = Int((ns.size.height * scale).rounded())
            if let ctx = rgbaContext(width: w, height: h) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                ns.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
                NSGraphicsContext.restoreGraphicsState()
                if let image = ctx.makeImage() { return (image, [:]) }
            }
        }
        #endif

        throw ConversionError.unreadable(name)
    }

    /// Camera/location/copyright info survives; orientation is reset because pixels are already upright.
    private static func preservedMetadata(_ props: [CFString: Any]) -> [CFString: Any] {
        var out: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let v = props[key] { out[key] = v }
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            out[kCGImagePropertyTIFFDictionary] = tiff
        }
        out[kCGImagePropertyOrientation] = 1
        return out
    }

    // MARK: - Encoding

    private static func writeWithImageIO(
        _ image: CGImage, typeIdentifier: String, format: ImageFormat,
        metadata: [CFString: Any], quality: Double, to url: URL
    ) throws {
        let frames: [CGImage] = format == .ico ? try iconFrames(image) : [image]
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier as CFString, frames.count, nil) else {
            throw ConversionError.writeFailed("couldn't create a \(format.displayName) file")
        }
        let keepsMetadata: [ImageFormat] = [.jpeg, .heic, .tiff, .png, .avif]
        var props: [CFString: Any] = keepsMetadata.contains(format) ? metadata : [:]
        if format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = quality }
        for frame in frames { CGImageDestinationAddImage(dest, frame, props as CFDictionary) }
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.writeFailed("the \(format.displayName) encoder rejected this image")
        }
    }

    /// ICO files hold several square sizes ≤ 256 px; Windows and browsers pick the best fit.
    private static func iconFrames(_ image: CGImage) throws -> [CGImage] {
        let longest = max(image.width, image.height)
        let sizes = [256, 128, 64, 48, 32, 16].filter { $0 <= max(longest, 16) }
        return try sizes.map { side in
            guard let ctx = rgbaContext(width: side, height: side) else { throw ConversionError.writeFailed("out of memory") }
            ctx.interpolationQuality = .high
            let scale = Double(side) / Double(longest)
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            ctx.draw(image, in: CGRect(x: (Double(side) - w) / 2, y: (Double(side) - h) / 2, width: w, height: h))
            guard let frame = ctx.makeImage() else { throw ConversionError.writeFailed("couldn't render icon") }
            return frame
        }
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.writeFailed(msg?.isEmpty == false ? msg! : "\(executable.lastPathComponent) failed")
        }
    }

    // MARK: - Pixel plumbing

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func rgbaContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func flattened(_ image: CGImage) throws -> CGImage {
        // Keep wide-gamut (Display P3) photos in their own colour space when possible.
        let own = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
        func context(_ space: CGColorSpace) -> CGContext? {
            CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        }
        guard let ctx = own.flatMap(context) ?? context(sRGB) else { throw ConversionError.writeFailed("out of memory") }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        guard let out = ctx.makeImage() else { throw ConversionError.writeFailed("couldn't flatten transparency") }
        return out
    }

    static func rgbaImage(from image: CGImage) throws -> RGBAImage {
        let w = image.width, h = image.height
        guard let ctx = rgbaContext(width: w, height: h) else { throw ConversionError.writeFailed("out of memory") }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { throw ConversionError.writeFailed("out of memory") }
        let src = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var px = [UInt8](UnsafeBufferPointer(start: src, count: w * h * 4))
        for i in stride(from: 0, to: px.count, by: 4) {  // un-premultiply
            let a = Int(px[i + 3])
            guard a != 0, a != 255 else { continue }
            for c in 0..<3 { px[i + c] = UInt8(min(255, (Int(px[i + c]) * 255 + a / 2) / a)) }
        }
        return try RGBAImage(width: w, height: h, pixels: px)
    }

    static func cgImage(from rgba: RGBAImage) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(rgba.pixels) as CFData),
              let image = CGImage(
                  width: rgba.width, height: rgba.height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: rgba.width * 4, space: sRGB,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw ConversionError.writeFailed("couldn't build image") }
        return image
    }
}
#endif
