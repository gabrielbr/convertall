#!/usr/bin/env bash
# Bumps CFBundleShortVersionString in Support/Info.plist.
#   scripts/bump-version.sh            # 0.1.3 → 0.1.4
#   scripts/bump-version.sh minor      # 0.1.3 → 0.2.0
#   scripts/bump-version.sh major      # 0.1.3 → 1.0.0
#   scripts/bump-version.sh 2.0.0      # explicit
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=Support/Info.plist
CURRENT=$(python3 -c "import plistlib; print(plistlib.load(open('$PLIST','rb'))['CFBundleShortVersionString'])")
IFS=. read -r MA MI PA <<<"$CURRENT"
case "${1:-patch}" in
  patch) NEXT="$MA.$MI.$((PA + 1))" ;;
  minor) NEXT="$MA.$((MI + 1)).0" ;;
  major) NEXT="$((MA + 1)).0.0" ;;
  *) NEXT="$1" ;;
esac
python3 - "$PLIST" "$NEXT" <<'PY'
import re, sys
path, version = sys.argv[1], sys.argv[2]
s = open(path).read()
s = re.sub(r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)", rf"\g<1>{version}\g<2>", s)
open(path, "w").write(s)
PY
echo "$CURRENT → $NEXT"
