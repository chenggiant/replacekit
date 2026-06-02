#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product ReplaceKit

APP="$PWD/outputs/ReplaceKit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ReplaceKit" "$APP/Contents/MacOS/ReplaceKit"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
