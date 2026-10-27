#if os(macOS)
import AppKit
import Foundation
import PDFKit

/// Text documents with no extra install: DOCX, DOC, ODT, RTF, TXT and HTML via the
/// Cocoa text system; PDF via PDFKit. Images come from rendered PDF pages.
enum DocumentEngine {
    static func convert(
        _ url: URL, from source: FileFormat, to target: FileFormat, options: ConversionOptions, task: ConversionTask
    ) throws -> [URL] {
        let work = try WorkDirectory()
        defer { work.remove() }

        if source == .pdf, target == .pdf {
            return [try compressPDF(url, options: options, work: work)]
        }

        if target.category == .image {
            let pdf: URL
            if source == .pdf {
                pdf = url
            } else {
                pdf = work.file("doc.pdf")
                try writePDF(try read(url, as: source), to: pdf)
            }
            task.report(0.2)
            return try PDFRasterizer.export(pdf, as: target, namedAfter: url, options: options, task: task, progressRange: 0.2...1)
        }

        let text = try read(url, as: source)
        task.report(0.5)
        let out = work.file("out.\(target.preferredExtension)")
        if target == .pdf {
            try writePDF(text, to: out)
        } else {
            try write(text, as: target, to: out)
        }
        task.report(1)
        return [try deliver(out, to: OutputNaming.destination(for: url, format: target))]
    }

    /// PDFKit's own "reduce size": images re-encoded as JPEG and downsampled for screens.
    static func compressPDF(_ url: URL, options: ConversionOptions, work: WorkDirectory) throws -> URL {
        guard let pdf = PDFDocument(url: url) else { throw ConversionError.unreadable(url.lastPathComponent) }
        if options.stripMetadata { pdf.documentAttributes = [:] }
        var writeOptions: [PDFDocumentWriteOption: Any] = [:]
        if #available(macOS 13.4, *) {
            writeOptions[.saveImagesAsJPEGOption] = true
            if options.quality != .best { writeOptions[.optimizeImagesForScreenOption] = true }
        }
        let out = work.file("out.pdf")
        guard pdf.write(to: out, withOptions: writeOptions) else { throw ConversionError.writeFailed("couldn't save the PDF") }
        return try deliver(out, to: OutputNaming.destination(for: url, format: .pdf))
    }

    // MARK: Reading

    static func read(_ url: URL, as format: FileFormat) throws -> NSAttributedString {
        switch format {
        case .pdf:
            guard let pdf = PDFDocument(url: url) else { throw ConversionError.unreadable(url.lastPathComponent) }
            let result = NSMutableAttributedString()
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i)?.attributedString, page.length > 0 else { continue }
                if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
                result.append(page)
            }
            guard result.string.contains(where: { !$0.isWhitespace }) else { throw ConversionError.noText }
            return result

        case .txt:
            var encoding = String.Encoding.utf8
            let string = try (try? String(contentsOf: url, usedEncoding: &encoding))
                ?? String(contentsOf: url, encoding: .isoLatin1)
            return NSAttributedString(string: string, attributes: bodyAttributes)

        default:
            guard let type = documentType(for: format) else { throw ConversionError.unreadable(url.lastPathComponent) }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
            if format == .html { options[.characterEncoding] = String.Encoding.utf8.rawValue }
            do {
                // HTML import uses WebKit and must happen on the main thread.
                return try onMain { try NSAttributedString(url: url, options: options, documentAttributes: nil) }
            } catch {
                throw ConversionError.unreadable(url.lastPathComponent)
            }
        }
    }

    // MARK: Writing

    static func write(_ text: NSAttributedString, as format: FileFormat, to url: URL) throws {
        if format == .txt {
            try text.string.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let type = documentType(for: format) else { throw ConversionError.engineMissing(format) }
        let data = try onMain {
            try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
        }
        try data.write(to: url)
    }

    /// Lays the text out on pages (A4 or US Letter, from the user's region) and writes a PDF.
    static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        let usesLetter = ["US", "CA", "MX", "PH"].contains(Locale.current.region?.identifier ?? "")
        var page = usesLetter ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 56
        let content = CGSize(width: page.width - margin * 2, height: page.height - margin * 2)

        try onMain {
            let storage = NSTextStorage(attributedString: text.length > 0 ? text : NSAttributedString(string: " "))
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            var ranges: [NSRange] = []
            while ranges.count < 5000 {
                let container = NSTextContainer(size: content)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                let range = layout.glyphRange(for: container)
                ranges.append(range)
                if NSMaxRange(range) >= layout.numberOfGlyphs || range.length == 0 { break }
            }

            guard let ctx = CGContext(url as CFURL, mediaBox: &page, nil) else {
                throw ConversionError.writeFailed("couldn't create the PDF")
            }
            for range in ranges {
                ctx.beginPDFPage(nil)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: page.height)
                ctx.scaleBy(x: 1, y: -1)  // TextKit draws in flipped coordinates
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                let origin = CGPoint(x: margin, y: margin)
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
                NSGraphicsContext.restoreGraphicsState()
                ctx.restoreGState()
                ctx.endPDFPage()
            }
            ctx.closePDF()
        }
    }

    private static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
    }

    private static func documentType(for format: FileFormat) -> NSAttributedString.DocumentType? {
        switch format {
        case .docx: .officeOpenXML
        case .doc: .docFormat
        case .odt: .openDocument
        case .rtf: .rtf
        case .html: .html
        case .txt: .plain
        default: nil
        }
    }
}

/// PDF pages → images, one file per page (in a folder when there are several).
enum PDFRasterizer {
    /// 144 dpi: crisp on Retina screens without huge files.
    static let scale: CGFloat = 2
    static let maxPages = 500

    static func export(
        _ pdfURL: URL, as format: FileFormat, namedAfter source: URL, options: ConversionOptions,
        task: ConversionTask, progressRange: ClosedRange<Double> = 0...1
    ) throws -> [URL] {
        guard let pdf = PDFDocument(url: pdfURL), pdf.pageCount > 0 else {
            throw ConversionError.unreadable(source.lastPathComponent)
        }
        let count = min(pdf.pageCount, maxPages)
        let destinations: [URL]
        if count == 1 {
            destinations = [OutputNaming.destination(for: source, format: format)]
        } else {
            let folder = OutputNaming.folder(for: source, format: format)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            destinations = OutputNaming.pageFiles(for: source, format: format, count: count, in: folder)
        }

        for (i, destination) in destinations.enumerated() {
            try task.checkCancelled()
            guard let page = pdf.page(at: i) else { continue }
            let image = try render(page)
            try ImageConverter.export(image, as: format, to: destination, options: options)
            let span = progressRange.upperBound - progressRange.lowerBound
            task.report(progressRange.lowerBound + span * Double(i + 1) / Double(count))
        }
        // Reveal the folder rather than hundreds of files.
        return count == 1 ? destinations : [destinations[0].deletingLastPathComponent()]
    }

    private static func render(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let size = CGSize(width: rotated ? bounds.height : bounds.width, height: rotated ? bounds.width : bounds.height)
        let w = max(1, Int(size.width * scale)), h = max(1, Int(size.height * scale))
        guard let ctx = ImageConverter.rgbaContext(width: w, height: h) else {
            throw ConversionError.writeFailed("page too large")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: ctx)  // applies the page's rotation
        guard let image = ctx.makeImage() else { throw ConversionError.writeFailed("couldn't render page") }
        return image
    }
}
#endif
