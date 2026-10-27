#if os(macOS)
import CoreServices
import Foundation

/// File-level FSEvents for a set of folders, delivered on the main queue.
final class FolderWatcher {
    struct Event {
        let path: String
        let flags: FSEventStreamEventFlags

        var isFile: Bool { flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 }
        var wasRenamed: Bool { flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 }
        var wasCreatedOrChanged: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified
                | kFSEventStreamEventFlagItemRenamed) != 0
        }
    }

    private var stream: FSEventStreamRef?
    private let handler: ([Event]) -> Void

    init?(paths: [String], latency: TimeInterval = 0.5, handler: @escaping ([Event]) -> Void) {
        guard !paths.isEmpty else { return nil }
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, rawFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as? [String] ?? []
            let events = (0..<min(count, paths.count)).map { Event(path: paths[$0], flags: rawFlags[$0]) }
            watcher.handler(events)
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
#endif
