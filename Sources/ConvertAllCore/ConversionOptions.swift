import Foundation

/// The chip's options strip: how hard to compress, how big the result may be,
/// and whether to drop metadata. Persisted between conversions.
public struct ConversionOptions: Codable, Equatable, Sendable {
    public enum Quality: String, CaseIterable, Codable, Sendable {
        case smaller, balanced, best

        public var title: String {
            switch self {
            case .smaller: "Smaller"
            case .balanced: "Balanced"
            case .best: "Best"
            }
        }
    }

    public enum Size: Codable, Equatable, Hashable, Sendable {
        case original
        case half
        /// Longest side at most this many pixels (never upscales).
        case maxDimension(Int)
        /// Aim for a file no bigger than this (images, video, audio).
        case targetBytes(Int64)

        public var title: String {
            switch self {
            case .original: "Original size"
            case .half: "50%"
            case .maxDimension(let px): "Max \(px) px"
            case .targetBytes(let bytes): "Under \(Self.sizeText(bytes))"
            }
        }

        /// Short form for the options strip button.
        public var shortTitle: String {
            switch self {
            case .original: "Original"
            case .half: "50%"
            case .maxDimension(let px): "≤ \(px) px"
            case .targetBytes(let bytes): "≤ \(Self.sizeText(bytes))"
            }
        }

        public var changesDimensions: Bool {
            switch self {
            case .half, .maxDimension: true
            default: false
            }
        }

        public var targetBytes: Int64? {
            if case .targetBytes(let b) = self { return b }
            return nil
        }

        public static let presets: [Size] = [
            .original, .half, .maxDimension(3840), .maxDimension(1920), .maxDimension(1280), .maxDimension(640),
        ]
        public static let targetPresets: [Size] = [500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000, 25_000_000]
            .map { .targetBytes($0) }

        static func sizeText(_ bytes: Int64) -> String {
            bytes >= 1_000_000 ? "\(bytes / 1_000_000) MB" : "\(bytes / 1000) KB"
        }

        /// New pixel size for an image of `width`×`height` (aspect kept, never upscaled).
        public func scaled(width: Int, height: Int) -> (width: Int, height: Int) {
            let longest = max(width, height)
            let factor: Double
            switch self {
            case .half: factor = 0.5
            case .maxDimension(let px) where longest > px: factor = Double(px) / Double(longest)
            default: return (width, height)
            }
            return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
        }
    }

    public var quality: Quality
    public var size: Size
    public var stripMetadata: Bool

    public init(quality: Quality = .balanced, size: Size = .original, stripMetadata: Bool = false) {
        self.quality = quality
        self.size = size
        self.stripMetadata = stripMetadata
    }

    public var isDefault: Bool { self == ConversionOptions() }

    // MARK: Encoder settings
    //
    // "Compress" (same format in, same format out) leans one notch smaller than a plain
    // conversion — the point is a lighter file, and the source is usually already lossy.

    /// 0…1 for JPEG/HEIC/WebP/AVIF.
    public func imageQuality(compress: Bool = false) -> Double {
        switch (quality, compress) {
        case (.smaller, false): 0.65
        case (.balanced, false): 0.85
        case (.best, false): 0.95
        case (.smaller, true): 0.5
        case (.balanced, true): 0.7
        case (.best, true): 0.85
        }
    }

    public func x264CRF(compress: Bool = false) -> Int {
        switch quality {
        case .smaller: compress ? 30 : 26
        case .balanced: compress ? 26 : 21
        case .best: compress ? 22 : 18
        }
    }

    /// VideoToolbox constant quality (1–100, higher is better).
    public func videoToolboxQuality(compress: Bool = false) -> Int {
        switch quality {
        case .smaller: compress ? 40 : 50
        case .balanced: compress ? 50 : 62
        case .best: compress ? 62 : 75
        }
    }

    public var vp9CRF: Int {
        switch quality {
        case .smaller: 40
        case .balanced: 33
        case .best: 26
        }
    }

    /// AAC/Opus bitrate.
    public func audioKbps(compress: Bool = false) -> Int {
        switch quality {
        case .smaller: compress ? 64 : 96
        case .balanced: compress ? 112 : 160
        case .best: compress ? 160 : 256
        }
    }

    /// LAME VBR level (0 best … 9 smallest).
    public func mp3VBR(compress: Bool = false) -> Int {
        switch quality {
        case .smaller: compress ? 7 : 5
        case .balanced: compress ? 5 : 2
        case .best: compress ? 3 : 0
        }
    }

    public var vorbisQuality: Int {
        switch quality {
        case .smaller: 3
        case .balanced: 5
        case .best: 8
        }
    }

    /// Animated GIF: frame rate, default width and palette size.
    public var gifFPS: Int { quality == .smaller ? 10 : (quality == .balanced ? 12 : 15) }
    public var gifWidth: Int { quality == .smaller ? 480 : (quality == .balanced ? 720 : 960) }
    public var gifColors: Int { quality == .smaller ? 64 : (quality == .balanced ? 128 : 256) }

    /// Splits a byte budget into video/audio bitrates (kbps) for a clip of `duration` seconds.
    public static func bitrateBudget(bytes: Int64, duration: Double?, hasAudio: Bool) -> (video: Int, audio: Int)? {
        guard let duration, duration > 0 else { return nil }
        let totalKbps = Double(bytes) * 8 / duration / 1000 * 0.95  // 5% container overhead
        let audio = hasAudio ? Int(min(128, max(32, totalKbps * 0.12))) : 0
        return (max(50, Int(totalKbps) - audio), audio)
    }
}
