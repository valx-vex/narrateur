#!/usr/bin/env bash
# Builds the downloadable archive: build/release/Narrateur-<version>-macos-arm64.zip and its sha256.
# Everything happens inside build/release/. Nothing is installed and no window is opened.
#
# In the repository the public copy is exported from (the one that has scripts/export-public.sh), the
# archive is never made from the working folder. The last commit is exported to build/release/source/,
# this same script is run there, and the app it built is searched once more before the archive is put
# in build/release/. If a committed file, or the app, carries something that must not be published,
# nothing is left in build/release/ but the reason on the screen.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 0 ]]; then echo 'release.sh takes no argument.' >&2; exit 2; fi
# An archive from an earlier run never stands in for this one.
rm -rf build/release/Narrateur.app build/release/check
rm -f build/release/Narrateur-*-macos-arm64.zip build/release/Narrateur-*-macos-arm64.zip.sha256
if [[ -f scripts/export-public.sh ]]; then
  rm -rf build/release/source
  mkdir -p build/release
  if ! scripts/export-public.sh "$PWD/build/release/source"; then echo 'release.sh: the last commit cannot be published as it is. Nothing was built.' >&2; exit 1; fi
  # (Its last three lines name the archive where it is not going to stay: they are said again below.)
  # If it stops (its own check refuses a path of this machine in the app, or the build fails), nothing stays here.
  if ! build/release/source/scripts/release.sh | { grep -v -E '^(Archive|Size|SHA-256): ' || true; }; then
    rm -rf build/release/source
    echo 'release.sh: no archive was made.' >&2; exit 1
  fi
  NAME="$(cd build/release/source/build/release && ls Narrateur-*-macos-arm64.zip)"
  # What a download will hold, searched the way the export searches the sources, short strings of the program included.
  mkdir -p build/release/check
  ditto -x -k "build/release/source/build/release/$NAME" build/release/check
  if ! python3 -B scripts/public_check.py bundle build/release/check/Narrateur.app; then
    # Neither the app searched, nor the sources it was built from, nor what the build left with them.
    rm -rf build/release/check build/release/source
    echo 'release.sh: no archive was made.' >&2; exit 1
  fi
  rm -rf build/release/check
  mv build/release/source/build/release/Narrateur.app "build/release/source/build/release/$NAME" "build/release/source/build/release/$NAME.sha256" build/release/
  # The sources that were built stay in build/release/source/; what the build left there does not.
  rm -rf build/release/source/build build/release/source/.build
  (cd build/release && shasum -a 256 -c "$NAME.sha256" >/dev/null)
  echo "Built from: commit $(git rev-parse --short HEAD), exported to $PWD/build/release/source"
  echo "Archive: $PWD/build/release/$NAME"
  echo "Size:    $(stat -f %z "build/release/$NAME") bytes"
  echo "SHA-256: $(cut -d ' ' -f 1 "build/release/$NAME.sha256")"
  exit 0
fi
# The version is written once, in the bundle's Info.plist.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' assets/Narrateur-Info.plist)"
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' assets/Narrateur-Info.plist)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "release.sh: unexpected version in Narrateur-Info.plist: $VERSION" >&2; exit 1; fi
NAME="Narrateur-$VERSION-macos-arm64.zip"
scripts/build-app.sh --output build/release
APP="build/release/Narrateur.app"
BINARY="$APP/Contents/MacOS/Narrateur"
fail() { echo "release.sh: $1" >&2; exit 1; }
[[ "$(lipo -archs "$BINARY")" == "arm64" ]] || fail "the app must be built on an Apple Silicon Mac (found: $(lipo -archs "$BINARY"))."
BUILT_FOR="$(vtool -show-build "$BINARY" | awk '$1 == "minos" { print $2 }')"
[[ "$BUILT_FOR" == "$MINIMUM" ]] || fail "the app is built for macOS $BUILT_FOR, but its Info.plist says $MINIMUM."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] || fail 'the bundle does not carry the version.'
for file in LICENSE THIRD_PARTY.md AppIcon.icns Fonts/SpaceGrotesk.ttf Fonts/SpaceGrotesk-OFL.txt Fonts/JetBrainsMono.ttf Fonts/JetBrainsMono-OFL.txt; do
  [[ -s "$APP/Contents/Resources/$file" ]] || fail "missing in the bundle: $file"
done
# What goes out must not name the machine or the folder it was built in.
if grep -r -l -a -F -e "$HOME" -e "$PWD" "$APP" >/dev/null; then
  grep -r -l -a -F -e "$HOME" -e "$PWD" "$APP" >&2 || true
  fail 'the app still carries a path of this machine (files listed above).'
fi
# No extended attributes or resource forks in the archive: only the bundle itself.
ditto -c -k --norsrc --keepParent "$APP" "build/release/$NAME"
# Open the archive again and check what a download will hold.
mkdir -p build/release/check
ditto -x -k "build/release/$NAME" build/release/check
codesign --verify --deep --strict build/release/check/Narrateur.app
diff -r "$APP" build/release/check/Narrateur.app >/dev/null || fail 'the archive does not hold the same app.'
rm -rf build/release/check
(cd build/release && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "Archive: $PWD/build/release/$NAME"
echo "Size:    $(stat -f %z "build/release/$NAME") bytes"
echo "SHA-256: $(cut -d ' ' -f 1 "build/release/$NAME.sha256")"
