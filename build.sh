#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build -c release

APP=Impaler.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Impaler" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign -s - --force "$APP"
