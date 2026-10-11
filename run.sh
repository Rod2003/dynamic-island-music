#!/bin/sh
set -e
swift build -c release
APP=.build/Island.app
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Island "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --timestamp --options runtime --entitlements Island.entitlements --sign "Developer ID Application" "$APP"
if [ "$1" = release ]; then
  ditto -c -k --keepParent "$APP" .build/Island.zip
  xcrun notarytool submit .build/Island.zip --keychain-profile notary --wait
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" .build/Island.zip
  exit
fi
pkill -x Island || true
open "$APP"
