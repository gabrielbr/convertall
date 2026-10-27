#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Quick facts shown in the chip header.
public struct FileInfo: Sendable {
    public let format: FileFormat?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let byteCount: Int?
}

/// Decodes any supported image and re-encodes it in the target format.
///
/// Encoder resolution order:
///   1. Pure-Swift codecs (QOI, PPM, TGA) — always available.
///   2. ImageIO, if this macOS can write the format (JPEG, PNG, HEIC, TIFF, GIF, BMP, ICO, EXR, …).
///   3. For formats macOS can only read (WebP, AVIF): Homebrew `cwebp`/`avifenc`,
///      or the FFmpeg media engine (which ships libwebp and AV1).
public enum ImageConverter {
    public static let defaultQuality = 0.85

    enum Encoder {
        case builtIn
        case imageIO(typeIdentifier: String)
        case external(executable: URL, arguments: (_ input: String, _ output: String, _ quality: Int) -> [String])
        case ffmpeg
    }

    private static let imageIOWritable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func encoder(for format: FileFormat) -> Encoder? {
        guard format.category == .image else { return nil }
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
        if (format == .webp || format == .avif), MediaEngine.ffmpegURL != nil { return .ffmpeg }
        return nil
    }

    public static func canWrite(_ format: FileFormat) -> Bool { encoder(for: format) != nil }

    /// WebP/AVIF can be unlocked by the media engine; everything else is always writable.
    public static func needsMediaEngine(_ format: FileFormat) -> Bool {
        (format == .webp || format == .avif) && !canWrite(format)
    }

    static func findTool(_ name: String) -> URL? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Inspecting

