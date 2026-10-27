#if os(macOS)
import AppKit
import Foundation
import PDFKit

/// "Combine": many files in, one file out.
///   • images and PDFs → one PDF (pages in selection order)
///   • videos → one MP4 (clips back to back, fitted to the first clip's frame)
///   • audio → one MP3 / M4A
public enum Combiner {
    public static func combine(
        _ files: [URL], sources: [FileFormat], to target: FileFormat,
        options: ConversionOptions = ConversionOptions(), task: ConversionTask = ConversionTask()
    ) throws -> URL {
        guard let first = files.first else { throw ConversionError.unreadable("nothing selected") }
        let destination = OutputNaming.combined(for: first, format: target)
        let work = try WorkDirectory()
        defer { work.remove() }
        let out = work.file("combined.\(target.preferredExtension)")

        switch target {
        case .pdf:
            try pdf(files, sources: sources, options: options, task: task, to: out)
        case .mp4:
            guard let ffmpeg = MediaEngine.ffmpegURL else { throw ConversionError.engineMissing(target) }
            let probes = try files.map { try MediaEngine.probe($0, ffmpeg: ffmpeg) }
            let total = probes.compactMap(\.duration).reduce(0, +)
            let attempts = FFmpeg.joinVideoArguments(
                inputs: zip(files, probes).map { ($0.path, $1) }, output: out.path, options: options)
            try MediaEngine.run(ffmpeg, attempts: attempts, duration: total, task: task, output: out)
        default:
            guard let ffmpeg = MediaEngine.ffmpegURL else { throw ConversionError.engineMissing(target) }
            let total = try files.compactMap { try MediaEngine.probe($0, ffmpeg: ffmpeg).duration }.reduce(0, +)
            let args = FFmpeg.joinAudioArguments(inputPaths: files.map(\.path), to: target, output: out.path, options: options)
            try MediaEngine.run(ffmpeg, attempts: [args], duration: total, task: task, output: out)
        }
        task.report(1)
        return try deliver(out, to: destination)
    }

    /// Images become pages sized to A4/Letter (orientation follows the image); PDF pages are copied as-is.
    private static func pdf(
        _ files: [URL], sources: [FileFormat], options: ConversionOptions, task: ConversionTask, to out: URL
    ) throws {
        let document = PDFDocument()
        let letter = ["US", "CA", "MX", "PH"].contains(Locale.current.region?.identifier ?? "")
        let paper = letter ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)

        for (i, (file, source)) in zip(files, sources).enumerated() {
            try task.checkCancelled()
            if source == .pdf {
                guard let pdf = PDFDocument(url: file) else { throw ConversionError.unreadable(file.lastPathComponent) }
                for p in 0..<pdf.pageCount {
                    if let page = pdf.page(at: p)?.copy() as? PDFPage { document.insert(page, at: document.pageCount) }
                }
            } else {
                let (decoded, _) = try ImageConverter.loadImage(at: file)
                let image = try ImageConverter.resized(decoded, to: options.size)
                let landscape = image.width > image.height
                let box = CGRect(origin: .zero, size: landscape ? CGSize(width: paper.height, height: paper.width) : paper)
                let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                let page: PDFPage?
                if #available(macOS 13.0, *) {
                    page = PDFPage(image: ns, options: [
                        .mediaBox: NSValue(rect: box),
                        .compressionQuality: options.imageQuality(),
                        .upscaleIfSmaller: false,
                    ])
                } else {
                    page = PDFPage(image: ns)
                }
                guard let page else { throw ConversionError.unreadable(file.lastPathComponent) }
                document.insert(page, at: document.pageCount)
            }
            task.report(Double(i + 1) / Double(files.count) * 0.95)
        }
        guard document.pageCount > 0, document.write(to: out) else {
            throw ConversionError.writeFailed("couldn't create the PDF")
        }
    }
}
#endif
