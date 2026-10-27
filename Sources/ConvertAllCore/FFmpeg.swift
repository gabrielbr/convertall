import Foundation

/// What `ffmpeg -i <file>` reports about an input.
public struct MediaProbe: Equatable, Sendable {
    public var duration: Double?
    public var videoCodec: String?
    public var audioCodec: String?
    public var width: Int?
    public var height: Int?

    public init(duration: Double? = nil, videoCodec: String? = nil, audioCodec: String? = nil,
                width: Int? = nil, height: Int? = nil) {
        self.duration = duration
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.width = width
        self.height = height
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
    /// Goes before `-i` (fast seeking for trims).
    public var inputArguments: [String] = []
    /// Seconds of output, for progress (trimmed length when trimming).
    public var outputDuration: Double?

    public init(attempts: [[String]], intermediate: FileFormat? = nil) {
        self.attempts = attempts
        self.intermediate = intermediate
    }

    /// The format FFmpeg itself produces.
    public func ffmpegOutput(for target: FileFormat) -> FileFormat { intermediate ?? target }
}

/// Pure FFmpeg knowledge: argument plans and output parsing. Running the binary
/// lives in `MediaEngine` (macOS only).
public enum FFmpeg {
    public static let baseArguments = ["-hide_banner", "-nostdin", "-y"]

    /// - Parameter options: quality / size / metadata from the chip's options strip.
    ///   `source == target` means "Compress": re-encode smaller in the same format.
    public static func plan(
        from source: FileFormat, to target: FileFormat, probe: MediaProbe,
        options: ConversionOptions = ConversionOptions(), trim: ClosedRange<Double>? = nil, animated: Bool = false
    ) -> MediaPlan {
        var plan = basePlan(from: source, to: target, probe: probe, options: options, trim: trim, animated: animated)
        plan.outputDuration = probe.duration
        if let trim, trim.upperBound > trim.lowerBound {
            // -ss before -i seeks fast; -t limits the length. Copying can't cut precisely,
            // so copy attempts were already left out by `basePlan`.
            plan.inputArguments = ["-ss", seconds(trim.lowerBound)]
            plan.attempts = plan.attempts.map { ["-t", seconds(trim.upperBound - trim.lowerBound)] + $0 }
            plan.outputDuration = trim.upperBound - trim.lowerBound
        }
        return plan
    }

