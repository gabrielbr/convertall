import XCTest
@testable import ConvertAllCore

final class FinderPresetsTests: XCTestCase {
    func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    func testEveryCandidateHasATag() {
        for kind in FinderPresets.Kind.allCases {
            for id in FinderPresets.candidates(for: kind) { XCTAssertNotNil(FinderPresets.all.firstIndex(of: id), id) }
        }
        for ids in FinderPresets.defaults.values { for id in ids { XCTAssertTrue(FinderPresets.all.contains(id), id) } }
        XCTAssertEqual(Set(FinderPresets.all).count, FinderPresets.all.count, "tags must be unique")
    }

    func testDefaultItems() {
        let jpeg = FinderPresets.items(for: [url("a.jpg")], isFolder: false, config: nil).map(\.title)
        XCTAssertEqual(jpeg.first, "Make Smaller")
        XCTAssertTrue(jpeg.contains("→ PNG"))
        XCTAssertFalse(jpeg.contains("→ JPEG"), "no same-format convert")
        XCTAssertTrue(jpeg.contains("→ PDF"))

        let two = FinderPresets.items(for: [url("a.jpg"), url("b.png")], isFolder: false, config: nil).map(\.title)
        XCTAssertFalse(two.contains("Make Smaller"), "mixed formats can't compress to one format")
        XCTAssertTrue(two.contains("Combine into One PDF"))

        let video = FinderPresets.items(for: [url("clip.mov")], isFolder: false, config: nil).map(\.title)
        XCTAssertTrue(video.contains("→ MP3 (audio)"))
        XCTAssertFalse(video.contains("Join into One MP4"))
        XCTAssertTrue(FinderPresets.items(for: [url("a.mov"), url("b.mp4")], isFolder: false, config: nil)
            .map(\.title).contains("Join into One MP4"))

        XCTAssertEqual(FinderPresets.items(for: [url("deck.pptx")], isFolder: false, config: nil).map(\.title),
                       ["→ PDF", "→ PNG (pages)"])
        XCTAssertTrue(FinderPresets.items(for: [url("a.jpg"), url("b.mp3")], isFolder: false, config: nil).isEmpty)
        XCTAssertEqual(FinderPresets.items(for: [url("x")], isFolder: true, config: nil).count, 3)
    }

    func testCustomConfigRoundTrip() {
        let config: FinderPresets.Config = ["image": ["convert-avif", "extract-text"]]
        let decoded = FinderPresets.decode(FinderPresets.encode(config))
        XCTAssertEqual(decoded, config)
        let titles = FinderPresets.items(for: [url("a.heic")], isFolder: false, config: decoded).map(\.title)
        XCTAssertEqual(titles, ["→ AVIF", "Extract Text"])
        // Kinds missing from a custom config fall back to the defaults.
        XCTAssertFalse(FinderPresets.items(for: [url("a.mp3")], isFolder: false, config: decoded).isEmpty)
        XCTAssertNil(FinderPresets.decode("not json"))
    }
}
