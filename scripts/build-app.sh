#!/usr/bin/env bash
# Builds Narrateur.app.
#   scripts/build-app.sh                 redraws the icon, builds build/Narrateur.app and installs it in ~/Applications
#                                        (an earlier installation is kept in build/previous/).
#   scripts/build-app.sh --output DIR    builds DIR/Narrateur.app from the files as they are and installs nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ $# -lt 2 || -z "$2" ]]; then echo 'build-app.sh: --output needs a folder.' >&2; exit 2; fi
      OUTPUT="$2"; shift 2 ;;
    *) echo "build-app.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done
source scripts/swift-env.sh
swift build -c release --disable-sandbox
if [[ -z "$OUTPUT" ]]; then
  mkdir -p build/AppIcon.iconset
  swift scripts/draw-icon.swift assets/AppIcon.png
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  if ! iconutil -c icns build/AppIcon.iconset -o assets/AppIcon.icns; then
    echo 'iconutil failed; using the lossless PNG ICNS container fallback.' >&2
    python3 scripts/package-icon.py build/AppIcon.iconset assets/AppIcon.icns
  fi
  APP="$PWD/build/Narrateur.app"
else
  mkdir -p "$OUTPUT"
  APP="$(cd "$OUTPUT" && pwd)/Narrateur.app"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp .build/release/Narrateur "$APP/Contents/MacOS/Narrateur"
# A build handed to someone else carries no debugging symbols, and so no path of the machine that built it.
if [[ -n "$OUTPUT" ]]; then strip -S "$APP/Contents/MacOS/Narrateur"; fi
cp assets/Narrateur-Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/"
cp assets/Fonts/*.ttf assets/Fonts/*OFL.txt "$APP/Contents/Resources/Fonts/"
cp LICENSE THIRD_PARTY.md "$APP/Contents/Resources/"
chmod +x "$APP/Contents/MacOS/Narrateur"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -n "$OUTPUT" ]]; then echo "Built $APP"; exit 0; fi
INSTALL="$HOME/Applications/Narrateur.app"
if [[ -L "$INSTALL" ]]; then echo 'Refusing to replace a symlink at the install path.' >&2; exit 1; fi
mkdir -p "$HOME/Applications"
if [[ -e "$INSTALL" ]]; then
  mkdir -p build/previous
  mv "$INSTALL" "build/previous/Narrateur-$(date -u +%Y%m%dT%H%M%SZ).app"
fi
ditto "$APP" "$INSTALL"
codesign --verify --deep --strict --verbose=2 "$INSTALL"
echo "Installed $INSTALL"
