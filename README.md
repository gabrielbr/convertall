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
- **Document pack.** This is LibreOffice (about 300 MB), needed for spreadsheets and presentations. It's a one-click download from the chip, pinned to a specific version and verified by SHA-256. If you already have LibreOffice installed, ConvertAll uses it instead.

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

### Make it smaller, and the options strip

- **Make smaller.** JPEG, PNG, HEIC, WebP, AVIF, GIF, MP4, MOV, WebM, MKV, MP3, M4A, AAC, OGG, Opus and PDF files get a **Smaller** pill. It re-encodes the file in its own format:
  - **Videos** become HEVC, about half the size of H.264.
  - **PNGs** are reduced to an 8-bit palette with transparency kept, like TinyPNG. This needs the media engine. Without it, PNGs get a plain re-encode.
  - **PDFs** get their images recompressed.

  The success message shows the saving (for example `2.4 MB → 680 KB (−72%)`). If the result wouldn't be smaller, nothing is saved.
- **Options strip.** Three compact controls sit under the grid. Your choices are remembered, and **Reset** puts them back:
  - **Quality:** Smaller, Balanced or Best. Applies to image quality, H.264/HEVC/VP9 quality, and audio bitrate.
  - **Size:** 50%, a maximum of 3840, 1920, 1280 or 640 px, or **Under 500 KB, 1, 2, 5, 10 or 25 MB**.
    - For images, ConvertAll lowers the quality first and then the dimensions until the file fits.
    - For video and audio, it calculates a bitrate from the clip's length.
  - **No metadata:** removes location, camera and author details.
- **Hardware video encoding.** Video is encoded with Apple's VideoToolbox, which is several times faster and much lighter on the battery. If that fails, ConvertAll falls back to the x264 software encoder.
- **Notifications.** When a long conversion finishes while you're in another app, you get a notification with a **Show in Finder** button.

### Folders, batches, combining, trimming

- **Folders.** Right-click a folder and choose **Open With › ConvertAll** (or use the Quick Action). Every convertible file inside is converted, including subfolders. Hidden files and app bundles are skipped. If the files are of mixed kinds, the chip offers every format any of them can become, and files that can't become the chosen format are skipped and counted.
- **Parallel batches.** Several files convert at once:
  - Images and documents run in parallel up to half your CPU cores, with a maximum of 8.
  - Video runs 1–3 at a time, because FFmpeg is already multi-threaded.
  - LibreOffice runs one at a time.

  The progress bar combines the progress of every file.
- **Combine.** A **Combine** section appears when it makes sense:
  - **One PDF** from images and PDFs, in selection order. Image pages are A4 or Letter (depending on your region), turned to match the image's orientation.
  - **Join MP4** puts clips back to back. They're fitted to the first clip's frame, and clips without sound get silence.
  - **Join MP3 / M4A** for audio.

  A single image also gets a **PDF** pill. The result is saved as `name (combined).ext`.
- **Trim.** For a single video or audio file, **Trim** in the options strip opens a two-handle range slider. The chosen range applies to the next conversion or **Smaller**.
- **Animation kept.**
  - Animated GIF, WebP, APNG and HEICS files stay animated as GIF or APNG (frame delays are kept), and as WebP or AVIF through the media engine.
  - An animated WebP or PNG can also become a video, like a GIF.

### Smart actions (on-device)

Both run on your Mac with Apple's Vision framework. Nothing is uploaded and nothing extra is downloaded.

- **Text (OCR).** Images get a **Text** pill that recognises the text in photos, screenshots and scans and saves it as `.txt`, with the language detected automatically. PDFs without a text layer (scans) fall back to OCR on their own when you convert them to TXT, DOCX, RTF and the other text formats.
- **Cutout.** Still images get a **Cutout** pill that keeps the main subject on a transparent background. The result is saved as `name (no background).png`, or in the same format if that format supports transparency (WebP, HEIC, TIFF). It needs macOS 14 or later.

### Shortcuts, command line, clipboard, watched folders, rename-to-convert

Open **Settings** with ⌘, from the welcome window or the menu bar icon. Everything here is off until you turn it on.

