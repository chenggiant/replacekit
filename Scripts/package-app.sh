#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product ReplaceKit

APP="$PWD/outputs/ReplaceKit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ReplaceKit" "$APP/Contents/MacOS/ReplaceKit"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/ReplaceKit.icns" "$APP/Contents/Resources/ReplaceKit.icns"
SIGN_IDENTITY="${REPLACEKIT_CODESIGN_IDENTITY:-}"
VALID_IDENTITIES="$(security find-identity -v -p codesigning)"
if [[ -z "$SIGN_IDENTITY" ]] && grep -Fq '"ReplaceKit Local Code Signing"' <<< "$VALID_IDENTITIES"; then
  SIGN_IDENTITY="ReplaceKit Local Code Signing"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi
if [[ "$SIGN_IDENTITY" != "-" ]] && ! grep -Fq "\"$SIGN_IDENTITY\"" <<< "$VALID_IDENTITIES"; then
  SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
if [[ "$SIGN_IDENTITY" != "-" ]] && ! codesign --verify --deep "$APP" >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP"
fi
printf '%s\n' "$APP"
