import Foundation

/// Netpbm family: PBM (P1/P4), PGM (P2/P5), PPM (P3/P6).
/// We read all six variants and write binary PPM (P6), the common denominator.
public enum PNM {
    public static func encode(_ image: RGBAImage) -> [UInt8] {
        var out = Array("P6\n\(image.width) \(image.height)\n255\n".utf8)
        out.reserveCapacity(out.count + image.width * image.height * 3)
        let px = image.pixels
        for i in stride(from: 0, to: px.count, by: 4) {
            out += [px[i], px[i + 1], px[i + 2]]
        }
        return out
    }

    public static func decode(_ bytes: [UInt8]) throws -> RGBAImage {
        guard bytes.count >= 2, bytes[0] == UInt8(ascii: "P"),
              let kind = Int(String(UnicodeScalar(bytes[1]))), (1...6).contains(kind)
        else { throw CodecError.invalidSignature }

        var pos = 2
        func token() throws -> Int {
            // Skip whitespace and `#` comments, then read a decimal number.
            while pos < bytes.count {
                let c = bytes[pos]
                if c == UInt8(ascii: "#") {
                    while pos < bytes.count, bytes[pos] != 0x0A, bytes[pos] != 0x0D { pos += 1 }
                } else if c == 0x20 || (0x09...0x0D).contains(c) {
                    pos += 1
                } else { break }
            }
            var value = 0, digits = 0
            while pos < bytes.count, (0x30...0x39).contains(bytes[pos]), digits < 9 {
                value = value * 10 + Int(bytes[pos] - 0x30)
                pos += 1; digits += 1
            }
            guard digits > 0 else { throw CodecError.truncated }
            return value
        }

        let width = try token(), height = try token()
        let isBitmap = kind == 1 || kind == 4
        let maxval = isBitmap ? 1 : try token()
        guard (1...65535).contains(maxval) else { throw CodecError.unsupportedVariant("maxval \(maxval)") }
        guard width > 0, height > 0, width.multipliedReportingOverflow(by: height).partialValue <= RGBAImage.maxPixelCount
        else { throw CodecError.invalidDimensions(width, height) }

        let ascii = kind <= 3
        let samplesPerPixel = (kind == 3 || kind == 6) ? 3 : 1
        let count = width * height
        var out = [UInt8](repeating: 255, count: count * 4)

        func scale(_ v: Int) -> UInt8 { UInt8(min(v, maxval) * 255 / maxval) }

        if !ascii { pos += 1 }  // exactly one whitespace byte after the header

        if kind == 4 {
            let rowBytes = (width + 7) / 8
            guard pos + rowBytes * height <= bytes.count else { throw CodecError.truncated }
            for y in 0..<height {
                for x in 0..<width {
                    let bit = bytes[pos + y * rowBytes + x / 8] >> (7 - UInt8(x % 8)) & 1
                    let v: UInt8 = bit == 1 ? 0 : 255  // 1 = black in PBM
                    let o = (y * width + x) * 4
                    out[o] = v; out[o + 1] = v; out[o + 2] = v
                }
            }
            return try RGBAImage(width: width, height: height, pixels: out)
        }

        let wide = maxval > 255
        if !ascii {
            let needed = count * samplesPerPixel * (wide ? 2 : 1)
            guard pos + needed <= bytes.count else { throw CodecError.truncated }
        }
        func sample() throws -> Int {
            if ascii {
                if kind == 1 {
                    // P1 digits may be packed without whitespace: "0101".
                    while pos < bytes.count, bytes[pos] != 0x30, bytes[pos] != 0x31 {
                        if bytes[pos] == UInt8(ascii: "#") {
                            while pos < bytes.count, bytes[pos] != 0x0A { pos += 1 }
                            continue
                        }
                        pos += 1
                    }
                    guard pos < bytes.count else { throw CodecError.truncated }
                    defer { pos += 1 }
                    return bytes[pos] == 0x31 ? 0 : 1  // 1 = black → value 0 of maxval 1
                }
                return try token()
            }
            if wide {
                defer { pos += 2 }
                return Int(bytes[pos]) << 8 | Int(bytes[pos + 1])
            }
            defer { pos += 1 }
            return Int(bytes[pos])
        }

        for i in 0..<count {
            let o = i * 4
            if samplesPerPixel == 3 {
                out[o] = scale(try sample()); out[o + 1] = scale(try sample()); out[o + 2] = scale(try sample())
            } else {
                let v = scale(try sample())
                out[o] = v; out[o + 1] = v; out[o + 2] = v
            }
        }
        return try RGBAImage(width: width, height: height, pixels: out)
    }
}
