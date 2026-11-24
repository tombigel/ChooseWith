#!/bin/zsh
# Build OpenWithPopup.app and install it to ~/Applications.
set -euo pipefail
cd "${0:A:h}"

APP=build/OpenWithPopup.app
DEST="$HOME/Applications/OpenWithPopup.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/OpenWithPopup" Sources/*.swift
codesign --force --sign - "$APP"

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

echo "Installed $DEST"
echo "Open it from ~/Applications (or: open \"$DEST\") to add extensions in Settings."
