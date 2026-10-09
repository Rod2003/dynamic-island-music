#!/bin/sh
# Builds Island.app (TCC permissions need a real bundle) and launches it.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=.build/Island.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/Island "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
# A real identity keeps TCC grants across rebuilds; ad-hoc ("-") re-prompts every build.
ID=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
codesign --force --sign "${ID:--}" "$APP"
pkill -x Island || true
open "$APP"
