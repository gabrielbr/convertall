#if os(macOS)
import Foundation

/// A newer ConvertAll published on GitHub Releases.
public struct AvailableUpdate: Equatable, Sendable {
    public let version: AppVersion
    public let downloadURL: URL
    public let pageURL: URL
}

/// Checks GitHub Releases for a newer version and installs it in place.
public enum UpdateInstaller {
    public static let repository = "gabrielbr/convertall"

    public static var currentVersion: AppVersion {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? AppVersion("0")!
    }

    /// nil when already up to date.
    public static func fetchLatest() async throws -> AvailableUpdate? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ConvertAll/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ConversionError.writeFailed("couldn't reach GitHub")
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tag_name), version > currentVersion,
              let asset = release.assets.first(where: { $0.name.hasPrefix("ConvertAll") && $0.name.hasSuffix(".zip") })
        else { return nil }
        return AvailableUpdate(version: version, downloadURL: asset.browser_download_url, pageURL: release.html_url)
    }

    /// Whether this copy of the app can replace itself (it must live in a writable folder,
    /// e.g. /Applications or ~/Applications, not a read-only disk image).
    public static var canInstallInPlace: Bool {
        FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }

    /// Downloads, verifies and swaps in the new version. The caller relaunches afterwards.
    public static func install(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void) async throws {
        let appURL = Bundle.main.bundleURL
        let zip = try await Downloader.download(update.downloadURL) { progress($0 * 0.9) }
        defer { try? FileManager.default.removeItem(at: zip) }

        try await Task.detached(priority: .userInitiated) {
            let work = try WorkDirectory()
            defer { work.remove() }
            let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
            guard try ProcessRunner.run(ditto, ["-x", "-k", zip.path, work.url.path]).status == 0 else {
                throw ConversionError.writeFailed("couldn't unpack the update")
            }
            let newApp = work.file("ConvertAll.app")
            try verify(newApp, expected: update.version)

            // Stage next to the current app (same volume), then swap atomically.
            let staged = appURL.deletingLastPathComponent()
                .appendingPathComponent(".ConvertAll-update-\(UUID().uuidString).app")
            try FileManager.default.moveItem(at: newApp, to: staged)
            do {
                _ = try FileManager.default.replaceItemAt(appURL, withItemAt: staged)
            } catch {
                try? FileManager.default.removeItem(at: staged)
                throw error
            }
        }.value
        progress(1)
    }

    /// Same app, the promised version, and an intact code signature.
    private static func verify(_ app: URL, expected: AppVersion) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              version == expected
        else { throw ConversionError.writeFailed("the downloaded update doesn't look right") }
        let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
        guard try ProcessRunner.run(codesign, ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            throw ConversionError.writeFailed("the downloaded update failed its signature check")
        }
    }

    /// Starts the (new) app once this process has exited.
    public static func relaunch() {
        let script = "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundleURL.path]
        try? process.run()
    }
}
#endif
