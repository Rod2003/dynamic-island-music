#!/bin/sh
set -e
swift build -c release
APP=.build/Island.app
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Island "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
ID=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
codesign --force --sign "${ID:--}" "$APP"
pkill -x Island || true
open "$APP"
