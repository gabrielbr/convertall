# ConvertAll

Convert any file to another format, right from Finder. Right-click → **Open With › ConvertAll**, and a small chip appears next to your pointer. Type or click a format, and the new file is saved next to the original.

It handles the full format list from [convt.app/formats](https://convt.app/formats):

| Kind | Formats | Converts to | Engine |
| --- | --- | --- | --- |
| **Images** | JPEG, PNG, WebP, HEIC, AVIF, GIF, TIFF, BMP, ICO, TGA, PPM, QOI, EXR, SVG (input only) | Other images. GIF can also become MP4, MOV, WebM, MKV or AVI | Built in (ImageIO and pure-Swift codecs) |
| **Video** | MP4, MOV, WebM, MKV, AVI | Other video, any audio format (extracts the soundtrack), GIF and other images (one representative frame) | Media engine |
| **Audio** | MP3, WAV, FLAC, AAC, M4A, OGG, Opus | Other audio | Media engine |
| **Documents** | PDF, DOCX, DOC, ODT, RTF, TXT, HTML | Each other, PDF, images (one per page) | Built in (Cocoa text and PDFKit) |
| **Spreadsheets** | XLSX, XLS, ODS, CSV | Each other, PDF, images | LibreOffice |
| **Presentations** | PPTX, PPT, ODP | Each other, PDF, images | LibreOffice |

Two extras are optional and are only needed for some conversions:

- **Media engine.** This is [FFmpeg](https://ffmpeg.org), a static build from [martin-riedl.de](https://ffmpeg.martin-riedl.de) (about 28 MB). It's needed for video and audio conversion. ConvertAll uses it to save WebP and AVIF images too, because macOS can only read those two formats. The first time you pick a format that needs it, the chip offers a one-click **Download & Convert**. The download is pinned to a specific version, its SHA-256 checksum is verified, and it's stored in `~/Library/Application Support/ConvertAll`. If you've installed `ffmpeg` with Homebrew, ConvertAll uses that instead.
- **LibreOffice.** This free app is needed for spreadsheets and presentations. If it isn't installed, the chip links to the download page. ConvertAll finds LibreOffice automatically once it's installed.

Pills that need an extra show a small ⬇︎ badge. Everything else works offline right away.

## How it works for the user

```
          ↖ pointer
 ┌──────────────────────────────────────┐
 │ ▣  holiday.jpg                     ⓧ │
 │    JPEG · 4032×3024 · 3.1 MB         │
 │ ┌──────────────────────────────────┐ │
 │ │ ⟳ Convert to…  type a format     │ │
 │ └──────────────────────────────────┘ │
 │ [ PNG ] [ WebP] [ HEIC] [ AVIF]      │
 │ [ GIF ] [ TIFF] [ ICO ] [ BMP ]      │
 │ [ TGA ] [ EXR ] [ QOI ] [ PPM ]      │
 │ ──────────────────────────────────── │
 │ Lossless · keeps transparency  ↩ ⌘↩  │
 └──────────────────────────────────────┘
```

1. **Right-click a file (or several)** in Finder, then choose **Open With › ConvertAll**, or **Quick Actions › Convert with ConvertAll**.
2. **The chip opens beside the pointer**, like a context menu. Near a screen edge it opens on the other side.
3. **Pick a format.** Formats are grouped by kind (Video, Audio, Images, …). The format you used last that fits this file is already selected. You can pick in any of these ways:
   - Click a pill.
   - Start typing. `p` picks PNG, `jp` or `.jpg` picks JPEG, `fav` picks ICO, `hdr` picks EXR, `iphone` picks HEIC. Formats that don't match fade out, and the grid stays in place.
   - Use the arrow keys or Tab, then press **↩**. **⌘↩** converts and shows the result in Finder. **⌘1…9** picks a format by its position.
4. **Done.** Long jobs such as video show a progress bar with a percentage and a **Cancel** button (Esc also cancels). You can click away and keep working while the chip floats until the job finishes. A check mark shows the new file name. You can drag the result straight out of the chip, or click **Show in Finder** or **Open**. The chip closes by itself after a moment. It stays open while your pointer is over it.

Esc clears what you typed, and a second Esc closes the chip. Clicking anywhere else also closes it, except while a conversion is running.

### Design decisions

- **The chip sits where your attention already is.** It opens next to the pointer you just used for the right-click, so your eyes don't have to move.
- **One fixed footprint.** Searching, converting, success and error states all use the same size, so nothing jumps under the pointer. Search dims the formats that don't match rather than removing them, so each pill stays where your muscle memory expects it.
- **It remembers your last choice.** The most recent format that fits the current file is already selected, so converting another file the same way takes a single **↩**.
- **Extras are offered only when you need them.** The first conversion that needs FFmpeg explains what it is and how big it is, then downloads it and carries on with your conversion. There's no separate setup step.
- **Every pill says what the format is for.** Hovering a pill shows a one-line description in the footer (for example "Apple photos · very small" or "HDR · VFX pipelines"), so you don't need to know every format.
- **Your files are safe.** The original is never touched. Output never overwrites an existing file: it becomes `photo 2.png`, the same way Finder names copies. Files are written to a temporary location first and moved into place when complete.
- **Sensible conversion defaults:**
  - Photos stay upright: EXIF orientation is applied to the pixels.
  - Camera, GPS and copyright metadata are kept where the target format supports them.
  - Transparent areas become white for JPEG and PPM, instead of black.
  - ICO output contains 16–256 px square sizes.
  - Lossy formats are saved at 85% quality.
- **It stays out of the way.** There's no Dock icon and no menu bar item. The app stays loaded for 2 minutes after the chip closes, so back-to-back conversions are instant, and then it quits itself.

## Build & install

You need macOS 13 or later and Xcode 15+ (or the matching Command Line Tools).

```sh
scripts/build-app.sh --install    # builds, signs ad-hoc, copies to ~/Applications, registers with Finder
```

To try it right away, launch ConvertAll once. A welcome window explains the right-click flow and has a drop zone to test with. The **Quick Actions › Convert with ConvertAll** entry can take a moment to appear. If it doesn't, enable it in **System Settings › Keyboard › Keyboard Shortcuts › Services › Files and Folders**.

Development:

```sh
swift build          # debug build
swift test           # codec, search and naming tests (also run on Linux)
python3 scripts/make-icon.py   # regenerate Support/AppIcon.icns (needs Pillow)
```

## Updates

ConvertAll checks [GitHub Releases](https://github.com/gabrielbr/convertall/releases) quietly, at most every 6 hours. When a newer version exists:

- An **Update to x.y.z** pill appears in the chip's footer.
- The welcome window shows an **Update** button. Launch the app directly, or use **⌘ › Check for Updates…**.

Installing an update works like this:

1. ConvertAll downloads the release zip.
2. It checks that the zip contains the same app, at the promised version, with an intact code signature.
3. It swaps itself in place and relaunches.

ConvertAll must be in a folder you can write to, such as `/Applications` or `~/Applications`. If it isn't, it opens the release page instead.

## Releases

Every merge to `main` publishes a GitHub Release (`v<version>`) with a ready-to-run `ConvertAll-<version>.zip`. The version comes from `CFBundleShortVersionString` in `Support/Info.plist`. Bump it with `scripts/bump-version.sh` in each PR; CI rejects versions that are already released.

## Architecture

```
Sources/
  ConvertAllCore/            platform-independent where possible, unit-tested
    FileFormat.swift         catalogue of all 40 formats: category, names, extensions, UTIs, aliases, blurbs
    ConversionMatrix.swift   what converts to what, chip sections, which engine handles each pair
    FFmpeg.swift             FFmpeg argument plans (stream copy first, re-encode fallback), output parsers
    AppVersion.swift         version parsing and comparison for the updater
    FormatSearch.swift       ranking of what the user types ("jp" → JPEG, "song" → MP3)
    OutputNaming.swift       "photo.png", "photo 2.png", "report (PNG)/report 01.png" … never overwrite
    RGBAImage.swift          plain 8-bit RGBA buffer + alpha flattening
    Codecs/QOI|PNM|TGA       pure-Swift encoders/decoders (verified against Pillow)
    Engines/                 macOS only
      Converter.swift        single entry point: route to an engine, report what's missing
      ImageConverter.swift   ImageIO + built-in codecs; WebP/AVIF via cwebp/avifenc or FFmpeg
      MediaEngine.swift      FFmpeg runner with progress; MediaPack = pinned, verified download
      DocumentEngine.swift   DOCX/DOC/ODT/RTF/TXT/HTML/PDF natively; PDF pages → images
      OfficeEngine.swift     LibreOffice (headless) for spreadsheets and presentations
      UpdateInstaller.swift  GitHub Releases check, verified download, in-place swap
      ConversionTask.swift   progress + cancellation, process runner, downloader
  ConvertAll/                the macOS app (AppKit + SwiftUI)
    AppDelegate.swift        accessory app, open-file events, idle quit, Edit menu
    ServiceProvider.swift    Finder Quick Action / Services entry point
    ChipController.swift     floating NSPanel, pointer-relative placement, keyboard, dismissal
    ChipModel.swift          state: sections, search, highlight, engine install, convert → done/failed
    Updater.swift            periodic update check and install
    ChipView.swift           the chip UI
    WelcomeWindow.swift      first-launch guide, drop zone, extras and update status
Support/
  Info.plist                 document types ("Open With"), Services, imported UTIs
  AppIcon.icns
scripts/build-app.sh         SwiftPM → ConvertAll.app bundle
```

## Known limitations

- Animated GIF, WebP and HEIC sources become images from their first frame only. GIF to video keeps the animation.
- Video to a still image keeps one representative frame.
- PDF to DOCX, ODT, RTF and the other text formats keeps the text and basic styling, but not the exact layout.
- There's no settings UI yet. Quality presets are fixed (images at 85%, H.264 at CRF 20, VP9 at CRF 32), and output goes next to the original.
- Top-level placement in Finder's context menu would need a Finder Sync extension. "Open With" and Quick Actions don't need one.
