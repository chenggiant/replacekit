#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product ReplaceKit

APP="$PWD/outputs/ReplaceKit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ReplaceKit" "$APP/Contents/MacOS/ReplaceKit"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
SIGN_IDENTITY="${REPLACEKIT_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]] && security find-identity -v -p codesigning | grep -Fq '"ReplaceKit Local Code Signing"'; then
  SIGN_IDENTITY="ReplaceKit Local Code Signing"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
printf '%s\n' "$APP"
