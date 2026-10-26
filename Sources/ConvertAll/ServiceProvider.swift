#if os(macOS)
import AppKit

/// Backs the Finder right-click item "Quick Actions › Convert with ConvertAll"
/// (declared under NSServices in Info.plist).
final class ServiceProvider: NSObject {
    @objc func convertFiles(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were selected." as NSString
            return
        }
        Task { @MainActor in (NSApp.delegate as? AppDelegate)?.open(urls) }
    }
}
#endif
