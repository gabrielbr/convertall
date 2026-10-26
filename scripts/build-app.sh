#!/usr/bin/env bash
# Builds ConvertAll.app from the Swift package — no Xcode project needed.
#
#   scripts/build-app.sh             # build/ConvertAll.app (universal, ad-hoc signed)
#   scripts/build-app.sh --install   # …and copy to ~/Applications, register with Finder
#
# Requires Xcode command-line tools (Swift 5.9+) on macOS 13 or later.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/ConvertAll.app"
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

ARCH_FLAGS=(--arch arm64 --arch x86_64)
# Universal builds need full Xcode; fall back to the host architecture otherwise.
if ! xcrun --find xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  ARCH_FLAGS=()
fi

echo "› Building release binary…"
swift build -c release --product ConvertAll ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --product ConvertAll ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ConvertAll" "$APP/Contents/MacOS/ConvertAll"
cp Support/Info.plist "$APP/Contents/Info.plist"
# CI stamps a monotonically increasing build number (CFBundleVersion).
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

if $INSTALL; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  rm -rf "$DEST/ConvertAll.app"
  cp -R "$APP" "$DEST/"
  APP="$DEST/ConvertAll.app"
  echo "› Installed to $APP"
fi

# Make "Open With" and the Quick Action show up immediately.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$APP" || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo "✓ Done: $APP"
echo "  Right-click any image in Finder → Open With → ConvertAll"
