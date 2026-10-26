import XCTest
@testable import ConvertAllCore

final class FormatTests: XCTestCase {
    func testExtensionLookup() {
        XCTAssertEqual(FileFormat(fileExtension: "JPG"), .jpeg)
        XCTAssertEqual(FileFormat(fileExtension: ".jfif"), .jpeg)
        XCTAssertEqual(FileFormat(fileExtension: "heif"), .heic)
        XCTAssertEqual(FileFormat(fileExtension: "pgm"), .pnm)
        XCTAssertEqual(FileFormat(fileExtension: "m4v"), .mp4)
        XCTAssertEqual(FileFormat(fileExtension: "oga"), .ogg)
        XCTAssertEqual(FileFormat(fileExtension: "htm"), .html)
        XCTAssertEqual(FileFormat(url: URL(fileURLWithPath: "/a/b.tif")), .tiff)
        XCTAssertNil(FileFormat(fileExtension: "exe"))
    }

    func testExtensionsAreUnique() {
        let all = FileFormat.allCases.flatMap(\.fileExtensions)
        XCTAssertEqual(all.count, Set(all).count)
    }

    func testCatalogueMatchesConvtApp() {
        let count = { (c: FormatCategory) in FileFormat.allCases.filter { $0.category == c }.count }
        XCTAssertEqual(count(.image), 14)
        XCTAssertEqual(count(.video), 5)
        XCTAssertEqual(count(.audio), 7)
        XCTAssertEqual(count(.document) + count(.spreadsheet) + count(.presentation), 14)
    }

    func testSearchRanking() {
        let images = ConversionMatrix.imageOutputs
        XCTAssertEqual(FormatSearch.rank(images, query: "").first, .png)
        XCTAssertEqual(FormatSearch.rank(images, query: "p").first, .png)
        XCTAssertEqual(FormatSearch.rank(images, query: "jp").first, .jpeg)
        XCTAssertEqual(FormatSearch.rank(images, query: ".jpg").first, .jpeg)
        XCTAssertEqual(FormatSearch.rank(images, query: "web").first, .webp)
        XCTAssertEqual(FormatSearch.rank(images, query: "fav").first, .ico)
        XCTAssertEqual(FormatSearch.rank(images, query: "hdr").first, .exr)
        XCTAssertEqual(FormatSearch.rank(images, query: "iphone").first, .heic)
        XCTAssertEqual(FormatSearch.rank(images, query: "ppm").first, .pnm)
        XCTAssertTrue(FormatSearch.rank(images, query: "zzz").isEmpty)

        let fromVideo = ConversionMatrix.targets(for: .mov)
        XCTAssertEqual(FormatSearch.rank(fromVideo, query: "mp3").first, .mp3)
        XCTAssertEqual(FormatSearch.rank(fromVideo, query: "gif").first, .gif)
        XCTAssertEqual(FormatSearch.rank(fromVideo, query: "song").first, .mp3)
        XCTAssertEqual(FormatSearch.rank(ConversionMatrix.targets(for: .xlsx), query: "excel").first, .xls)
        XCTAssertEqual(FormatSearch.rank(ConversionMatrix.targets(for: .pdf), query: "word").first, .docx)
    }

    func testOutputNamingNeverOverwrites() {
        let src = URL(fileURLWithPath: "/tmp/photos/cat.jpg")
        let taken: Set<String> = ["/tmp/photos/cat.png", "/tmp/photos/cat 2.png"]
        let dest = OutputNaming.destination(for: src, format: .png, fileExists: { taken.contains($0.path) })
        XCTAssertEqual(dest.path, "/tmp/photos/cat 3.png")

        let same = OutputNaming.destination(for: URL(fileURLWithPath: "/x/a.png"), format: .png, fileExists: { _ in false })
        XCTAssertEqual(same.path, "/x/a 2.png")
    }

    func testMultiPageNaming() {
        let src = URL(fileURLWithPath: "/docs/report.pdf")
        let folder = OutputNaming.folder(for: src, format: .png, fileExists: { $0.lastPathComponent == "report (PNG)" })
        XCTAssertEqual(folder.lastPathComponent, "report (PNG) 2")
        let pages = OutputNaming.pageFiles(for: src, format: .jpeg, count: 12, in: folder)
        XCTAssertEqual(pages.first?.lastPathComponent, "report 01.jpg")
        XCTAssertEqual(pages.last?.lastPathComponent, "report 12.jpg")
    }