- **Shortcuts.** The Shortcuts app gets these actions: **Convert Files**, **Make Files Smaller**, **Combine Files**, **Extract Text (OCR)** and **Remove Background**. Each one returns the new files (or the text), so actions can be chained.
- **Command line.** `convertall` is bundled inside the app, and **Settings › Install…** links it into `/usr/local/bin`. Converted paths are printed one per line, and errors go to stderr. Examples:

  ```sh
  convertall *.heic --to jpeg --size 1920
  convertall clip.mov --smaller --quality smaller
  convertall scans/ --combine pdf
  convertall talk.mp4 --to mp3 --trim 1:30-12:00 --install-engine
  convertall screenshot.png --text
  ```

  It also works with Raycast and Alfred, and from Shortcuts' "Run Shell Script" action.
- **Menu bar.** An optional icon with **Convert Files…**, **Convert Clipboard**, **Settings…** and **Check for Updates…**. Open at login is available too (built on macOS 13's login item support).
- **Clipboard (⌥⌘V).** Copy an image or some files, press ⌥⌘V, and pick a format. The result goes onto the clipboard, ready to paste: as a picture for a single image, and as file references for anything else.
- **Watched folders.** Add a folder and choose **Make smaller** or a target format, plus a quality. New files dropped into it are converted into its `Converted/` subfolder, and you get a notification for each one.
- **Rename to convert.** In the folders you choose (Desktop and Downloads by default), rename `photo.jpg` to `photo.png` in Finder and ConvertAll really converts it. A content sniffer that reads the file's bytes catches the mismatch between the name and what's inside. The untouched original goes to the Trash.

### Finder menu and the document pack

- **ConvertAll in Finder's right-click menu.** A Finder extension adds a **ConvertAll ▸** submenu with presets that fit the selection:
  - Images: Make Smaller, → PNG, JPEG, HEIC or WebP, → PDF (or **Combine into One PDF**), Extract Text, Remove Background.
  - Video: Make Smaller, → MP4, → GIF, → MP3, Join into One MP4.
  - Audio: Make Smaller, → MP3, M4A or WAV.
  - PDF: Make Smaller, → DOCX, → PNG pages, → Text.
  - Office documents: → PDF, → PNG pages.

  **Convert…** opens the chip. A preset starts converting right away, with the chip showing progress next to the pointer.
  - To turn it on, go to **Settings › Finder › Turn On…** and enable "ConvertAll Finder Menu".
  - How it works: the extension is sandboxed, so it only builds the menu. It passes your choice to the app through a `convertall://` link, and the app does the work.
- **Document pack.** Spreadsheets and presentations no longer need a separate LibreOffice install.
  - The chip offers **Download & Continue**. It fetches The Document Foundation's official LibreOffice 26.8.1 build (about 300 MB, once), checks the published SHA-256, and unpacks it into `~/Library/Application Support/ConvertAll`.
  - If you've already installed LibreOffice yourself, ConvertAll uses that instead.
  - On the command line, `convertall --install-engine` downloads whichever engine is missing.

### Arcade mode (90s fighting-game skin)

Turn it on in **Settings › Arcade**, or type **↑↑↓↓←→←→BA** in the chip.

- **CONVERTLY!** is slammed into the middle of the screen in chunky metallic letters, with a shake and an announcer voice, when a conversion finishes.
- **Corner pop-in.** When several files or a folder finish, a character peeks in from the bottom-right corner and plays its sound.
- **Extras.**
  - **ROUND n · FIGHT!** when a batch starts.
  - A **HIT COMBO** counter as files finish.
  - **FLAWLESS VICTORY** when nothing fails, **PERFECT!** when a file shrinks by 70% or more, and **K.O.** when everything fails.
- **HI-SCORE:** the total megabytes you've ever saved.
- **Your own picture and sound.** Settings › Arcade › *Choose…* copies them into `~/Library/Application Support/ConvertAll/Arcade`. They stay on your Mac and are never bundled or published. Without them you get an original pixel mascot and a synthesized "Converty!".
- **Embedding your own picture and sound** (in builds you make yourself):
  1. Put `popin.png` (or another image) and `sound.mp3` (or another audio file) in `Support/Personal/`.
  2. Run `scripts/build-app.sh --install`.

  The files are embedded in that build only. `Support/Personal/` is git-ignored, so they're never committed or published. On first launch they become your pop-in, and they stay after app updates. Updates replace the app with the public build, but your files have already been copied into Application Support.
- **Reduce Motion.** If Reduce Motion is on in macOS, the effects fade in and out instead of moving.
- **Font.** The arcade font is [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P), under the SIL Open Font License. Its license is in `Support/Fonts/OFL.txt`.

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

With [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (`brew install xcodegen`), the build script builds through Xcode. Xcode is needed for the Shortcuts actions, because it generates their App Intents metadata. Without XcodeGen, a plain SwiftPM build produces everything except the Shortcuts actions.


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
    ConversionOptions.swift  quality / size / metadata options and the encoder settings they map to
    FFmpeg.swift             FFmpeg argument plans (stream copy first, re-encode fallback), output parsers
    AppVersion.swift         version parsing and comparison for the updater
    FormatSearch.swift       ranking of what the user types ("jp" → JPEG, "song" → MP3)
    FolderScanner.swift      folders → the convertible files inside
    FileSniffer.swift        identify files by their bytes (rename-to-convert, misnamed files)
    OutputNaming.swift       "photo.png", "photo 2.png", "report (PNG)/report 01.png" … never overwrite
    RGBAImage.swift          plain 8-bit RGBA buffer + alpha flattening
    Codecs/QOI|PNM|TGA       pure-Swift encoders/decoders (verified against Pillow)
    Engines/                 macOS only
      Converter.swift        single entry point: route to an engine, report what's missing
      ImageConverter.swift   ImageIO + built-in codecs; WebP/AVIF via cwebp/avifenc or FFmpeg
      MediaEngine.swift      FFmpeg runner with progress; MediaPack = pinned, verified download
      DocumentEngine.swift   DOCX/DOC/ODT/RTF/TXT/HTML/PDF natively; PDF pages → images
      OfficeEngine.swift     LibreOffice (headless) for spreadsheets and presentations
      OfficePack.swift       one-click LibreOffice download (pinned, SHA-256 verified)
      Combiner.swift         many files → one PDF / MP4 / MP3 / M4A
      VisionEngine.swift     OCR (images, scanned PDFs) and background removal
      UpdateInstaller.swift  GitHub Releases check, verified download, in-place swap
      ConversionTask.swift   progress + cancellation, process runner, downloader
  ConvertAll/                the macOS app (AppKit + SwiftUI)
    AppDelegate.swift        accessory app, open-file events, idle quit, Edit menu
    ServiceProvider.swift    Finder Quick Action / Services entry point
    ChipController.swift     floating NSPanel, pointer-relative placement, keyboard, dismissal
    ChipAction.swift         a pill: convert to a format, make smaller, or combine
    ChipModel.swift          state: sections, search, highlight, trim, engine install, parallel run → done/failed
    Updater.swift            periodic update check and install
    Notifier.swift           "done" notifications with Show in Finder
    Intents.swift            Shortcuts actions (App Intents)
    AppSettings.swift        settings, open at login, command-line install
    SettingsWindow.swift     the Settings window
    BackgroundServices.swift menu bar, clipboard hotkey, watched folders, rename-to-convert
    HotKey.swift             system-wide ⌥⌘V
    FolderWatcher.swift      FSEvents wrapper
    Arcade/                  arcade mode: ArcadeDirector (events, sound), ArcadeOverlay (the stage)
  ConvertAllCLI/             the `convertall` command-line tool
Extensions/FinderSync/       Finder right-click menu extension (FinderMenu.appex)
    ChipView.swift           the chip UI
    WelcomeWindow.swift      first-launch guide, drop zone, extras and update status
Support/
  Info.plist                 document types ("Open With"), Services, imported UTIs
  AppIcon.icns
project.yml                  XcodeGen spec (app + CLI) for release builds
scripts/build-app.sh         Xcode (via XcodeGen) or SwiftPM → ConvertAll.app bundle
```

## Known limitations

- Animated sources keep their animation only when the target can hold it (GIF, APNG, WebP, AVIF, video). Other targets get the first frame.
- Video to a still image keeps one representative frame.
- PDF to DOCX, ODT, RTF and the other text formats keeps the text and basic styling, but not the exact layout. Scanned PDFs are read with OCR, which gives plain text only.
- There's no settings UI yet. Output always goes next to the original.
- The Finder menu's presets are fixed; customising them is planned.
