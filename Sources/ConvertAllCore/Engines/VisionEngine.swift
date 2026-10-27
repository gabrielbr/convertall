#if os(macOS)
import CoreImage
import Foundation
import PDFKit
import Vision

/// On-device intelligence via Apple's Vision framework (nothing leaves the Mac):
///   • OCR — text from photos, screenshots and scanned PDFs
///   • Background removal — the main subject on a transparent background (macOS 14+)
public enum VisionEngine {
    public static var canRemoveBackground: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    // MARK: OCR

    /// Recognised text of an image, top to bottom, one line per text line.
    static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? [])
            .sorted { a, b in
                // Top to bottom (Vision's origin is bottom-left), then left to right on the same line.
                abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01
                    ? a.boundingBox.midY > b.boundingBox.midY
                    : a.boundingBox.minX < b.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// Text of a scanned PDF, page by page.
    static func recognizeText(in pdf: PDFDocument, task: ConversionTask? = nil) throws -> String {
        var pages: [String] = []
        for i in 0..<pdf.pageCount {
            try task?.checkCancelled()
            guard let page = pdf.page(at: i) else { continue }
            pages.append(try recognizeText(in: PDFRasterizer.render(page, scale: 3)))
            task?.report(Double(i + 1) / Double(pdf.pageCount) * 0.9)
        }
        return pages.joined(separator: "\n\n")
    }

    /// "Extract text": image or PDF → .txt next to the original.
    public static func extractText(_ url: URL, from source: FileFormat, task: ConversionTask = ConversionTask()) throws -> URL {
        let text: String
        if source == .pdf {
            guard let pdf = PDFDocument(url: url) else { throw ConversionError.unreadable(url.lastPathComponent) }
            let embedded = pdf.string ?? ""
            text = embedded.contains(where: { !$0.isWhitespace }) ? embedded : try recognizeText(in: pdf, task: task)
        } else {
            text = try recognizeText(in: ImageConverter.loadImage(at: url).0)
        }
        guard text.contains(where: { !$0.isWhitespace }) else { throw ConversionError.noTextFound }
        let work = try WorkDirectory()
        defer { work.remove() }
        let out = work.file("text.txt")
        try text.write(to: out, atomically: true, encoding: .utf8)
        task.report(1)
        return try deliver(out, to: OutputNaming.destination(for: url, format: .txt))
    }

    // MARK: Background removal

    /// "Cutout": the photo's subject on a transparent background, as PNG (or the
    /// source format when it can hold transparency).
    public static func removeBackground(
        _ url: URL, from source: FileFormat, options: ConversionOptions = ConversionOptions(),
        task: ConversionTask = ConversionTask()
    ) throws -> URL {
        guard #available(macOS 14.0, *) else { throw ConversionError.writeFailed("background removal needs macOS 14") }
        let (image, _) = try ImageConverter.loadImage(at: url)
        task.report(0.2)
        let cutout = try cutOut(image)
        task.report(0.8)
        let format: FileFormat = [.png, .webp, .heic, .tiff].contains(source) && ImageConverter.canWrite(source) ? source : .png
        let destination = OutputNaming.destination(for: url, format: format, suffix: "no background")
        let out = try ImageConverter.export(cutout, as: format, to: destination, options: options)
        task.report(1)
        return out
    }

    @available(macOS 14.0, *)
    private static func cutOut(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw ConversionError.noSubject
        }
        let buffer = try result.generateMaskedImage(
            ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let out = CIContext().createCGImage(ci, from: ci.extent) else {
            throw ConversionError.writeFailed("couldn't build the cutout")
        }
        return out
    }
}
#endif
