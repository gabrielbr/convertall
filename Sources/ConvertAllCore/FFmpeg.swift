import Foundation

/// What `ffmpeg -i <file>` reports about an input.
public struct MediaProbe: Equatable, Sendable {
    public var duration: Double?
    public var videoCodec: String?
    public var audioCodec: String?

    public init(duration: Double? = nil, videoCodec: String? = nil, audioCodec: String? = nil) {
        self.duration = duration
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
    }
}

/// How to turn one media file into another with FFmpeg.
public struct MediaPlan: Equatable, Sendable {
    /// Argument sets to try in order (between the input and the output path).
    /// A fast stream-copy attempt comes first when the codecs allow it.
    public var attempts: [[String]]
    /// FFmpeg writes this format; the image engine then converts it to the real
    /// target (e.g. a video frame is grabbed as PNG, then saved as HEIC).
    public var intermediate: FileFormat?

    /// The format FFmpeg itself produces.
    public func ffmpegOutput(for target: FileFormat) -> FileFormat { intermediate ?? target }
}

/// Pure FFmpeg knowledge: argument plans and output parsing. Running the binary
/// lives in `MediaEngine` (macOS only).
public enum FFmpeg {
    public static let baseArguments = ["-hide_banner", "-nostdin", "-y"]

    public static func plan(from source: FileFormat, to target: FileFormat, probe: MediaProbe) -> MediaPlan {
        let v = probe.videoCodec, a = probe.audioCodec
        let evenSize = ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
        let h264 = ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"] + evenSize
        let aacAudio = ["-c:a", "aac", "-b:a", "160k"]
        let appleVideo: Set<String> = ["h264", "hevc"]
        let appleAudio: Set<String> = ["aac", "mp3", "alac"]
        let canCopyIntoApple = v.map(appleVideo.contains) == true && (a == nil || appleAudio.contains(a!))

        switch target {
        // MARK: Video
        case .mp4:
            let encode = h264 + aacAudio + ["-movflags", "+faststart"]
            return MediaPlan(attempts: canCopyIntoApple ? [["-c", "copy", "-movflags", "+faststart"], encode] : [encode])
        case .mov:
            let encode = h264 + aacAudio
            return MediaPlan(attempts: canCopyIntoApple ? [["-c", "copy"], encode] : [encode])
        case .mkv:
            // Matroska holds almost anything: keep every track untouched when possible.
            let encode = h264 + aacAudio
            return MediaPlan(attempts: source.category == .video ? [["-map", "0", "-c", "copy"], encode] : [encode])
        case .webm:
            let encode = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-deadline", "good",
                          "-cpu-used", "4", "-pix_fmt", "yuv420p", "-c:a", "libopus", "-b:a", "128k"]
            let webmVideo: Set<String> = ["vp8", "vp9", "av1"], webmAudio: Set<String> = ["opus", "vorbis"]
            let canCopy = v.map(webmVideo.contains) == true && (a == nil || webmAudio.contains(a!))
            return MediaPlan(attempts: canCopy ? [["-c", "copy"], encode] : [encode])
        case .avi:
            return MediaPlan(attempts: [["-c:v", "mpeg4", "-vtag", "xvid", "-q:v", "3"] + evenSize
                + ["-c:a", "libmp3lame", "-q:a", "3"]])

        // MARK: Audio (from audio, or the soundtrack of a video)
        case .mp3: return audio(copyIf: a == "mp3", ["-c:a", "libmp3lame", "-q:a", "2"])
        case .m4a: return audio(copyIf: a == "aac" || a == "alac", ["-c:a", "aac", "-b:a", "192k"], extra: ["-movflags", "+faststart"])
        case .aac: return audio(copyIf: a == "aac", ["-c:a", "aac", "-b:a", "192k"], extra: ["-f", "adts"])
        case .wav: return audio(copyIf: false, ["-c:a", "pcm_s16le"])
        case .flac: return audio(copyIf: a == "flac", ["-c:a", "flac"])
        case .ogg: return audio(copyIf: a == "vorbis", ["-c:a", "libvorbis", "-q:a", "5"])
        case .opus: return audio(copyIf: a == "opus", ["-c:a", "libopus", "-b:a", "128k"])

        // MARK: Images
        case .gif:
            // Two-pass palette in one graph: far better colours than FFmpeg's default GIF.
            return MediaPlan(attempts: [[
                "-vf", "fps=12,scale='min(720,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
                "-loop", "0",
            ]])
        case .webp where source.category == .image:
            return MediaPlan(attempts: [["-c:v", "libwebp", "-quality", "85", "-frames:v", "1"]])
        case .avif where source.category == .image:
            return MediaPlan(attempts: [["-c:v", "libaom-av1", "-still-picture", "1", "-crf", "28", "-b:v", "0",
                                         "-cpu-used", "6", "-pix_fmt", "yuv420p", "-frames:v", "1"]])
        default:
            // Any other image from a video: grab a representative frame as PNG, then
            // let the image engine produce the real format.
            return MediaPlan(attempts: [["-vf", "thumbnail", "-frames:v", "1", "-update", "1"]], intermediate: .png)
        }
    }

    private static func audio(copyIf canCopy: Bool, _ encode: [String], extra: [String] = []) -> MediaPlan {
        let common = ["-vn", "-map_metadata", "0"]
        let attempts = canCopy ? [common + ["-c:a", "copy"] + extra, common + encode + extra] : [common + encode + extra]
        return MediaPlan(attempts: attempts)
    }

    // MARK: Parsing FFmpeg's stderr

    public static func parseProbe(_ output: String) -> MediaProbe {
        var probe = MediaProbe()
        if let m = firstMatch(#"Duration:\s*(\d+):(\d{2}):(\d{2}(?:\.\d+)?)"#, in: output) {
            probe.duration = seconds(m[0], m[1], m[2])
        }
        for line in output.split(whereSeparator: \.isNewline) where line.contains("Stream #") {
            if probe.videoCodec == nil, !line.contains("attached pic"),
               let m = firstMatch(#": Video: ([A-Za-z0-9_]+)"#, in: String(line)) {
                probe.videoCodec = m[0]
            }
            if probe.audioCodec == nil, let m = firstMatch(#": Audio: ([A-Za-z0-9_]+)"#, in: String(line)) {
                probe.audioCodec = m[0]
            }
        }
        return probe
    }

    /// Seconds processed so far, from a progress line like `… time=00:01:02.50 bitrate=…`.
    public static func parseProgressTime(_ line: String) -> Double? {
        guard let m = firstMatch(#"time=\s*(\d+):(\d{2}):(\d{2}(?:\.\d+)?)"#, in: line) else { return nil }
        return seconds(m[0], m[1], m[2])
    }

    /// The most useful line of an FFmpeg failure, for showing to people.
    public static func errorSummary(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let interesting = lines.last { line in
            let l = line.lowercased()
            return l.contains("error") || l.contains("invalid") || l.contains("not supported")
                || l.contains("could not") || l.contains("no such")
        }
        return interesting ?? lines.last ?? "FFmpeg failed"
    }

    private static func seconds(_ h: String, _ m: String, _ s: String) -> Double? {
        guard let h = Double(h), let m = Double(m), let s = Double(s) else { return nil }
        return h * 3600 + m * 60 + s
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}