    static func seconds(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func basePlan(
        from source: FileFormat, to target: FileFormat, probe: MediaProbe,
        options: ConversionOptions, trim: ClosedRange<Double>?, animated: Bool
    ) -> MediaPlan {
        let compress = source == target
        let v = probe.videoCodec, a = probe.audioCodec
        let budget = options.size.targetBytes.flatMap {
            ConversionOptions.bitrateBudget(bytes: $0, duration: probe.duration, hasAudio: a != nil)
        }
        // Stream copy is only possible when nothing about the streams has to change.
        let mayCopy = !compress && !options.size.changesDimensions && budget == nil && trim == nil
        let metadata = options.stripMetadata ? ["-map_metadata", "-1", "-map_chapters", "-1"] : ["-map_metadata", "0"]
        let scale = ["-vf", videoScaleFilter(options.size)]
        let faststart = ["-movflags", "+faststart"]
        let audioKbps = budget?.audio ?? options.audioKbps(compress: compress)
        let aac = ["-c:a", "aac", "-b:a", "\(audioKbps)k"]

        var bitrate: [String]?
        if let budget {
            bitrate = ["-b:v", "\(budget.video)k", "-maxrate", "\(budget.video * 6 / 5)k", "-bufsize", "\(budget.video * 2)k"]
        }

        /// Apple's hardware encoder: several times faster and far kinder to the battery.
        func videoToolbox(hevc: Bool) -> [String] {
            var args = ["-c:v", hevc ? "hevc_videotoolbox" : "h264_videotoolbox"]
            args += bitrate ?? ["-q:v", "\(options.videoToolboxQuality(compress: compress))"]
            args += ["-pix_fmt", "yuv420p"]
            if hevc { args += ["-tag:v", "hvc1"] }
            return args + scale
        }
        /// Software fallback (Intel Macs without constant-quality VideoToolbox, odd inputs).
        var x264 = ["-c:v", "libx264", "-preset", "medium"]
        x264 += bitrate ?? ["-crf", "\(options.x264CRF(compress: compress))"]
        x264 += ["-pix_fmt", "yuv420p"] + scale

        let appleVideo: Set<String> = ["h264", "hevc"]
        let appleAudio: Set<String> = ["aac", "mp3", "alac"]
        let canCopyIntoApple = mayCopy && v.map(appleVideo.contains) == true && (a == nil || appleAudio.contains(a!))

        switch target {
        // MARK: Video
        case .mp4, .mov, .mkv:
            let tail = (target == .mov ? [] : (target == .mp4 ? faststart : [])) + metadata
            var attempts: [[String]] = []
            if target == .mkv, mayCopy, source.category == .video {
                attempts.append(["-map", "0", "-c", "copy"])  // Matroska holds anything: keep every track
            } else if target != .mkv, canCopyIntoApple {
                attempts.append(["-c", "copy"] + tail)
            }
            // Compressing → HEVC: roughly half the size of H.264 at the same quality.
            attempts.append(videoToolbox(hevc: compress) + aac + tail)
            attempts.append(x264 + aac + tail)
            return MediaPlan(attempts: attempts)

        case .webm:
            var encode = ["-c:v", "libvpx-vp9"]
            if let budget { encode += ["-b:v", "\(budget.video)k"] } else { encode += ["-crf", "\(options.vp9CRF)", "-b:v", "0"] }
            encode += ["-row-mt", "1", "-deadline", "good", "-cpu-used", "4", "-pix_fmt", "yuv420p"] + scale
            encode += ["-c:a", "libopus", "-b:a", "\(min(audioKbps, 192))k"] + metadata
            let webmVideo: Set<String> = ["vp8", "vp9", "av1"], webmAudio: Set<String> = ["opus", "vorbis"]
            let canCopy = mayCopy && v.map(webmVideo.contains) == true && (a == nil || webmAudio.contains(a!))
            return MediaPlan(attempts: canCopy ? [["-c", "copy"], encode] : [encode])

        case .avi:
            let q = options.quality == .smaller ? 6 : (options.quality == .balanced ? 3 : 2)
            var encode = ["-c:v", "mpeg4", "-vtag", "xvid"]
            encode += budget.map { ["-b:v", "\($0.video)k"] } ?? ["-q:v", "\(q)"]
            encode += scale + ["-c:a", "libmp3lame", "-q:a", "3"] + metadata
            return MediaPlan(attempts: [encode])

        // MARK: Audio (from audio, or the soundtrack of a video)
        case .mp3:
            let rate: [String] = budget.map { ["-b:a", "\($0.audio)k"] } ?? ["-q:a", "\(options.mp3VBR(compress: compress))"]
            let encode = ["-c:a", "libmp3lame"] + rate
            return audio(copyIf: mayCopy && a == "mp3", encode, metadata: metadata)
        case .m4a:
            return audio(copyIf: mayCopy && (a == "aac" || a == "alac"), aac, metadata: metadata, extra: faststart)
        case .aac:
            return audio(copyIf: mayCopy && a == "aac", aac, metadata: metadata, extra: ["-f", "adts"])
        case .wav:
            return audio(copyIf: false, ["-c:a", "pcm_s16le"], metadata: metadata)
        case .flac:
            return audio(copyIf: mayCopy && a == "flac", ["-c:a", "flac", "-compression_level", "8"], metadata: metadata)
        case .ogg:
            let rate: [String] = budget.map { ["-b:a", "\($0.audio)k"] } ?? ["-q:a", "\(options.vorbisQuality)"]
            let encode = ["-c:a", "libvorbis"] + rate
            return audio(copyIf: mayCopy && a == "vorbis", encode, metadata: metadata)
        case .opus:
            return audio(copyIf: mayCopy && a == "opus", ["-c:a", "libopus", "-b:a", "\(min(audioKbps, 256))k"], metadata: metadata)

        // MARK: Images
        case .gif:
            // Two-pass palette in one graph: far better colours than FFmpeg's default GIF.
            let width: String = switch options.size {
            case .half: "trunc(iw/2)"
            case .maxDimension(let px): "'min(\(px),iw)'"
            default: compress ? "iw" : "'min(\(options.gifWidth),iw)'"
            }
            let fps = compress && options.quality != .smaller ? "" : "fps=\(options.gifFPS),"
            return MediaPlan(attempts: [[
                "-vf", "\(fps)scale=\(width):-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=\(options.gifColors):stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
                "-loop", "0",
            ] + metadata])
        case .png where compress:
            return MediaPlan(attempts: [pngQuantizeArguments(colors: options.quality == .smaller ? 96 : 256)])
        case .webp where source.category == .image, .avif where source.category == .image:
            let quality = options.imageQuality(compress: compress)
            return MediaPlan(attempts: [animated ? animatedImageArguments(for: target, quality: quality)
                                                 : stillImageArguments(for: target, quality: quality)])
        default:
            // Any other image from a video: grab a representative frame as PNG, then
            // let the image engine produce the real format (and apply size options).
            return MediaPlan(attempts: [["-vf", "thumbnail", "-frames:v", "1", "-update", "1"]], intermediate: .png)
        }
    }

    /// WebP/AVIF still-image encode at a 0…1 quality (macOS can't write these itself).
    public static func stillImageArguments(for format: FileFormat, quality: Double) -> [String] {
        if format == .avif {
            let crf = Int((1 - quality) * 60) + 12
            return ["-c:v", "libaom-av1", "-still-picture", "1", "-crf", "\(crf)", "-b:v", "0",
                    "-cpu-used", "6", "-pix_fmt", "yuv420p", "-frames:v", "1"]
        }
        return ["-c:v", "libwebp", "-quality", "\(Int((quality * 100).rounded()))", "-frames:v", "1"]
    }

    /// Animated WebP/AVIF from an animated source (every frame, looping forever).
    public static func animatedImageArguments(for format: FileFormat, quality: Double) -> [String] {
        if format == .avif {
            let crf = Int((1 - quality) * 60) + 12
            return ["-c:v", "libaom-av1", "-crf", "\(crf)", "-b:v", "0", "-cpu-used", "6",
                    "-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-an"]
        }
        return ["-c:v", "libwebp", "-quality", "\(Int((quality * 100).rounded()))", "-loop", "0", "-an"]
    }

    /// Joins several videos (any sizes, with or without sound) into one MP4: every clip is
    /// fitted into the first clip's frame, and silent clips get a silent track.
    /// Returns arguments for everything after `-hide_banner -nostdin -y`, including inputs.
    public static func joinVideoArguments(
        inputs: [(path: String, probe: MediaProbe)], output: String, options: ConversionOptions
    ) -> [[String]] {
        let w = max(2, (inputs.first?.probe.width ?? 1280) / 2 * 2)
        let h = max(2, (inputs.first?.probe.height ?? 720) / 2 * 2)
        var args: [String] = []
        var silent: [Int: Int] = [:]  // clip index → input index of its silent track
        for input in inputs { args += ["-i", input.path] }
        for (i, input) in inputs.enumerated() where input.probe.audioCodec == nil {
            silent[i] = inputs.count + silent.count
            args += ["-f", "lavfi", "-t", seconds(input.probe.duration ?? 1), "-i", "anullsrc=r=48000:cl=stereo"]
        }
        var graph = ""
        var pairs = ""
        for i in inputs.indices {
            graph += "[\(i):v:0]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v\(i)];"
            graph += "[\(silent[i] ?? i):a:0]aresample=48000,aformat=channel_layouts=stereo[a\(i)];"
            pairs += "[v\(i)][a\(i)]"
        }
        graph += "\(pairs)concat=n=\(inputs.count):v=1:a=1[v][a]"
        let common = args + ["-filter_complex", graph, "-map", "[v]", "-map", "[a]"]
        let audio = ["-c:a", "aac", "-b:a", "\(options.audioKbps())k", "-movflags", "+faststart", output]
        return [
            common + ["-c:v", "h264_videotoolbox", "-q:v", "\(options.videoToolboxQuality())"] + audio,
            common + ["-c:v", "libx264", "-preset", "medium", "-crf", "\(options.x264CRF())"] + audio,
        ]
    }

    /// Joins audio files back to back.
    public static func joinAudioArguments(inputPaths: [String], to format: FileFormat, output: String,
                                          options: ConversionOptions) -> [String] {
        var args: [String] = []
        for path in inputPaths { args += ["-i", path] }
        let graph = inputPaths.indices.map { "[\($0):a:0]aresample=48000,aformat=channel_layouts=stereo[a\($0)];" }.joined()
            + inputPaths.indices.map { "[a\($0)]" }.joined() + "concat=n=\(inputPaths.count):v=0:a=1[a]"
        let codec = format == .mp3
            ? ["-c:a", "libmp3lame", "-q:a", "\(options.mp3VBR())"]
            : ["-c:a", "aac", "-b:a", "\(options.audioKbps())k", "-movflags", "+faststart"]
        return args + ["-filter_complex", graph, "-map", "[a]"] + codec + [output]
    }

    /// Lossy PNG optimisation (like TinyPNG): quantise to an 8-bit palette, keeping alpha.
    public static func pngQuantizeArguments(colors: Int) -> [String] {
        ["-vf", "split[a][b];[a]palettegen=max_colors=\(colors):reserve_transparent=1[p];[b][p]paletteuse=dither=sierra2_4a:alpha_threshold=128",
         "-frames:v", "1"]
    }

    /// Even-sized output (H.264/HEVC need it), optionally scaled down.
    static func videoScaleFilter(_ size: ConversionOptions.Size) -> String {
        switch size {
        case .half:
            return "scale=trunc(iw/4)*2:trunc(ih/4)*2"
        case .maxDimension(let px):
            return "scale=w='if(gte(iw,ih),trunc(min(\(px),iw)/2)*2,-2)':h='if(gte(iw,ih),-2,trunc(min(\(px),ih)/2)*2)'"
        default:
            return "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        }
    }

    private static func audio(copyIf canCopy: Bool, _ encode: [String], metadata: [String], extra: [String] = []) -> MediaPlan {
        let common = ["-vn"] + metadata
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
                if let size = firstMatch(#", (\d{2,5})x(\d{2,5})[ ,\[]"#, in: String(line)) {
                    probe.width = Int(size[0])
                    probe.height = Int(size[1])
                }
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
