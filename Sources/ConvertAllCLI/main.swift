import ConvertAllCore
import Foundation

// `convertall` — the same engines as the app, for Terminal, scripts, Shortcuts
// ("Run Shell Script") and launchers like Raycast or Alfred.

let usage = """
usage: convertall <files or folders>... <action> [options]

actions (pick one):
  --to <format>          convert, e.g. --to png, --to mp4, --to pdf
  --smaller              same format, smaller file
  --combine <format>     everything into one file: pdf, mp4, mp3 or m4a
  --text                 OCR: recognise text → .txt
  --cutout               remove the background (macOS 14+)

options:
  --quality <q>          smaller | balanced (default) | best
  --size <s>             50% | <pixels> (longest side) | <n>KB | <n>MB (target file size)
  --no-metadata          strip location, camera and author details
  --trim <start-end>     keep part of a video/audio clip, e.g. 0:10-1:05 or 10-65
  --install-engine       download what's missing (media engine or document pack), then continue
  --formats              list every format and what it converts to
  --version

Converted files are saved next to the originals (never overwriting). Their paths
are printed one per line; errors go to stderr and set a non-zero exit code.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("convertall: \(message)\n".utf8))
    exit(code)
}

#if os(macOS)
enum Action {
    case convert(FileFormat), smaller, combine(FileFormat), text, cutout
}

var paths: [String] = []
var action: Action?
var options = ConversionOptions()
var trim: ClosedRange<Double>?
var installEngine = false

func parseTime(_ s: String) -> Double? {
    let parts = s.split(separator: ":").map { Double($0) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
    return parts.reduce(0) { $0 * 60 + $1! }
}

func format(_ s: String?) -> FileFormat {
    guard let s, let f = FileFormat(fileExtension: s) ?? FileFormat(rawValue: s.lowercased()) else {
        fail("unknown format '\(s ?? "")' — see --formats")
    }
    return f
}

var args = Array(CommandLine.arguments.dropFirst())[...]
if args.isEmpty { print(usage); exit(0) }
while let arg = args.popFirst() {
    switch arg {
    case "-h", "--help": print(usage); exit(0)
    case "--version": print(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"); exit(0)
    case "--formats":
        for f in FileFormat.allCases {
            print("\(f.displayName.padding(toLength: 6, withPad: " ", startingAt: 0)) → \(ConversionMatrix.targets(for: f).map(\.displayName).joined(separator: " "))")
        }
        exit(0)
    case "--to": action = .convert(format(args.popFirst()))
    case "--smaller": action = .smaller
    case "--combine": action = .combine(format(args.popFirst()))
    case "--text": action = .text
    case "--cutout": action = .cutout
    case "--no-metadata": options.stripMetadata = true
    case "--install-engine": installEngine = true
    case "--quality":
        guard let q = args.popFirst().flatMap(ConversionOptions.Quality.init(rawValue:)) else { fail("--quality takes smaller, balanced or best") }
        options.quality = q
    case "--size":
        guard let s = args.popFirst()?.lowercased() else { fail("--size needs a value") }
        if s.hasSuffix("%"), Int(s.dropLast()) == 50 { options.size = .half }
        else if s.hasSuffix("mb"), let n = Double(s.dropLast(2)) { options.size = .targetBytes(Int64(n * 1_000_000)) }
        else if s.hasSuffix("kb"), let n = Double(s.dropLast(2)) { options.size = .targetBytes(Int64(n * 1000)) }
        else if let px = Int(s.replacingOccurrences(of: "px", with: "")) { options.size = .maxDimension(px) }
        else { fail("--size takes 50%, a pixel size like 1920, or a file size like 5MB") }
    case "--trim":
        let parts = (args.popFirst() ?? "").split(separator: "-").map(String.init)
        guard parts.count == 2, let a = parseTime(parts[0]), let b = parseTime(parts[1]), b > a else {
            fail("--trim takes start-end, e.g. 0:10-1:05")
        }
        trim = a...b
    default:
        if arg.hasPrefix("--") { fail("unknown option \(arg)\n\n\(usage)", code: 64) }
        paths.append(arg)
    }
}

guard let action else { fail("choose what to do: --to <format>, --smaller, --combine, --text or --cutout", code: 64) }
let files = FolderScanner.expand(paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
guard !files.isEmpty else { fail("no convertible files given") }
let sources = files.map { Converter.sourceFormat(of: $0) ?? FileFormat(url: $0)! }

let wantedFormat: FileFormat? = {
    switch action {
    case .convert(let f), .combine(let f): return f
    case .smaller: return sources.first
    default: return nil
    }
}()
let needsOffice = wantedFormat.map { f in zip(files, sources).contains { Converter.requirement(from: $1, to: f) == .libreOffice } } ?? false
if installEngine, needsOffice {
    FileHandle.standardError.write(Data("Downloading the document pack (\(OfficePack.downloadSizeText))…\n".utf8))
    final class Outcome: @unchecked Sendable { var error: Error? }
    let outcome = Outcome()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do { try await OfficePack.install { _ in } } catch { outcome.error = error }
        done.signal()
    }
    done.wait()
    if let error = outcome.error { fail("couldn't install the document pack: \(error.localizedDescription)") }
}
if installEngine, MediaEngine.ffmpegURL == nil, !needsOffice {
    FileHandle.standardError.write(Data("Downloading the media engine (\(MediaPack.downloadSizeText))…\n".utf8))
    final class Outcome: @unchecked Sendable { var error: Error? }
    let outcome = Outcome()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do { try await MediaPack.install { _ in } } catch { outcome.error = error }
        done.signal()
    }
    done.wait()
    if let error = outcome.error { fail("couldn't install the media engine: \(error.localizedDescription)") }
}

var failures = 0
func run(_ name: String, _ body: () throws -> [URL]) {
    do {
        for url in try body() { print(url.path) }
    } catch {
        failures += 1
        var message = error.localizedDescription
        if case ConversionError.engineMissing = error {
            message += " Re-run with --install-engine."
        }
        FileHandle.standardError.write(Data("convertall: \(name): \(message)\n".utf8))
    }
}

switch action {
case .combine(let target):
    run(files[0].lastPathComponent) { [try Combiner.combine(files, sources: sources, to: target, options: options)] }
default:
    for (file, source) in zip(files, sources) {
        run(file.lastPathComponent) {
            switch action {
            case .convert(let target):
                guard ConversionMatrix.targets(for: source).contains(target) || Converter.isAnimated(file, format: source) else {
                    throw ConversionError.writeFailed("\(source.displayName) can't become \(target.displayName)")
                }
                return try Converter.convert(file, from: source, to: target, options: options, trim: trim)
            case .smaller:
                return try Converter.convert(file, from: source, to: source, options: options, trim: trim)
            case .text:
                return [try VisionEngine.extractText(file, from: source)]
            case .cutout:
                return [try VisionEngine.removeBackground(file, from: source, options: options)]
            case .combine:
                return []
            }
        }
    }
}
exit(failures == 0 ? 0 : 1)
#else
fail("convertall needs macOS")
#endif
