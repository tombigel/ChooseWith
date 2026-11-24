#!/bin/zsh
# Build OpenWithPopup.app and install it to ~/Applications.
#
# Signing: uses your "Developer ID Application" certificate if one is in the
# keychain (or SIGN_ID="Developer ID Application: Name (TEAMID)"), otherwise signs
# ad hoc, which only runs on this Mac.
#
# Release: NOTARIZE=1 ./build.sh  also notarizes with Apple, staples the ticket and
# writes dist/OpenWithPopup.zip. Needs a notarytool keychain profile, created once with:
#   xcrun notarytool store-credentials OpenWithPopup --apple-id you@example.com --team-id TEAMID
# (override the profile name with NOTARY_PROFILE=...).
set -euo pipefail
cd "${0:A:h}"

APP=build/OpenWithPopup.app
DEST="$HOME/Applications/OpenWithPopup.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-OpenWithPopup}"

if [[ -z "${SIGN_ID:-}" ]]; then
  SIGN_ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] || swift tools/make_icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -swift-version 5 -target arm64-apple-macos13 -o build/owp-arm64 Sources/*.swift
swiftc -O -swift-version 5 -target x86_64-apple-macos13 -o build/owp-x86_64 Sources/*.swift
lipo -create build/owp-arm64 build/owp-x86_64 -output "$APP/Contents/MacOS/OpenWithPopup"

if [[ -n "$SIGN_ID" ]]; then
  echo "Signing with: $SIGN_ID"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "No Developer ID certificate found; signing ad hoc (runs on this Mac only)."
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

if [[ "${NOTARIZE:-0}" == 1 ]]; then
  [[ -n "$SIGN_ID" ]] || { echo "Notarizing needs a Developer ID certificate."; exit 1; }
  mkdir -p dist
  ditto -c -k --keepParent "$APP" build/notarize.zip
  xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
  ditto -c -k --keepParent "$APP" dist/OpenWithPopup.zip
  echo "Release: dist/OpenWithPopup.zip"
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

echo "Installed $DEST"
echo "Open it from ~/Applications (or: open \"$DEST\") to add extensions in Settings."
