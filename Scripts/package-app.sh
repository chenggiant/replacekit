#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product ReplaceKit

APP="$PWD/outputs/ReplaceKit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ReplaceKit" "$APP/Contents/MacOS/ReplaceKit"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
SIGN_IDENTITY="${REPLACEKIT_CODESIGN_IDENTITY:--}"
VALID_IDENTITIES="$(security find-identity -v -p codesigning)"
if [[ "$SIGN_IDENTITY" != "-" ]] && ! grep -Fq "\"$SIGN_IDENTITY\"" <<< "$VALID_IDENTITIES"; then
  SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
if [[ "$SIGN_IDENTITY" != "-" ]] && ! codesign --verify --deep "$APP" >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP"
fi
printf '%s\n' "$APP"