    func testVersionComparison() {
        XCTAssertLessThan(AppVersion("0.1.0")!, AppVersion("v0.2.0")!)
        XCTAssertLessThan(AppVersion("0.9.9")!, AppVersion("0.10.0")!)
        XCTAssertEqual(AppVersion("1.2")!, AppVersion("1.2.0")!)
        XCTAssertFalse(AppVersion("1.2.0")! < AppVersion("1.2.0-beta")!)
        XCTAssertNil(AppVersion("latest"))
        XCTAssertEqual(AppVersion("v3.4.5")?.description, "3.4.5")
    }
}

final class MatrixTests: XCTestCase {
    func testTargetsFollowConvtApp() {
        // Video → video, audio and images (incl. GIF).
        let video = ConversionMatrix.targets(for: .mp4)
        XCTAssertFalse(video.contains(.mp4))
        XCTAssertTrue(video.contains(.webm) && video.contains(.mp3) && video.contains(.gif) && video.contains(.png))
        // Audio → audio only.
        XCTAssertTrue(ConversionMatrix.targets(for: .wav).allSatisfy { $0.category == .audio })
        // GIF is the only image that can become video.
        XCTAssertTrue(ConversionMatrix.targets(for: .gif).contains(.mp4))
        XCTAssertFalse(ConversionMatrix.targets(for: .png).contains(.mp4))
        // Images never become documents; SVG is input-only.
        XCTAssertFalse(ConversionMatrix.targets(for: .png).contains(.pdf))
        XCTAssertTrue(FileFormat.allCases.allSatisfy { !ConversionMatrix.targets(for: $0).contains(.svg) })
        // Documents → PDF and images; PDF doesn't target itself.
        XCTAssertTrue(ConversionMatrix.targets(for: .docx).contains(.pdf))
        XCTAssertTrue(ConversionMatrix.targets(for: .pptx).contains(.png))
        XCTAssertFalse(ConversionMatrix.targets(for: .pdf).contains(.pdf))
        XCTAssertTrue(ConversionMatrix.targets(for: .csv).contains(.xlsx))
        XCTAssertFalse(ConversionMatrix.targets(for: .csv).contains(.docx))
        // Every format is a valid source with at least one target.
        XCTAssertTrue(FileFormat.allCases.allSatisfy { !ConversionMatrix.targets(for: $0).isEmpty })
    }

    func testSectionsIntersectSelection() {
        let single = ConversionMatrix.sections(for: [.mov])
        XCTAssertEqual(single.map(\.category), [.video, .audio, .image])

        // A video plus an audio file can only share audio targets.
        let mixed = ConversionMatrix.sections(for: [.mov, .wav])
        XCTAssertEqual(mixed.map(\.category), [.audio])
        XCTAssertFalse(mixed[0].formats.contains(.wav))

        XCTAssertTrue(ConversionMatrix.sections(for: [.mp3, .pdf]).isEmpty)
        XCTAssertEqual(ConversionMatrix.sections(for: [.xlsx]).map(\.category), [.spreadsheet, .document, .image])
    }

    func testEngineRouting() {
        XCTAssertEqual(ConversionMatrix.engine(from: .jpeg, to: .png), .image)
        XCTAssertEqual(ConversionMatrix.engine(from: .gif, to: .mp4), .media)
        XCTAssertEqual(ConversionMatrix.engine(from: .mov, to: .gif), .media)
        XCTAssertEqual(ConversionMatrix.engine(from: .flac, to: .mp3), .media)
        XCTAssertEqual(ConversionMatrix.engine(from: .docx, to: .pdf), .document)
        XCTAssertEqual(ConversionMatrix.engine(from: .pdf, to: .png), .document)
        XCTAssertEqual(ConversionMatrix.engine(from: .xlsx, to: .csv), .office)
        XCTAssertEqual(ConversionMatrix.engine(from: .pptx, to: .jpeg), .office)
    }
}

