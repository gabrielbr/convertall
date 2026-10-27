import Foundation

/// Identifies a file by its first bytes, not its name. Powers rename-to-convert
/// (`photo.jpg` renamed to `photo.png` is still a JPEG inside → convert it) and
/// recognises misnamed or extension-less files.
public enum FileSniffer {
    /// Bytes needed for a confident answer.
    public static let headerLength = 4096

    public static func detect(url: URL) -> FileFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: headerLength)) ?? Data()
        return detect([UInt8](data), extensionHint: url.pathExtension)
    }

    /// - Parameter extensionHint: breaks ties the bytes can't (old Office files share one container).
    public static func detect(_ b: [UInt8], extensionHint: String = "") -> FileFormat? {
        func at(_ offset: Int, _ bytes: [UInt8]) -> Bool {
            b.count >= offset + bytes.count && Array(b[offset..<offset + bytes.count]) == bytes
        }
        func ascii(_ offset: Int, _ text: String) -> Bool { at(offset, Array(text.utf8)) }
        let hint = FileFormat(fileExtension: extensionHint)

        // Images
        if at(0, [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if ascii(0, "GIF87a") || ascii(0, "GIF89a") { return .gif }
        if ascii(0, "RIFF") {
            if ascii(8, "WEBP") { return .webp }
            if ascii(8, "WAVE") { return .wav }
            if ascii(8, "AVI ") { return .avi }
        }
        if at(0, [0x49, 0x49, 0x2A, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if ascii(0, "BM"), b.count > 14 { return .bmp }
        if at(0, [0x00, 0x00, 0x01, 0x00]) { return .ico }
        if ascii(0, "qoif") { return .qoi }
        if at(0, [0x76, 0x2F, 0x31, 0x01]) { return .exr }
        if b.count >= 3, b[0] == UInt8(ascii: "P"), (UInt8(ascii: "1")...UInt8(ascii: "6")).contains(b[1]),
           [0x20, 0x09, 0x0A, 0x0D].contains(b[2]) { return .pnm }

        // ISO base media (MP4 family): a "ftyp" box at offset 4, brand at 8.
        if ascii(4, "ftyp"), b.count >= 12 {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            switch brand {
            case "heic", "heix", "hevc", "heim", "heis", "hevx", "mif1", "msf1": return .heic
            case "avif", "avis": return .avif
            case "qt  ": return .mov
            case "M4A ", "M4B ", "M4P ": return .m4a
            default: return .mp4
            }
        }
        if at(0, [0x1A, 0x45, 0xDF, 0xA3]) {
            return contains(b, "webm", within: 64) ? .webm : .mkv
        }

        // Audio
        if ascii(0, "fLaC") { return .flac }
        if ascii(0, "OggS") { return ascii(28, "OpusHead") ? .opus : .ogg }
        if ascii(0, "ID3") { return .mp3 }
        if b.count >= 2, b[0] == 0xFF {
            if b[1] & 0xF6 == 0xF0 { return .aac }  // ADTS (layer bits 00)
            if b[1] & 0xE0 == 0xE0, b[1] & 0x06 != 0 { return .mp3 }  // MPEG audio frame sync
        }

        // Documents
        if ascii(0, "%PDF") { return .pdf }
        if ascii(0, "{\\rtf") { return .rtf }
        if at(0, [0x50, 0x4B, 0x03, 0x04]) {  // ZIP: OpenDocument or Office Open XML
            if contains(b, "opendocument.text", within: 128) { return .odt }
            if contains(b, "opendocument.spreadsheet", within: 128) { return .ods }
            if contains(b, "opendocument.presentation", within: 128) { return .odp }
            if contains(b, "word/", within: b.count) { return .docx }
            if contains(b, "xl/", within: b.count) { return .xlsx }
            if contains(b, "ppt/", within: b.count) { return .pptx }
            return [.docx, .xlsx, .pptx, .odt, .ods, .odp].contains(hint) ? hint : nil
        }
        if at(0, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {  // old Office (OLE2)
            return [.doc, .xls, .ppt].contains(hint) ? hint : .doc
        }

        // Text-based: look past a BOM and leading whitespace.
        let text = String(decoding: b.prefix(1024), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            .lowercased()
        if text.hasPrefix("<svg") || (text.hasPrefix("<?xml") && text.contains("<svg")) { return .svg }
        if text.hasPrefix("<!doctype html") || text.hasPrefix("<html") { return .html }
        return nil
    }

    private static func contains(_ bytes: [UInt8], _ text: String, within limit: Int) -> Bool {
        let needle = Array(text.utf8)
        let hay = Array(bytes.prefix(limit))
        guard hay.count >= needle.count else { return false }
        for i in 0...(hay.count - needle.count) where hay[i] == needle[0] {
            if Array(hay[i..<i + needle.count]) == needle { return true }
        }
        return false
    }

    /// Rename-to-convert: the file now *claims* one format (its new extension) but *is*
    /// another. Returns (actual, wanted) when ConvertAll can turn one into the other.
    public static func renameIntent(for url: URL) -> (actual: FileFormat, wanted: FileFormat)? {
        guard let wanted = FileFormat(url: url), let actual = detect(url: url), actual != wanted,
              ConversionMatrix.targets(for: actual).contains(wanted)
        else { return nil }
        return (actual, wanted)
    }
}
