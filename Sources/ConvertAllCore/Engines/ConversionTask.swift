#if os(macOS)
import Foundation

/// A running conversion: reports progress and can be cancelled from the UI
/// (cancelling terminates any helper process such as FFmpeg or LibreOffice).
public final class ConversionTask: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    private let progressHandler: @Sendable (Double) -> Void

    public init(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) {
        progressHandler = onProgress
    }

    public var isCancelled: Bool { lock.locked { cancelled } }

    public func cancel() {
        let p: Process? = lock.locked {
            cancelled = true
            return process
        }
        if let p, p.isRunning { p.terminate() }
    }

    /// 0…1. Called from background threads.
    public func report(_ fraction: Double) {
        progressHandler(min(max(fraction, 0), 1))
    }

    func checkCancelled() throws {
        if isCancelled { throw CancellationError() }
    }

    func attach(_ p: Process) throws {
        try lock.locked {
            if cancelled { throw CancellationError() }
            process = p
        }
    }

    func detach() { lock.locked { process = nil } }
}

/// Runs a helper tool, streaming its output line by line (FFmpeg reports progress on stderr).
enum ProcessRunner {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(
        _ executable: URL, _ arguments: [String], task: ConversionTask? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = OutputCollector(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collector.append(data) }
        }

        try task?.attach(process)
        defer { task?.detach() }
        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        collector.append(pipe.fileHandleForReading.readDataToEndOfFile())

        try task?.checkCancelled()
        return Result(status: process.terminationStatus, output: collector.text)
    }
}

/// Thread-safe accumulator that splits output on \n and \r (FFmpeg rewrites its status line with \r).
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var partial = ""
    private let onLine: (@Sendable (String) -> Void)?
    private let limit = 256 * 1024

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    var text: String { lock.locked { buffer + partial } }

    func append(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return }
        var lines: [String] = []
        lock.locked {
            partial += chunk
            while let i = partial.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let line = String(partial[..<i])
                partial = String(partial[partial.index(after: i)...])
                if !line.isEmpty { lines.append(line); buffer += line + "\n" }
            }
            if buffer.count > limit { buffer = String(buffer.suffix(limit / 2)) }
        }
        lines.forEach { onLine?($0) }
    }
}

/// Downloads a file with progress (used for the media engine and app updates).
enum Downloader {
    static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let progress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        private let lock = NSLock()

        init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

        private func finish(_ result: Result<URL, Error>) {
            let c: CheckedContinuation<URL, Error>? = lock.locked {
                defer { continuation = nil }
                return continuation
            }
            c?.resume(with: result)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return finish(.failure(ConversionError.writeFailed("download failed (HTTP \(http.statusCode))")))
            }
            // The system deletes `location` when this method returns; move it somewhere stable.
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertAll-dl-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: location, to: keep)
                finish(.success(keep))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(.failure(error)) }
        }
    }
}

/// Scratch space for one conversion, removed afterwards.
struct WorkDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertAll-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// Moves a finished temp file to its final place (next to the original).
func deliver(_ temp: URL, to destination: URL) throws -> URL {
    guard FileManager.default.fileExists(atPath: temp.path) else {
        throw ConversionError.writeFailed("the converter produced no file")
    }
    do {
        try FileManager.default.moveItem(at: temp, to: destination)
    } catch {
        throw ConversionError.writeFailed(error.localizedDescription)
    }
    return destination
}

/// Some AppKit text APIs (HTML import in particular) must run on the main thread.
func onMain<T>(_ body: () throws -> T) rethrows -> T {
    if Thread.isMainThread { return try body() }
    return try DispatchQueue.main.sync(execute: body)
}
#endif

#if os(macOS)
extension NSLock {
    /// `NSLocking.withLock` needs macOS 14; this works on 13.
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif
