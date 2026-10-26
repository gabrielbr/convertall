import XCTest
@testable import ConvertAllCore

final class CodecTests: XCTestCase {
    /// A gradient with a run, a repeated colour, and a semi-transparent stripe —
    /// enough to exercise every QOI op and both TGA packet kinds.
    func makeImage(width: Int = 37, height: Int = 23, alpha: Bool = true) throws -> RGBAImage {
        var px: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                if x < 8 {
                    px += [200, 10, 10, 255]  // run
                } else if (x + y) % 11 == 0 {
                    px += [1, 2, 3, 255]  // recurring → index op
                } else {
                    let a: UInt8 = alpha && y % 5 == 0 ? UInt8(x * 6 % 256) : 255
                    px += [UInt8(x * 7 % 256), UInt8(y * 11 % 256), UInt8((x * y) % 256), a]
                }
            }
        }
        return try RGBAImage(width: width, height: height, pixels: px)
    }

    func testQOIRoundTrip() throws {
        for alpha in [true, false] {
            let image = try makeImage(alpha: alpha)
            let data = QOI.encode(image)
            XCTAssertEqual(Array(data.prefix(4)), Array("qoif".utf8))
            XCTAssertEqual(data[12], alpha ? 4 : 3)
            XCTAssertEqual(try QOI.decode(data), image)
        }
    }

    func testQOILongRunAndSinglePixel() throws {
        let long = try RGBAImage(width: 300, height: 1, pixels: Array(repeating: [9, 9, 9, 255], count: 300).flatMap { $0 })
        XCTAssertEqual(try QOI.decode(QOI.encode(long)), long)
        let one = try RGBAImage(width: 1, height: 1, pixels: [0, 0, 0, 255])
        XCTAssertEqual(try QOI.decode(QOI.encode(one)), one)
    }

    func testQOIRejectsGarbage() {
        XCTAssertThrowsError(try QOI.decode(Array("not an image at all".utf8)))
        var truncated = QOI.encode(try! makeImage())
        truncated.removeLast(40)
        XCTAssertThrowsError(try QOI.decode(truncated))
    }

    func testTGARoundTrip() throws {
        let image = try makeImage()
        let data = TGA.encode(image)
        XCTAssertEqual(data[2], 10)
        XCTAssertEqual(Array(data.suffix(18)), Array("TRUEVISION-XFILE.".utf8) + [0])
        XCTAssertEqual(try TGA.decode(data), image)
    }

    func testTGAReadsUncompressedBottomUp24Bit() throws {
        // 2×2, bottom-left origin, BGR.
        var data: [UInt8] = [0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 2, 0, 24, 0]
        data += [255, 0, 0, 0, 255, 0]  // bottom row: blue, green
        data += [0, 0, 255, 255, 255, 255]  // top row: red, white
        let image = try TGA.decode(data)
        XCTAssertEqual(image.pixels, [255, 0, 0, 255, 255, 255, 255, 255, 0, 0, 255, 255, 0, 255, 0, 255])
    }

    func testPNMRoundTripFlattensAlpha() throws {
        let image = try makeImage(alpha: false)
        let data = PNM.encode(image)
        XCTAssertTrue(data.starts(with: Array("P6\n37 23\n255\n".utf8)))
        XCTAssertEqual(try PNM.decode(data), image)
    }

    func testPNMAsciiVariants() throws {
        let pbm = try PNM.decode(Array("P1\n# tiny\n3 1\n101".utf8))
        XCTAssertEqual(pbm.pixels, [0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255])

        let pgm = try PNM.decode(Array("P2 2 1 15\n0 15\n".utf8))
        XCTAssertEqual(pgm.pixels, [0, 0, 0, 255, 255, 255, 255, 255])

        let ppm = try PNM.decode(Array("P3\n1 1\n255\n10 20 30\n".utf8))
        XCTAssertEqual(ppm.pixels, [10, 20, 30, 255])
    }

    func testPNMBinaryBitmapAnd16Bit() throws {
        let pbm = try PNM.decode(Array("P4\n10 1\n".utf8) + [0b1000_0000, 0b0100_0000])
        XCTAssertEqual(pbm.pixels[0], 0)
        XCTAssertEqual(pbm.pixels[4], 255)
        XCTAssertEqual(pbm.pixels[9 * 4], 0)

        let pgm16 = try PNM.decode(Array("P5 1 1 65535\n".utf8) + [0xFF, 0xFF])
        XCTAssertEqual(pgm16.pixels, [255, 255, 255, 255])
    }

    func testFlattenOntoWhite() throws {
        let image = try RGBAImage(width: 2, height: 1, pixels: [0, 0, 0, 0, 0, 0, 0, 128])
        XCTAssertEqual(image.flattened().pixels, [255, 255, 255, 255, 127, 127, 127, 255])
        XCTAssertFalse(image.flattened().hasTransparency)
    }

    func testRejectsAbsurdDimensions() {
        XCTAssertThrowsError(try PNM.decode(Array("P6 999999 999999 255\n".utf8)))
    }
}
