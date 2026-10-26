import Foundation

/// A plain 8-bit RGBA bitmap, straight (non-premultiplied) alpha, rows top to bottom.
/// This is the hand-off format between ImageIO and the pure-Swift codecs.
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    /// Anything bigger is almost certainly a corrupt header, not a real image.
    public static let maxPixelCount = 1 << 28

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0, width.multipliedReportingOverflow(by: height).partialValue <= Self.maxPixelCount
        else { throw CodecError.invalidDimensions(width, height) }
        guard pixels.count == width * height * 4 else { throw CodecError.truncated }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public var hasTransparency: Bool {
        stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] != 255 }
    }

    /// Composite onto a solid background (default white) and make fully opaque.
    /// Used before writing formats without alpha so transparent areas don't turn black.
    public func flattened(red: UInt8 = 255, green: UInt8 = 255, blue: UInt8 = 255) -> RGBAImage {
        var out = self
        let bg = [Int(red), Int(green), Int(blue)]
        for i in stride(from: 0, to: out.pixels.count, by: 4) {
            let a = Int(out.pixels[i + 3])
            if a == 255 { continue }
            for c in 0..<3 {
                out.pixels[i + c] = UInt8((Int(out.pixels[i + c]) * a + bg[c] * (255 - a) + 127) / 255)
            }
            out.pixels[i + 3] = 255
        }
        return out
    }
}

public enum CodecError: Error, Equatable, LocalizedError {
    case invalidSignature
    case unsupportedVariant(String)
    case invalidDimensions(Int, Int)
    case truncated

    public var errorDescription: String? {
        switch self {
        case .invalidSignature: "This file doesn't look like the format its name says."
        case .unsupportedVariant(let what): "This flavour of the format isn't supported (\(what))."
        case .invalidDimensions(let w, let h): "The image size \(w)×\(h) is invalid."
        case .truncated: "The file is incomplete or damaged."
        }
    }
}

/// Little helpers for reading binary headers safely.
struct ByteReader {
    let data: [UInt8]
    var offset = 0

    init(_ data: [UInt8]) { self.data = data }

    var isAtEnd: Bool { offset >= data.count }

    mutating func u8() throws -> UInt8 {
        guard offset < data.count else { throw CodecError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func u16le() throws -> Int {
        let lo = Int(try u8()), hi = Int(try u8())
        return lo | hi << 8
    }

    mutating func u32be() throws -> Int {
        var v = 0
        for _ in 0..<4 { v = v << 8 | Int(try u8()) }
        return v
    }

    mutating func skip(_ n: Int) throws {
        guard n >= 0, offset + n <= data.count else { throw CodecError.truncated }
        offset += n
    }
}
