#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
ROOT="$(cd .. && pwd)"
APP="$ROOT/build/dot-bridge.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/DotBridge"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/server"
cp "$BIN" "$APP/Contents/MacOS/DotBridge"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/server.mjs" "$ROOT/package.json" "$ROOT/package-lock.json" "$APP/Contents/Resources/server/"
(cd "$APP/Contents/Resources/server" && npm ci --omit=dev --silent)

codesign --force --deep --sign - "$APP"
echo "Built $APP"
