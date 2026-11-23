#!/bin/bash
# Builds Ferro.app (ad-hoc signed) into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Ferro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ferro "$APP/Contents/MacOS/Ferro"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
