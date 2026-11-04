#!/usr/bin/env bash
# End-to-end smoke test on a real Mac: runs actual conversions through the bundled
# `convertall` CLI (the same engines the chip uses) and checks every output exists.
#
#   scripts/smoke-test.sh [path/to/ConvertAll.app]
#
# Downloads the media engine (~30 MB) on first run. Exits non-zero if anything fails.
set -uo pipefail

APP="${1:-build/ConvertAll.app}"
CLI="$APP/Contents/Helpers/convertall"
[[ -x "$CLI" ]] || { echo "no CLI at $CLI" >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
PASS=0; FAIL=0; FAILED=()

# check <description> <expected-suffix> -- <convertall args...>
check() {
  local desc="$1" want="$2"; shift 3
  local out status
  out="$("$CLI" "$@" 2>err.txt)"; status=$?
  local last; last="$(printf '%s\n' "$out" | tail -1)"
  if [[ $status -eq 0 && -n "$last" && -e "$last" && "$last" == *"$want" ]] && [[ -s "$last" || -d "$last" ]]; then
    PASS=$((PASS + 1)); printf '  ✓ %-38s → %s\n' "$desc" "$(basename "$last")"
  else
    FAIL=$((FAIL + 1)); FAILED+=("$desc"); printf '  ✗ %-38s (exit %s) %s\n' "$desc" "$status" "$(tr '\n' ' ' < err.txt)"
  fi
  LAST="$last"
}

echo "› Fixtures"
mkdir -p img doc av out
sips -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns --out img/icon.png >/dev/null
sips -s format jpeg img/icon.png --out img/photo.jpg >/dev/null
sips -s format psd img/icon.png --out img/layers.psd >/dev/null 2>&1 || true
printf 'ConvertAll smoke test\n\nThe quick brown fox jumps over the lazy dog.\n' > doc/notes.txt
printf '# Release notes\n\nSome **bold** text and a [link](https://example.com).\n\n- one\n- two\n' > doc/readme.md
printf '<!DOCTYPE html><html><body><h1>Hello</h1><p>From HTML.</p></body></html>' > doc/page.html
python3 - <<'PY'
import math, struct, wave
with wave.open("av/tone.wav", "w") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
    w.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * 440 * i / 44100))) for i in range(44100 * 2)))
PY
# A minimal EPUB: mimetype (stored, first), container.xml, package, one chapter.
mkdir -p epub/META-INF epub/OEBPS
printf 'application/epub+zip' > epub/mimetype
cat > epub/META-INF/container.xml <<'XML'
<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
XML
cat > epub/OEBPS/book.opf <<'XML'
<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/><manifest><item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>
XML
printf '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Chapter One</h1><p>Once upon a time.</p></body></html>' > epub/OEBPS/ch1.xhtml
(cd epub && zip -q -X -0 ../doc/book.epub mimetype && zip -q -X -r ../doc/book.epub META-INF OEBPS)

echo "› Images"
for f in png heic tiff gif bmp ico tga qoi pnm exr; do
  ext="$f"; [[ $f == pnm ]] && ext=ppm
  check "JPEG → $(printf '%s' "$f" | tr a-z A-Z)" ".$ext" -- img/photo.jpg --to "$f"
done
check "PNG → JPEG (flatten alpha)" ".jpg" -- img/icon.png --to jpeg
check "Smaller JPEG" ".jpg" -- img/photo.jpg --smaller --quality smaller
check "Resize 50%" ".png" -- img/icon.png --to png --size 50% --out out
check "Fit under 20 KB" ".jpg" -- img/icon.png --to jpeg --size 20KB --out out
check "QOI → PNG (built-in codec)" ".png" -- img/photo.qoi --to png --out out
[[ -f img/layers.psd ]] && check "PSD → PNG" ".png" -- img/layers.psd --to png --out out
check "Images → one PDF" ".pdf" -- img/icon.png img/photo.jpg --combine pdf

echo "› Documents"
check "TXT → DOCX" ".docx" -- doc/notes.txt --to docx
check "DOCX → PDF" ".pdf" -- doc/notes.docx --to pdf
check "PDF → PNG pages" ".png" -- doc/notes.pdf --to png
check "PDF → TXT" ".txt" -- doc/notes.pdf --to txt --out out
check "OCR on rendered page" ".txt" -- doc/notes.png --text
grep -qi "quick brown fox" doc/notes.txt && grep -qi "fox" "$LAST" \
  && { PASS=$((PASS + 1)); echo "  ✓ OCR read the words back"; } \
  || { FAIL=$((FAIL + 1)); FAILED+=("OCR accuracy"); echo "  ✗ OCR text: $(head -c 200 "$LAST" 2>/dev/null)"; }
check "Markdown → DOCX" ".docx" -- doc/readme.md --to docx
check "Markdown → HTML" ".html" -- doc/readme.md --to html
check "HTML → RTF" ".rtf" -- doc/page.html --to rtf
check "EPUB → TXT" ".txt" -- doc/book.epub --to txt
grep -q "Once upon a time" "$LAST" && { PASS=$((PASS + 1)); echo "  ✓ EPUB chapter text present"; } \
  || { FAIL=$((FAIL + 1)); FAILED+=("EPUB text"); echo "  ✗ EPUB text missing"; }

echo "› Media (installs the media engine)"
check "WAV → MP3 (+ engine install)" ".mp3" -- av/tone.wav --to mp3 --install-engine
FFMPEG="$HOME/Library/Application Support/ConvertAll/Engines/ffmpeg-9.0.2/ffmpeg"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i testsrc=duration=3:size=640x360:rate=24 \
  -f lavfi -i sine=duration=3 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest av/clip.mov
cp av/clip.mov av/clip2.mov
check "WAV → M4A / FLAC / OGG / Opus" ".m4a" -- av/tone.wav --to m4a
check "  → FLAC" ".flac" -- av/tone.wav --to flac
check "  → OGG" ".ogg" -- av/tone.wav --to ogg
check "  → Opus" ".opus" -- av/tone.wav --to opus
check "MOV → MP4 (stream copy)" ".mp4" -- av/clip.mov --to mp4
check "MOV → WebM (VP9)" ".webm" -- av/clip.mov --to webm --out out
check "MOV → GIF" ".gif" -- av/clip.mov --to gif
check "MOV → MP3 (soundtrack)" ".mp3" -- av/clip.mov --to mp3 --out out
check "MOV → JPEG (frame)" ".jpg" -- av/clip.mov --to jpeg
check "Smaller MOV (HEVC)" ".mov" -- av/clip.mov --smaller --out out
check "Trim 1–2 s" ".mp4" -- av/clip2.mov --to mp4 --trim 1-2 --out out
check "Join two clips" ".mp4" -- av/clip.mov av/clip2.mov --combine mp4
check "GIF → MP4" ".mp4" -- av/clip.gif --to mp4 --out out
check "JPEG → WebP (via engine)" ".webp" -- img/photo.jpg --to webp
check "JPEG → AVIF (via engine)" ".avif" -- img/photo.jpg --to avif

echo
echo "Smoke test: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then printf '  failed: %s\n' "${FAILED[@]}"; exit 1; fi
