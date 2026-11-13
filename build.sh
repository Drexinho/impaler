#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build -c release

APP=Impaler.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Impaler" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp AppIcon.icns "$APP/Contents/Resources/"
codesign -s - --force "$APP"