final class FFmpegTests: XCTestCase {
    let probeOutput = """
    Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'clip.mov':
      Duration: 00:01:02.50, start: 0.000000, bitrate: 5123 kb/s
      Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709), 1920x1080, 4990 kb/s, 30 fps
      Stream #0:1[0x2](und): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 128 kb/s
    At least one output file must be specified
    """

    func testParseProbe() {
        let p = FFmpeg.parseProbe(probeOutput)
        XCTAssertEqual(p.duration, 62.5)
        XCTAssertEqual(p.videoCodec, "h264")
        XCTAssertEqual(p.audioCodec, "aac")

        let song = FFmpeg.parseProbe("""
          Duration: 00:03:10.00, start: 0.025057, bitrate: 320 kb/s
          Stream #0:0: Audio: mp3 (mp3float), 44100 Hz, stereo, fltp, 320 kb/s
          Stream #0:1: Video: mjpeg (Baseline), yuvj420p, 600x600 [SAR 1:1 DAR 1:1], 90k tbr (attached pic)
        """)
        XCTAssertEqual(song.audioCodec, "mp3")
        XCTAssertNil(song.videoCodec, "cover art isn't a video track")
        XCTAssertNil(FFmpeg.parseProbe("Duration: N/A, bitrate: N/A").duration)
    }

    func testParseProgress() {
        XCTAssertEqual(FFmpeg.parseProgressTime("frame=  240 fps= 60 q=28.0 size=  1024kB time=00:00:08.00 bitrate=1048.6kbits/s"), 8)
        XCTAssertEqual(FFmpeg.parseProgressTime("size=N/A time=01:00:00.50 bitrate=N/A"), 3600.5)
        XCTAssertNil(FFmpeg.parseProgressTime("Press [q] to stop"))
    }

    func testErrorSummary() {
        let out = "Input #0 ...\n[libx264 @ 0x1] width not divisible by 2\nError initializing output stream 0:0\nConversion failed!"
        XCTAssertEqual(FFmpeg.errorSummary(out), "Error initializing output stream 0:0")
    }

    func testPlansCopyWhenCompatible() {
        let probe = FFmpeg.parseProbe(probeOutput)
        let mp4 = FFmpeg.plan(from: .mov, to: .mp4, probe: probe)
        XCTAssertEqual(mp4.attempts.count, 2)
        XCTAssertTrue(mp4.attempts[0].contains("copy"))
        XCTAssertTrue(mp4.attempts[1].contains("libx264"))

        let vp9 = MediaProbe(duration: 10, videoCodec: "vp9", audioCodec: "opus")
        let fromWebm = FFmpeg.plan(from: .webm, to: .mp4, probe: vp9)
        XCTAssertEqual(fromWebm.attempts.count, 1, "VP9 can't be copied into MP4 for Apple players")
        XCTAssertEqual(FFmpeg.plan(from: .mp4, to: .webm, probe: vp9).attempts.count, 2)

        let m4a = FFmpeg.plan(from: .mov, to: .m4a, probe: probe)
        XCTAssertEqual(m4a.attempts[0], ["-vn", "-map_metadata", "0", "-c:a", "copy", "-movflags", "+faststart"])
        XCTAssertTrue(FFmpeg.plan(from: .flac, to: .mp3, probe: MediaProbe(audioCodec: "flac")).attempts[0].contains("libmp3lame"))
    }

    func testImagePlans() {
        let probe = MediaProbe(duration: 5, videoCodec: "h264")
        XCTAssertNil(FFmpeg.plan(from: .mp4, to: .gif, probe: probe).intermediate)
        let heic = FFmpeg.plan(from: .mp4, to: .heic, probe: probe)
        XCTAssertEqual(heic.intermediate, .png)
        XCTAssertEqual(heic.ffmpegOutput(for: .heic), .png)
        XCTAssertTrue(FFmpeg.plan(from: .png, to: .webp, probe: MediaProbe()).attempts[0].contains("libwebp"))
        XCTAssertTrue(FFmpeg.plan(from: .png, to: .avif, probe: MediaProbe()).attempts[0].contains("libaom-av1"))
        // A video → WebP still goes through a PNG frame first.
        XCTAssertEqual(FFmpeg.plan(from: .mov, to: .webp, probe: probe).intermediate, .png)
    }
}
