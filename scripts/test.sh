#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
swift test --disable-sandbox --disable-xctest --enable-swift-testing \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_DIR/Library/Developer/usr/lib" "$@"
