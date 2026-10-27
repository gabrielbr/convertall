import XCTest
@testable import ConvertAllCore

final class SnifferTests: XCTestCase {
    func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }
    func ftyp(_ brand: String) -> [UInt8] { [0, 0, 0, 0x18] + bytes("ftyp" + brand) + [0, 0, 0, 0] }

    func testImages() {
        XCTAssertEqual(FileSniffer.detect([0xFF, 0xD8, 0xFF, 0xE0]), .jpeg)
        XCTAssertEqual(FileSniffer.detect([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), .png)
        XCTAssertEqual(FileSniffer.detect(bytes("GIF89a")), .gif)
        XCTAssertEqual(FileSniffer.detect(bytes("RIFF\0\0\0\0WEBPVP8 ")), .webp)
        XCTAssertEqual(FileSniffer.detect(ftyp("heic")), .heic)
        XCTAssertEqual(FileSniffer.detect(ftyp("avif")), .avif)
        XCTAssertEqual(FileSniffer.detect(bytes("II*\0")), .tiff)
        XCTAssertEqual(FileSniffer.detect(bytes("qoif")), .qoi)
        XCTAssertEqual(FileSniffer.detect(bytes("P6\n4 4\n255\n")), .pnm)
        XCTAssertEqual(FileSniffer.detect(bytes("\u{FEFF}  <?xml version=\"1.0\"?><svg xmlns=…")), .svg)
        XCTAssertEqual(FileSniffer.detect(QOI.encode(try! RGBAImage(width: 1, height: 1, pixels: [1, 2, 3, 255]))), .qoi)
    }

    func testVideoAndAudio() {
        XCTAssertEqual(FileSniffer.detect(ftyp("qt  ")), .mov)
        XCTAssertEqual(FileSniffer.detect(ftyp("isom")), .mp4)
        XCTAssertEqual(FileSniffer.detect(ftyp("M4A ")), .m4a)
        XCTAssertEqual(FileSniffer.detect([0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x42, 0x82, 0x84] + bytes("webm")), .webm)
        XCTAssertEqual(FileSniffer.detect([0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x42, 0x82, 0x88] + bytes("matroska")), .mkv)
        XCTAssertEqual(FileSniffer.detect(bytes("RIFF\0\0\0\0AVI LIST")), .avi)
        XCTAssertEqual(FileSniffer.detect(bytes("RIFF\0\0\0\0WAVEfmt ")), .wav)
        XCTAssertEqual(FileSniffer.detect(bytes("ID3\u{4}")), .mp3)
        XCTAssertEqual(FileSniffer.detect([0xFF, 0xFB, 0x90, 0x00]), .mp3)
        XCTAssertEqual(FileSniffer.detect([0xFF, 0xF1, 0x50, 0x80]), .aac)
        XCTAssertEqual(FileSniffer.detect(bytes("fLaC")), .flac)
        var opus = bytes("OggS") + [UInt8](repeating: 0, count: 24) + bytes("OpusHead")
        XCTAssertEqual(FileSniffer.detect(opus), .opus)
        opus.replaceSubrange(28..<36, with: bytes("\u{1}vorbis\0"))
        XCTAssertEqual(FileSniffer.detect(opus), .ogg)
    }

    func testDocuments() {
        XCTAssertEqual(FileSniffer.detect(bytes("%PDF-1.7")), .pdf)
        XCTAssertEqual(FileSniffer.detect(bytes("{\\rtf1\\ansi")), .rtf)
        XCTAssertEqual(FileSniffer.detect(bytes("<!DOCTYPE html><html>")), .html)
        let zip: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        XCTAssertEqual(FileSniffer.detect(zip + bytes("....mimetypeapplication/vnd.oasis.opendocument.text")), .odt)
        XCTAssertEqual(FileSniffer.detect(zip + bytes("....[Content_Types].xml....word/document.xml")), .docx)
        XCTAssertEqual(FileSniffer.detect(zip + bytes("....[Content_Types].xml....xl/workbook.xml")), .xlsx)
        XCTAssertEqual(FileSniffer.detect(zip + bytes("....nothing useful"), extensionHint: "pptx"), .pptx)
        XCTAssertNil(FileSniffer.detect(zip + bytes("....nothing useful")))
        let ole: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        XCTAssertEqual(FileSniffer.detect(ole, extensionHint: "xls"), .xls)
        XCTAssertNil(FileSniffer.detect(bytes("just some words")))
        XCTAssertNil(FileSniffer.detect([]))
    }

    func testRenameIntent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sniff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10] + bytes("JFIF"))

        let renamed = dir.appendingPathComponent("photo.png")
        try jpegBytes.write(to: renamed)
        let intent = FileSniffer.renameIntent(for: renamed)
        XCTAssertEqual(intent?.actual, .jpeg)
        XCTAssertEqual(intent?.wanted, .png)

        let honest = dir.appendingPathComponent("photo.jpg")
        try jpegBytes.write(to: honest)
        XCTAssertNil(FileSniffer.renameIntent(for: honest), "name matches content")

        let impossible = dir.appendingPathComponent("photo.mp3")
        try jpegBytes.write(to: impossible)
        XCTAssertNil(FileSniffer.renameIntent(for: impossible), "an image can't become MP3")
    }
}
