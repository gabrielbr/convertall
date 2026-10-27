#if os(macOS)
import AppKit
import Foundation

/// Spreadsheets and presentations through LibreOffice: the one-click document pack
/// (`OfficePack`) or a LibreOffice the user installed themselves.
public enum OfficeEngine {
    public static let downloadPage = URL(string: "https://www.libreoffice.org/download/download-libreoffice/")!

    public static var sofficeURL: URL? {
        var candidates = [
            URL(fileURLWithPath: "/Applications/LibreOffice.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LibreOffice.app"),
        ]
        if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.libreoffice.script") {
            candidates.insert(found, at: 0)
        }
        candidates.append(OfficePack.app)  // the document pack, when the user has no LibreOffice of their own
        return candidates
            .map { $0.appendingPathComponent("Contents/MacOS/soffice") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// A private profile so conversions work even while LibreOffice is open,
    /// and stay fast after the first run.
    private static var profile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConvertAll/LibreOfficeProfile", isDirectory: true)
    }

    static func convert(
        _ url: URL, from source: FileFormat, to target: FileFormat, options: ConversionOptions, task: ConversionTask
    ) throws -> [URL] {
        guard let soffice = sofficeURL else { throw ConversionError.engineMissing(target) }
        let work = try WorkDirectory()
        defer { work.remove() }

        let produce: FileFormat = target.category == .image ? .pdf : target
        let filter = produce == .csv ? "csv:Text - txt - csv (StarCalc):44,34,76,1" : produce.preferredExtension
        // LibreOffice names output after the input; copy it to a simple name first.
        let input = work.file("in.\(source.preferredExtension)")
        try FileManager.default.copyItem(at: url, to: input)
        let outDir = work.file("out")

        task.report(0.05)
        let result = try ProcessRunner.run(soffice, [
            "-env:UserInstallation=\(profile.absoluteString)",
            "--headless", "--norestore", "--nolockcheck",
            "--convert-to", filter, "--outdir", outDir.path, input.path,
        ], task: task)
        let out = outDir.appendingPathComponent("in.\(produce.preferredExtension)")
        guard result.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            throw ConversionError.writeFailed(FFmpeg.errorSummary(result.output))
        }

        if target.category == .image {
            task.report(0.5)
            return try PDFRasterizer.export(out, as: target, namedAfter: url, options: options, task: task, progressRange: 0.5...1)
        }
        task.report(1)
        return [try deliver(out, to: OutputNaming.destination(for: url, format: target))]
    }
}
#endif
