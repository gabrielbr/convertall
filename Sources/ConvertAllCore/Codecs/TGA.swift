import Foundation

/// Truevision TGA. Writes RLE-compressed 32-bit BGRA with a TGA 2.0 footer;
/// reads uncompressed and RLE true-colour, greyscale and colour-mapped images.
public enum TGA {
    public static func encode(_ image: RGBAImage) -> [UInt8] {
        var out: [UInt8] = [
            0,  // ID length
            0,  // no colour map
            10,  // RLE true-colour
            0, 0, 0, 0, 0,  // colour map spec
            0, 0, 0, 0,  // x/y origin
            UInt8(image.width & 0xFF), UInt8(image.width >> 8 & 0xFF),
            UInt8(image.height & 0xFF), UInt8(image.height >> 8 & 0xFF),
            32,  // bits per pixel
            0x28,  // 8 alpha bits, top-left origin
        ]
        let px = image.pixels
        func bgra(_ p: Int) -> [UInt8] { [px[p * 4 + 2], px[p * 4 + 1], px[p * 4], px[p * 4 + 3]] }
        func same(_ a: Int, _ b: Int) -> Bool {
            px[a * 4] == px[b * 4] && px[a * 4 + 1] == px[b * 4 + 1]
                && px[a * 4 + 2] == px[b * 4 + 2] && px[a * 4 + 3] == px[b * 4 + 3]
        }

        // Packets must not cross scanlines (TGA spec recommendation).
        for y in 0..<image.height {
            let rowStart = y * image.width, rowEnd = rowStart + image.width
            var i = rowStart
            while i < rowEnd {
                var run = 1
                while i + run < rowEnd, run < 128, same(i, i + run) { run += 1 }
                if run > 1 {
                    out.append(0x80 | UInt8(run - 1))
                    out += bgra(i)
                    i += run
                } else {
                    var raw = 1
                    while i + raw < rowEnd, raw < 128, !(i + raw + 1 < rowEnd && same(i + raw, i + raw + 1)) {
                        raw += 1
                    }
                    out.append(UInt8(raw - 1))
                    for p in i..<(i + raw) { out += bgra(p) }
                    i += raw
                }
            }
        }
        out += [UInt8](repeating: 0, count: 8)  // extension + developer area offsets
        out += Array("TRUEVISION-XFILE.".utf8) + [0]
        return out
    }

    public static func decode(_ bytes: [UInt8]) throws -> RGBAImage {
        var r = ByteReader(bytes)
        let idLength = Int(try r.u8())
        let colorMapType = try r.u8()
        let imageType = try r.u8()
        let cmapFirst = try r.u16le(), cmapLength = try r.u16le()
        let cmapDepth = Int(try r.u8())
        try r.skip(4)  // origin
        let width = try r.u16le(), height = try r.u16le()
        let depth = Int(try r.u8())
        let descriptor = try r.u8()

        guard [1, 2, 3, 9, 10, 11].contains(imageType) else {
            throw imageType == 0 ? CodecError.invalidSignature : CodecError.unsupportedVariant("type \(imageType)")
        }
        guard width > 0, height > 0 else { throw CodecError.invalidDimensions(width, height) }
        let isMapped = imageType == 1 || imageType == 9
        let isGray = imageType == 3 || imageType == 11
        let isRLE = imageType >= 9
        try r.skip(idLength)

        func readColor(depth: Int, gray: Bool) throws -> (UInt8, UInt8, UInt8, UInt8) {
            switch (depth, gray) {
            case (8, true): let v = try r.u8(); return (v, v, v, 255)
            case (16, true): let v = try r.u8(); let a = try r.u8(); return (v, v, v, a)
            case (15, false), (16, false):
                let v = try r.u16le()
                func expand(_ c: Int) -> UInt8 { UInt8((c << 3) | (c >> 2)) }
                return (expand(v >> 10 & 0x1F), expand(v >> 5 & 0x1F), expand(v & 0x1F), 255)
            case (24, false):
                let b = try r.u8(), g = try r.u8(), rr = try r.u8(); return (rr, g, b, 255)
            case (32, false):
                let b = try r.u8(), g = try r.u8(), rr = try r.u8(), a = try r.u8(); return (rr, g, b, a)
            default: throw CodecError.unsupportedVariant("\(depth)-bit")
            }
        }

        var palette: [(UInt8, UInt8, UInt8, UInt8)] = []
        if colorMapType == 1 {
            if isMapped {
                for _ in 0..<cmapLength { palette.append(try readColor(depth: cmapDepth, gray: false)) }
            } else {
                try r.skip(cmapLength * ((cmapDepth + 7) / 8))
            }
        }
        if isMapped, palette.isEmpty { throw CodecError.unsupportedVariant("missing palette") }

        func readPixel() throws -> (UInt8, UInt8, UInt8, UInt8) {
            if isMapped {
                let idx = (depth == 16 ? try r.u16le() : Int(try r.u8())) - cmapFirst
                guard palette.indices.contains(idx) else { throw CodecError.truncated }
                return palette[idx]
            }
            return try readColor(depth: depth, gray: isGray)
        }

        let count = width * height
        var linear = [(UInt8, UInt8, UInt8, UInt8)]()
        linear.reserveCapacity(count)
        while linear.count < count {
            if isRLE {
                let header = try r.u8()
                let n = Int(header & 0x7F) + 1
                if header & 0x80 != 0 {
                    let p = try readPixel()
                    for _ in 0..<n where linear.count < count { linear.append(p) }
                } else {
                    for _ in 0..<n where linear.count < count { linear.append(try readPixel()) }
                }
            } else {
                linear.append(try readPixel())
            }
        }

        // Some writers leave the alpha byte zeroed; treat an all-zero alpha as opaque.
        let alphaUnused = linear.allSatisfy { $0.3 == 0 }
        let topToBottom = descriptor & 0x20 != 0
        let rightToLeft = descriptor & 0x10 != 0
        var out = [UInt8](repeating: 0, count: count * 4)
        for sy in 0..<height {
            let dy = topToBottom ? sy : height - 1 - sy
            for sx in 0..<width {
                let dx = rightToLeft ? width - 1 - sx : sx
                let p = linear[sy * width + sx]
                let o = (dy * width + dx) * 4
                out[o] = p.0; out[o + 1] = p.1; out[o + 2] = p.2; out[o + 3] = alphaUnused ? 255 : p.3
            }
        }
        return try RGBAImage(width: width, height: height, pixels: out)
    }
}
