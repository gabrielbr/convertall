import XCTest
@testable import ConvertAllCore

final class BatchTests: XCTestCase {
    func testFolderScanner() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        for path in ["a.jpg", "b.txt", "notes.xyz", ".hidden.png", "sub/c.mp4", "sub/deeper/d.PNG", "Thing.app/e.png"] {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        }
        let found = FolderScanner.expand([root]).map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        XCTAssertEqual(found, ["a.jpg", "b.txt", "sub/c.mp4", "sub/deeper/d.PNG"])
        XCTAssertTrue(FolderScanner.containsFolder([root]))
        XCTAssertFalse(FolderScanner.containsFolder([root.appendingPathComponent("a.jpg")]))
        // Explicit files pass through; duplicates collapse.
        let a = root.appendingPathComponent("a.jpg")
        XCTAssertEqual(FolderScanner.expand([a, a]).count, 1)
    }

    func testCombineTargets() {
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.jpeg]), [.pdf], "one image can become a PDF page")
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.png, .pdf, .heic]), [.pdf])
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.pdf, .pdf]), [.pdf])
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.pdf]), [], "nothing to combine")
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.mov, .mp4]), [.mp4])
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.mp3, .wav]), [.mp3, .m4a])
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.mov]), [])
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.mov, .mp3]), [])
        XCTAssertEqual(ConversionMatrix.combineTargets(for: [.docx, .docx]), [])
    }

    func testParallelism() {
        XCTAssertEqual(ConversionMatrix.parallelism(for: .office, cores: 16), 1)
        XCTAssertEqual(ConversionMatrix.parallelism(for: .media, cores: 4), 1)
        XCTAssertEqual(ConversionMatrix.parallelism(for: .media, cores: 12), 3)
        XCTAssertEqual(ConversionMatrix.parallelism(for: .image, cores: 2), 2)
        XCTAssertEqual(ConversionMatrix.parallelism(for: .image, cores: 24), 8)
    }

    func testAnimatedRouting() {
        XCTAssertEqual(ConversionMatrix.engine(from: .webp, to: .gif, animated: true), .image, "ImageIO writes animated GIF")
        XCTAssertEqual(ConversionMatrix.engine(from: .gif, to: .webp, animated: true), .media)
        XCTAssertEqual(ConversionMatrix.engine(from: .webp, to: .mp4, animated: true), .media)
        XCTAssertEqual(ConversionMatrix.engine(from: .gif, to: .webp, animated: false), .image)
        let webp = FFmpeg.plan(from: .gif, to: .webp, probe: MediaProbe(), animated: true)
        XCTAssertTrue(webp.attempts[0].contains("-loop"))
        XCTAssertFalse(webp.attempts[0].contains("-frames:v"))
    }

    func testTrimPlan() {
        let probe = MediaProbe(duration: 60, videoCodec: "h264", audioCodec: "aac")
        let plan = FFmpeg.plan(from: .mov, to: .mp4, probe: probe, trim: 10...25.5)
        XCTAssertEqual(plan.inputArguments, ["-ss", "10.000"])
        XCTAssertEqual(plan.outputDuration, 15.5)
        XCTAssertFalse(plan.attempts.contains { $0.contains("copy") }, "copy can't cut precisely")
        XCTAssertTrue(plan.attempts.allSatisfy { $0.prefix(2) == ["-t", "15.500"] })
        XCTAssertEqual(FFmpeg.plan(from: .mov, to: .mp4, probe: probe).inputArguments, [])
    }

    func testJoinArguments() {
        let clips = [
            ("/a.mov", MediaProbe(duration: 3, videoCodec: "h264", audioCodec: "aac", width: 1919, height: 1080)),
            ("/b.mp4", MediaProbe(duration: 4, videoCodec: "hevc", audioCodec: nil, width: 640, height: 480)),
        ]
        let attempts = FFmpeg.joinVideoArguments(inputs: clips, output: "/out.mp4", options: ConversionOptions())
        XCTAssertEqual(attempts.count, 2)
        let args = attempts[0]
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 3, "two clips plus a silent track for the mute one")
        let graph = args[args.firstIndex(of: "-filter_complex")! + 1]
        XCTAssertTrue(graph.contains("scale=1918:1080"), "fits into the first clip's (even) frame")
        XCTAssertTrue(graph.contains("[2:a:0]"), "clip 1 uses the silent input")
        XCTAssertTrue(graph.hasSuffix("concat=n=2:v=1:a=1[v][a]"))
        XCTAssertTrue(attempts[0].contains("h264_videotoolbox"))
        XCTAssertEqual(args.last, "/out.mp4")

        let audio = FFmpeg.joinAudioArguments(inputPaths: ["/1.mp3", "/2.wav"], to: .m4a, output: "/o.m4a", options: ConversionOptions())
        XCTAssertTrue(audio.contains("aac"))
        XCTAssertTrue(audio[audio.firstIndex(of: "-filter_complex")! + 1].hasSuffix("concat=n=2:v=0:a=1[a]"))
    }

    func testProbeReadsDimensions() {
        let p = FFmpeg.parseProbe("  Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709), 1920x1080 [SAR 1:1 DAR 16:9], 4990 kb/s")
        XCTAssertEqual(p.width, 1920)
        XCTAssertEqual(p.height, 1080)
    }

    func testCombinedNaming() {
        let first = URL(fileURLWithPath: "/pics/beach.jpg")
        XCTAssertEqual(OutputNaming.combined(for: first, format: .pdf, fileExists: { _ in false }).path, "/pics/beach (combined).pdf")
        XCTAssertEqual(OutputNaming.combined(for: first, format: .pdf, fileExists: { $0.path == "/pics/beach (combined).pdf" }).path,
                       "/pics/beach (combined) 2.pdf")
    }
}