    public static func info(for url: URL) -> FileInfo {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let format = Converter.sourceFormat(of: url)
        var w: Int?, h: Int?
        if format?.category == .image,
           let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            w = props[kCGImagePropertyPixelWidth] as? Int
            h = props[kCGImagePropertyPixelHeight] as? Int
            if let o = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(o) { swap(&w, &h) }
        }
        return FileInfo(format: format, pixelWidth: w, pixelHeight: h, byteCount: size)
    }

    // MARK: - Converting

    /// Converts `source` and returns the URL of the new file (next to the original
    /// unless `destination` is given). Never overwrites existing files.
    @discardableResult
    public static func convert(
        _ source: URL,
        to format: FileFormat,
        options: ConversionOptions = ConversionOptions(),
        compress: Bool? = nil,
        destination: URL? = nil
    ) throws -> URL {
        guard encoder(for: format) != nil else { throw ConversionError.engineMissing(format) }
        let compress = compress ?? (FileFormat(url: source) == format)
        let destination = destination ?? OutputNaming.destination(for: source, format: format)
        // Animated GIF/WebP/APNG/HEICS → GIF or APNG keeps every frame.
        if !compress, format == .gif || format == .png, frameCount(source) > 1 {
            return try exportAnimation(from: source, as: format, to: destination, options: options)
        }
        let (image, metadata) = try loadImage(at: source)
        return try export(image, as: format, to: destination, metadata: metadata, options: options, compress: compress)
    }

    /// Encodes an already-decoded image (a video frame, a PDF page, …) to `destination`,
    /// applying the size, quality and metadata options.
    @discardableResult
    static func export(
        _ decoded: CGImage, as format: FileFormat, to destination: URL,
        metadata: [CFString: Any] = [:], options: ConversionOptions = ConversionOptions(), compress: Bool = false
    ) throws -> URL {
        guard let encoder = encoder(for: format) else { throw ConversionError.engineMissing(format) }
        let viaFFmpeg: Bool = { if case .ffmpeg = encoder { return true }; return false }()
        var image = try resized(decoded, to: options.size)
        if !format.supportsAlpha || (format == .avif && viaFFmpeg) { image = try flattened(image) }
        let metadata = options.stripMetadata ? [:] : metadata
        // Lossy PNG quantisation needs FFmpeg; without it PNG compression is a plain re-encode.
        let quantizePNG = format == .png && compress && options.quality != .best && MediaEngine.ffmpegURL != nil

        let work = try WorkDirectory()
        defer { work.remove() }
        var attempt = 0

        func encode(_ image: CGImage, quality: Double) throws -> URL {
            attempt += 1
            let out = work.file("out-\(attempt).\(format.preferredExtension)")
            if quantizePNG {
                let png = work.file("in-\(attempt).png")
                try writeWithImageIO(image, typeIdentifier: "public.png", format: .png, metadata: [:], quality: 1, to: png)
                try MediaEngine.encodeImage(png, arguments: FFmpeg.pngQuantizeArguments(colors: options.quality == .smaller ? 96 : 256), to: out)
                return out
            }
            switch encoder {
            case .builtIn:
                let rgba = try rgbaImage(from: image)
                let bytes: [UInt8] = switch format {
                case .qoi: QOI.encode(rgba)
                case .tga: TGA.encode(rgba)
                default: PNM.encode(rgba)
                }
                try Data(bytes).write(to: out)

            case .imageIO(let uti):
                try writeWithImageIO(image, typeIdentifier: uti, format: format, metadata: metadata, quality: quality, to: out)

            case .external(let executable, let arguments):
                let png = work.file("in-\(attempt).png")
                try writeWithImageIO(image, typeIdentifier: "public.png", format: .png, metadata: [:], quality: 1, to: png)
                let result = try ProcessRunner.run(executable, arguments(png.path, out.path, Int((quality * 100).rounded())))
                guard result.status == 0 else { throw ConversionError.writeFailed(FFmpeg.errorSummary(result.output)) }

            case .ffmpeg:
                let png = work.file("in-\(attempt).png")
                try writeWithImageIO(image, typeIdentifier: "public.png", format: .png, metadata: [:], quality: 1, to: png)
                try MediaEngine.encodeImage(png, arguments: FFmpeg.stillImageArguments(for: format, quality: quality), to: out)
            }
            return out
        }

        guard let target = options.size.targetBytes else {
            return try deliver(encode(image, quality: options.imageQuality(compress: compress)), to: destination)
        }

        // "Under X MB": step quality down first (lossy formats), then shrink the pixels.
        let qualities = format.isLossy ? [0.85, 0.72, 0.6, 0.48, 0.36] : [1.0]
        var best: (url: URL, size: Int)?
        var current = image
        search: for _ in 0..<6 {
            for q in qualities {
                let out = try encode(current, quality: q)
                let size = fileSize(out)
                if best == nil || size < best!.size { best = (out, size) }
                if size <= target { break search }
            }
            guard min(current.width, current.height) > 32 else { break }
            current = try resized(current, to: .maxDimension(max(current.width, current.height) * 3 / 4))
        }
        return try deliver(best!.url, to: destination)
    }

    // MARK: - Animation

    public static func frameCount(_ url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return 0 }
        return CGImageSourceGetCount(src)
    }

    /// Per-frame delay from whichever animation dictionary the source uses.
    private static func frameDelay(_ props: [CFString: Any]) -> Double {
        let sources: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dict, unclamped, clamped) in sources {
            guard let d = props[dict] as? [CFString: Any] else { continue }
            let value = (d[unclamped] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? (d[clamped] as? Double) ?? 0
            return value >= 0.02 ? value : 0.1  // browsers treat tiny delays as 100 ms
        }
        return 0.1
    }

    static let maxFrames = 2000

    private static func exportAnimation(
        from source: URL, as format: FileFormat, to destination: URL, options: ConversionOptions
    ) throws -> URL {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ConversionError.unreadable(source.lastPathComponent)
        }
        let count = min(CGImageSourceGetCount(src), maxFrames)
        let work = try WorkDirectory()
        defer { work.remove() }
        let out = work.file("out.\(format.preferredExtension)")
        let uti = format == .gif ? "com.compuserve.gif" : "public.png"
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, count, nil) else {
            throw ConversionError.writeFailed("couldn't create the animation")
        }
        let loop: [CFString: Any] = format == .gif
            ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
            : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]]
        CGImageDestinationSetProperties(dest, loop as CFDictionary)
        for i in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let delay = frameDelay(CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] ?? [:])
            let props: [CFString: Any] = format == .gif
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
                : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]]
            CGImageDestinationAddImage(dest, try resized(frame, to: options.size), props as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw ConversionError.writeFailed("couldn't write the animation") }
        return try deliver(out, to: destination)
    }

    public static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    /// High-quality downscale for the Size option (never upscales).
    static func resized(_ image: CGImage, to size: ConversionOptions.Size) throws -> CGImage {
        let (w, h) = size.scaled(width: image.width, height: image.height)
        guard w != image.width || h != image.height else { return image }
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? sRGB
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ?? rgbaContext(width: w, height: h)
        else { throw ConversionError.writeFailed("out of memory") }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw ConversionError.writeFailed("couldn't resize") }
        return out
    }

    // MARK: - Decoding

    /// Returns the first frame, upright (EXIF orientation applied), plus the
    /// metadata worth carrying over.
    static func loadImage(at url: URL) throws -> (CGImage, [CFString: Any]) {
        let name = url.lastPathComponent

        if let format = FileFormat(url: url), format.hasBuiltInCodec,
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
        _ image: CGImage, typeIdentifier: String, format: FileFormat,
        metadata: [CFString: Any], quality: Double, to url: URL
    ) throws {
        let frames: [CGImage] = format == .ico ? try iconFrames(image) : [image]
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier as CFString, frames.count, nil) else {
            throw ConversionError.writeFailed("couldn't create a \(format.displayName) file")
        }
        let keepsMetadata: [FileFormat] = [.jpeg, .heic, .tiff, .png, .avif]
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

    // MARK: - Pixel plumbing

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func rgbaContext(width: Int, height: Int) -> CGContext? {
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
