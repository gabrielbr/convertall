import Foundation

/// Expands a Finder selection: folders become the convertible files inside them
/// (recursively, skipping hidden files and app/package bundles).
public enum FolderScanner {
    public static let maxFiles = 10_000

    public static func expand(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            guard result.count < maxFiles, FileFormat(url: url) != nil else { return }
            if seen.insert(url.standardizedFileURL.path).inserted { result.append(url) }
        }

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            guard isDir.boolValue, !isPackage(url) else {
                add(url)
                continue
            }
            guard let walker = fm.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var found: [URL] = []
            while let file = walker.nextObject() as? URL {
                if isPackage(file) { walker.skipDescendants(); continue }
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { found.append(file) }
            }
            found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }.forEach(add)
        }
        return result
    }

    /// Whether the selection included at least one folder (changes the chip's wording).
    public static func containsFolder(_ urls: [URL]) -> Bool {
        urls.contains { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue && !isPackage(url)
        }
    }

    private static func isPackage(_ url: URL) -> Bool {
        ["app", "bundle", "framework", "photoslibrary", "pages", "numbers", "key", "xcodeproj", "playground"]
            .contains(url.pathExtension.lowercased())
    }
}
