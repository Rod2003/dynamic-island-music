#!/bin/sh
set -e
swift build -c release
APP=.build/Soundwave.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Soundwave "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
xcrun actool Soundwave.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.2 --app-icon Soundwave --output-partial-info-plist .build/icon.plist >/dev/null
codesign --force --timestamp --options runtime --entitlements Soundwave.entitlements --sign "Developer ID Application" "$APP"
if [ "$1" = release ]; then
  ditto -c -k --keepParent "$APP" .build/Soundwave.zip
  xcrun notarytool submit .build/Soundwave.zip --keychain-profile notary --wait
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" .build/Soundwave.zip
  exit
fi
pkill -x Soundwave || true
open "$APP"
