#if os(macOS)
import CryptoKit
import Foundation

/// The optional document pack: the official LibreOffice build from The Document Foundation,
/// downloaded once into Application Support (no separate install), verified against the
/// SHA-256 TDF publishes. Powers spreadsheets and presentations.
public enum OfficePack {
    public static let version = "26.8.1"

    struct Build {
        let url: URL
        let sha256: String
        let size: Int64
    }

    static var build: Build {
        let base = "https://download.documentfoundation.org/libreoffice/stable/\(version)/mac"
        #if arch(arm64)
        return Build(url: URL(string: "\(base)/aarch64/LibreOffice_\(version)_MacOS_aarch64.dmg")!,
                     sha256: "ca074e0b13571efb30a31fc531c5f95e997030637325e5d5de92d67aefdf0dfc", size: 298_845_477)
        #else
        return Build(url: URL(string: "\(base)/x86_64/LibreOffice_\(version)_MacOS_x86-64.dmg")!,
                     sha256: "4c7464313a529e9074400cbcdc894fc40ac4ef9421ded03b16b5a78d12cb155e", size: 309_092_706)
        #endif
    }

    public static var downloadSizeText: String {
        ByteCountFormatter.string(fromByteCount: build.size, countStyle: .file)
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConvertAll/Engines/LibreOffice-\(version)", isDirectory: true)
    }

    static var app: URL { directory.appendingPathComponent("LibreOffice.app") }

    public static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/soffice").path)
    }

    public static func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        let build = build
        let dmg = try await Downloader.download(build.url) { progress($0 * 0.85) }
        defer { try? FileManager.default.removeItem(at: dmg) }

        try await Task.detached(priority: .userInitiated) {
            guard try sha256(of: dmg) == build.sha256 else {
                throw ConversionError.writeFailed("the downloaded document pack failed verification")
            }
            progress(0.9)

            let work = try WorkDirectory()
            defer { work.remove() }
            let mount = work.file("mnt")
            let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
            // "Y" answers a licence prompt if the image ever shows one.
            let attach = try ProcessRunner.run(hdiutil, [
                "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path,
            ], input: Data("Y\n".utf8))
            guard attach.status == 0 else { throw ConversionError.writeFailed("couldn't open the document pack") }
            defer { _ = try? ProcessRunner.run(hdiutil, ["detach", mount.path, "-force"]) }

            let staged = work.file("LibreOffice.app")
            let copy = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                             [mount.appendingPathComponent("LibreOffice.app").path, staged.path])
            guard copy.status == 0 else { throw ConversionError.writeFailed("couldn't unpack the document pack") }

            let fm = FileManager.default
            try? fm.removeItem(at: directory)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.moveItem(at: staged, to: app)
        }.value
        progress(1)
    }

    /// Streams the file through SHA-256 (the image is ~300 MB; don't load it at once).
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
#endif
