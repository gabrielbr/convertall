import Foundation

/// The "Quite OK Image" format — https://qoiformat.org/qoi-specification.pdf
public enum QOI {
    private static let opIndex: UInt8 = 0x00
    private static let opDiff: UInt8 = 0x40
    private static let opLuma: UInt8 = 0x80
    private static let opRun: UInt8 = 0xC0
    private static let opRGB: UInt8 = 0xFE
    private static let opRGBA: UInt8 = 0xFF
    private static let padding: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]

    private struct Pixel: Equatable {
        var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255
        var hash: Int { (Int(r) * 3 + Int(g) * 5 + Int(b) * 7 + Int(a) * 11) % 64 }
    }

    public static func encode(_ image: RGBAImage) -> [UInt8] {
        let channels: UInt8 = image.hasTransparency ? 4 : 3
        var out: [UInt8] = Array("qoif".utf8)
        out.reserveCapacity(14 + image.width * image.height * 3 + padding.count)
        for v in [image.width, image.height] {
            out += [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
        }
        out += [channels, 0]  // colorspace: sRGB with linear alpha

        var index = [Pixel](repeating: Pixel(r: 0, g: 0, b: 0, a: 0), count: 64)
        var prev = Pixel()
        var run = 0
        let px = image.pixels
        let last = px.count - 4

        for i in stride(from: 0, to: px.count, by: 4) {
            let p = Pixel(r: px[i], g: px[i + 1], b: px[i + 2], a: px[i + 3])
            if p == prev {
                run += 1
                if run == 62 || i == last {
                    out.append(opRun | UInt8(run - 1))
                    run = 0
                }
                continue
            }
            if run > 0 {
                out.append(opRun | UInt8(run - 1))
                run = 0
            }
            let h = p.hash
            if index[h] == p {
                out.append(opIndex | UInt8(h))
            } else {
                index[h] = p
                if p.a == prev.a {
                    let vr = Int(Int8(truncatingIfNeeded: Int(p.r) - Int(prev.r)))
                    let vg = Int(Int8(truncatingIfNeeded: Int(p.g) - Int(prev.g)))
                    let vb = Int(Int8(truncatingIfNeeded: Int(p.b) - Int(prev.b)))
                    let vgr = vr - vg, vgb = vb - vg
                    if (-2...1).contains(vr), (-2...1).contains(vg), (-2...1).contains(vb) {
                        out.append(opDiff | UInt8(vr + 2) << 4 | UInt8(vg + 2) << 2 | UInt8(vb + 2))
                    } else if (-8...7).contains(vgr), (-32...31).contains(vg), (-8...7).contains(vgb) {
                        out.append(opLuma | UInt8(vg + 32))
                        out.append(UInt8(vgr + 8) << 4 | UInt8(vgb + 8))
                    } else {
                        out += [opRGB, p.r, p.g, p.b]
                    }
                } else {
                    out += [opRGBA, p.r, p.g, p.b, p.a]
                }
            }
            prev = p
        }
        out += padding
        return out
    }

    public static func decode(_ bytes: [UInt8]) throws -> RGBAImage {
        guard bytes.count >= 14 + padding.count, Array(bytes[0..<4]) == Array("qoif".utf8) else {
            throw CodecError.invalidSignature
        }
        var header = ByteReader(bytes)
        try header.skip(4)
        let width = try header.u32be(), height = try header.u32be()
        let channels = try header.u8()
        guard channels == 3 || channels == 4 else { throw CodecError.unsupportedVariant("\(channels) channels") }
        guard width > 0, height > 0, width.multipliedReportingOverflow(by: height).partialValue <= RGBAImage.maxPixelCount
        else { throw CodecError.invalidDimensions(width, height) }

        let count = width * height
        var out = [UInt8](repeating: 0, count: count * 4)
        var index = [Pixel](repeating: Pixel(r: 0, g: 0, b: 0, a: 0), count: 64)
        var p = Pixel()
        var run = 0
        var pos = 14
        let end = bytes.count - padding.count

        func next() throws -> UInt8 {
            guard pos < end else { throw CodecError.truncated }
            defer { pos += 1 }
            return bytes[pos]
        }

        for i in 0..<count {
            if run > 0 {
                run -= 1
            } else {
                let b1 = try next()
                if b1 == opRGB {
                    p.r = try next(); p.g = try next(); p.b = try next()
                } else if b1 == opRGBA {
                    p.r = try next(); p.g = try next(); p.b = try next(); p.a = try next()
                } else {
                    switch b1 & 0xC0 {
                    case opIndex:
                        p = index[Int(b1)]
                    case opDiff:
                        p.r = p.r &+ ((b1 >> 4) & 0x03) &- 2
                        p.g = p.g &+ ((b1 >> 2) & 0x03) &- 2
                        p.b = p.b &+ (b1 & 0x03) &- 2
                    case opLuma:
                        let b2 = try next()
                        let vg = (b1 & 0x3F) &- 32
                        p.r = p.r &+ vg &- 8 &+ ((b2 >> 4) & 0x0F)
                        p.g = p.g &+ vg
                        p.b = p.b &+ vg &- 8 &+ (b2 & 0x0F)
                    default:  // opRun
                        run = Int(b1 & 0x3F)
                    }
                }
                index[p.hash] = p
            }
            let o = i * 4
            out[o] = p.r; out[o + 1] = p.g; out[o + 2] = p.b; out[o + 3] = p.a
        }
        return try RGBAImage(width: width, height: height, pixels: out)
    }
}
