# ConvertAll

Convert any file to another format, right from Finder. Right-click → **Open With › ConvertAll**, and a small chip appears next to your pointer. Type or click a format, and the new file is saved next to the original.

This MVP covers **images**, using the image list from [convt.app/formats](https://convt.app/formats):

| Read | Write |
| --- | --- |
| JPEG, PNG, WebP, HEIC/HEIF, AVIF, GIF, TIFF, BMP, ICO, TGA, PPM/PGM/PBM/PNM, QOI, OpenEXR, SVG | PNG, JPEG, WebP\*, HEIC, AVIF\*, GIF, TIFF, ICO, BMP, TGA, EXR, QOI, PPM |

\* macOS can read WebP and AVIF but can't write them. ConvertAll uses the Homebrew encoders when they're installed (`brew install webp libavif`). Until then those pills appear dimmed, with a hint that says what to install.

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

1. **Right-click an image (or several)** in Finder, then choose **Open With › ConvertAll**, or **Quick Actions › Convert with ConvertAll**.
2. **The chip opens beside the pointer**, like a context menu. Near a screen edge it opens on the other side.
3. **Pick a format** in any of these ways:
   - Click a pill.
   - Start typing. `p` picks PNG, `jp` or `.jpg` picks JPEG, `fav` picks ICO, `hdr` picks EXR, `iphone` picks HEIC. Formats that don't match fade out, and the grid stays in place.
   - Use the arrow keys or Tab, then press **↩**. **⌘↩** converts and shows the result in Finder. **⌘1…9** picks a format by its position.
4. **Done.** A check mark shows the new file name. You can drag the result straight out of the chip, or click **Show in Finder** or **Open**. The chip closes by itself after a moment. It stays open while your pointer is over it.

Esc clears what you typed, and a second Esc closes the chip. Clicking anywhere else also closes it, except while a conversion is running.

### Design decisions

- **The chip sits where your attention already is.** It opens next to the pointer you just used for the right-click, so your eyes don't have to move.
- **One fixed footprint.** Searching, converting, success and error states all use the same size, so nothing jumps under the pointer. Search dims the formats that don't match rather than removing them, so each pill stays where your muscle memory expects it.
- **It remembers your last choices.** The last three target formats come first, and the most recent one is already selected. Converting another image the same way takes a single **↩**.
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

## Architecture

```
Sources/
  ConvertAllCore/            platform-independent where possible, unit-tested
    ImageFormat.swift        format catalogue: names, extensions, UTIs, aliases, blurbs
    FormatSearch.swift       ranking of what the user types ("jp" → JPEG)
    OutputNaming.swift       "photo.png", "photo 2.png", … never overwrite
    RGBAImage.swift          plain 8-bit RGBA buffer + alpha flattening
    Codecs/QOI|PNM|TGA       pure-Swift encoders/decoders (verified against Pillow)
    ImageConverter.swift     decode (ImageIO, built-in codecs, AppKit for SVG) →
                             encode (built-in, ImageIO, or Homebrew cwebp/avifenc)
  ConvertAll/                the macOS app (AppKit + SwiftUI)
    AppDelegate.swift        accessory app, open-file events, idle quit, Edit menu
    ServiceProvider.swift    Finder Quick Action / Services entry point
    ChipController.swift     floating NSPanel, pointer-relative placement, keyboard, dismissal
    ChipModel.swift          state: formats, search, highlight, convert → done/failed
    ChipView.swift           the chip UI
    WelcomeWindow.swift      first-launch guide and drop zone
Support/
  Info.plist                 document types ("Open With"), Services, imported UTIs
  AppIcon.icns
scripts/build-app.sh         SwiftPM → ConvertAll.app bundle
```

To add a new category (video, audio, documents), add a format catalogue for it, add a converter (ffmpeg, PDFKit and so on), and extend the document types in `Info.plist`. The chip itself works with any list of formats.

## Known limitations (MVP)

- Animated GIF, WebP and HEIC sources are converted from the first frame only.
- High-bit-depth input (16-bit PNG/TIFF, EXR) is converted at 8 bits per channel when the target is a built-in codec (QOI, PPM, TGA).
- There's no settings UI yet. Quality is fixed at 85%, and output goes next to the original.
- Top-level Finder context-menu placement would need a Finder Sync extension. "Open With" and Quick Actions don't need one.
