#if os(macOS)
import CryptoKit
import Foundation

/// Video and audio conversion through FFmpeg.
public enum MediaEngine {
    /// FFmpeg to use: the downloaded media pack first, then a Homebrew install.
    public static var ffmpegURL: URL? {
        if FileManager.default.isExecutableFile(atPath: MediaPack.executable.path) { return MediaPack.executable }
        return ImageConverter.findTool("ffmpeg")
    }

    public static func probe(_ url: URL, ffmpeg: URL) throws -> MediaProbe {
        // Without an output FFmpeg prints the stream info and exits non-zero; that's expected.
        let result = try ProcessRunner.run(ffmpeg, ["-hide_banner", "-nostdin", "-i", url.path])
        return FFmpeg.parseProbe(result.output)
    }

    static func convert(
        _ url: URL, from source: FileFormat, to target: FileFormat, options: ConversionOptions,
        trim: ClosedRange<Double>? = nil, animated: Bool = false, task: ConversionTask
    ) throws -> URL {
        guard let ffmpeg = ffmpegURL else { throw ConversionError.engineMissing(target) }
        let probe = try probe(url, ffmpeg: ffmpeg)
        let plan = FFmpeg.plan(from: source, to: target, probe: probe, options: options, trim: trim, animated: animated)
        let produced = plan.ffmpegOutput(for: target)

        let work = try WorkDirectory()
        defer { work.remove() }
        let out = work.file("out.\(produced.preferredExtension)")
        let attempts = plan.attempts.map { FFmpeg.baseArguments + plan.inputArguments + ["-i", url.path] + $0 + [out.path] }
        try run(ffmpeg, attempts: attempts, duration: plan.outputDuration ?? 0, share: plan.intermediate == nil ? 1 : 0.9,
                task: task, output: out)

        let destination = OutputNaming.destination(for: url, format: target)
        if plan.intermediate != nil {
            let final = try ImageConverter.convert(out, to: target, options: options, compress: false, destination: destination)
            task.report(1)
            return final
        }
        task.report(1)
        return try deliver(out, to: destination)
    }

    /// Tries each full argument list until one produces a non-empty `output`, reporting progress.
    static func run(
        _ ffmpeg: URL, attempts: [[String]], duration: Double, share: Double = 1,
        task: ConversionTask, output: URL
    ) throws {
        var lastError = "FFmpeg couldn't convert this file"
        for args in attempts {
            try task.checkCancelled()
            let fullArgs = args.first == "-hide_banner" ? args : FFmpeg.baseArguments + args
            let result = try ProcessRunner.run(ffmpeg, fullArgs, task: task) { line in
                if duration > 0, let t = FFmpeg.parseProgressTime(line) { task.report(t / duration * share) }
            }
            if result.status == 0, ImageConverter.fileSize(output) > 0 { return }
            lastError = FFmpeg.errorSummary(result.output)
            try? FileManager.default.removeItem(at: output)
        }
        throw ConversionError.writeFailed(lastError)
    }

    /// Used by the image engine: WebP/AVIF encoding and PNG quantisation.
    static func encodeImage(_ png: URL, arguments: [String], to output: URL) throws {
        guard let ffmpeg = ffmpegURL else { throw ConversionError.engineMissing(.png) }
        let args = FFmpeg.baseArguments + ["-i", png.path] + arguments + [output.path]
        let result = try ProcessRunner.run(ffmpeg, args)
        guard result.status == 0 else { throw ConversionError.writeFailed(FFmpeg.errorSummary(result.output)) }
    }
}

/// The optional media engine: a static FFmpeg build (martin-riedl.de, GPL), downloaded
/// once into Application Support and verified against a pinned SHA-256.
public enum MediaPack {
    public static let version = "9.0.2"

    struct Build {
        let url: URL
        let sha256: String
        let size: Int64
    }

    static var build: Build {
        #if arch(arm64)
        Build(url: URL(string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip")!,
              sha256: "c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924", size: 28_395_699)
        #else
        Build(url: URL(string: "https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/ffmpeg.zip")!,
              sha256: "7c6b4125b191cbf773832dc51f424cf2b6bb7da43007d1e066f95909e47cacd4", size: 33_816_391)
        #endif
    }

    /// e.g. "28 MB" — shown before downloading.
    public static var downloadSizeText: String {
        ByteCountFormatter.string(fromByteCount: build.size, countStyle: .file)
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ConvertAll/Engines/ffmpeg-\(version)", isDirectory: true)
    }

    static var executable: URL { directory.appendingPathComponent("ffmpeg") }

    public static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    public static func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        let build = build
        let zip = try await Downloader.download(build.url) { progress($0 * 0.95) }
        defer { try? FileManager.default.removeItem(at: zip) }

        let digest = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard digest == build.sha256 else {
            throw ConversionError.writeFailed("the downloaded media engine failed verification")
        }

        let work = try WorkDirectory()
        defer { work.remove() }
        let unzip = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, work.url.path])
        let binary = work.file("ffmpeg")
        guard unzip.status == 0, FileManager.default.fileExists(atPath: binary.path) else {
            throw ConversionError.writeFailed("couldn't unpack the media engine")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        // Apple silicon refuses unsigned code; give it an ad-hoc signature if it lacks a valid one.
        let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
        if try ProcessRunner.run(codesign, ["--verify", binary.path]).status != 0 {
            _ = try ProcessRunner.run(codesign, ["--force", "--sign", "-", binary.path])
        }

        let fm = FileManager.default
        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.moveItem(at: binary, to: executable)
        progress(1)
    }
}
#endif
