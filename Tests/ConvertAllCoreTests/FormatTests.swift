import XCTest
@testable import ConvertAllCore

final class FormatTests: XCTestCase {
    func testExtensionLookup() {
        XCTAssertEqual(ImageFormat(fileExtension: "JPG"), .jpeg)
        XCTAssertEqual(ImageFormat(fileExtension: "jfif"), .jpeg)
        XCTAssertEqual(ImageFormat(fileExtension: "heif"), .heic)
        XCTAssertEqual(ImageFormat(fileExtension: "pgm"), .pnm)
        XCTAssertEqual(ImageFormat(url: URL(fileURLWithPath: "/a/b.tif")), .tiff)
        XCTAssertNil(ImageFormat(fileExtension: "mp4"))
    }

    func testOutputsMatchConvtApp() {
        let outputs = Set(ImageFormat.allCases.filter(\.isOutputCandidate))
        XCTAssertEqual(outputs, Set(ImageFormat.popularityOrder))
        XCTAssertFalse(outputs.contains(.svg))
    }

    func testSearchRanking() {
        let all = ImageFormat.popularityOrder
        XCTAssertEqual(FormatSearch.rank(all, query: "").first, .png)
        XCTAssertEqual(FormatSearch.rank(all, query: "p").first, .png)
        XCTAssertEqual(FormatSearch.rank(all, query: "jp").first, .jpeg)
        XCTAssertEqual(FormatSearch.rank(all, query: ".jpg").first, .jpeg)
        XCTAssertEqual(FormatSearch.rank(all, query: "web").first, .webp)
        XCTAssertEqual(FormatSearch.rank(all, query: "fav").first, .ico)
        XCTAssertEqual(FormatSearch.rank(all, query: "hdr").first, .exr)
        XCTAssertEqual(FormatSearch.rank(all, query: "tif").first, .tiff)
        XCTAssertEqual(FormatSearch.rank(all, query: "iphone").first, .heic)
        XCTAssertEqual(FormatSearch.rank(all, query: "ppm").first, .pnm)
        XCTAssertTrue(FormatSearch.rank(all, query: "zzz").isEmpty)
    }

    func testOutputNamingNeverOverwrites() {
        let src = URL(fileURLWithPath: "/tmp/photos/cat.jpg")
        let taken: Set<String> = ["/tmp/photos/cat.png", "/tmp/photos/cat 2.png"]
        let dest = OutputNaming.destination(for: src, format: .png, fileExists: { taken.contains($0.path) })
        XCTAssertEqual(dest.path, "/tmp/photos/cat 3.png")

        let same = OutputNaming.destination(for: URL(fileURLWithPath: "/x/a.png"), format: .png, fileExists: { _ in false })
        XCTAssertEqual(same.path, "/x/a 2.png")
    }
}
