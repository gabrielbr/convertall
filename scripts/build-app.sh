#!/usr/bin/env bash
# Builds ConvertAll.app.
#
#   scripts/build-app.sh             # build/ConvertAll.app (ad-hoc signed)
#   scripts/build-app.sh --install   # …and copy to ~/Applications, register with Finder
#
# With XcodeGen installed (brew install xcodegen) the app is built through Xcode, which
# also produces the Shortcuts actions (App Intents metadata) and app extensions.
# Without it, a plain SwiftPM build is assembled (everything except those).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/ConvertAll.app"
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true
rm -rf "$APP"
mkdir -p build

if command -v xcodegen >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  echo "› Generating Xcode project…"
  xcodegen generate --quiet
  echo "› Building with Xcode (universal)…"
  xcodebuild -project ConvertAll.xcodeproj -scheme ConvertAll -configuration Release \
    -derivedDataPath build/DerivedData \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    ${BUILD_NUMBER:+CURRENT_PROJECT_VERSION=$BUILD_NUMBER} \
    -quiet build
  cp -R build/DerivedData/Build/Products/Release/ConvertAll.app "$APP"
  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
  fi
else
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  # Universal builds need full Xcode; fall back to the host architecture otherwise.
  if ! xcodebuild -version >/dev/null 2>&1; then ARCH_FLAGS=(); fi

  echo "› Building release binaries with SwiftPM…"
  swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
  BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

  echo "› Assembling $APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BIN_DIR/ConvertAll" "$APP/Contents/MacOS/ConvertAll"
  cp "$BIN_DIR/convertall" "$APP/Contents/MacOS/convertall"
  cp Support/Info.plist "$APP/Contents/Info.plist"
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  printf 'APPL????' > "$APP/Contents/PkgInfo"
  # CI stamps a monotonically increasing build number (CFBundleVersion).
  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
  fi
fi

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
echo "  Right-click any file in Finder → Open With → ConvertAll"
