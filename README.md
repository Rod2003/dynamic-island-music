# Soundwave

Turns the MacBook notch into a Dynamic Island for whatever is playing: the app's icon on the left (album art for Spotify) and a live waveform of the actual audio on the right. Works with any app or website.

## Install

1. Download `Soundwave.zip` from [Releases](../../releases/latest), unzip, and move `Soundwave.app` to Applications.
2. Open it and allow **System Audio Recording** (and **Automation** for Spotify album art) when asked.

Needs a MacBook with a notch and macOS 14.2 or later. There's no Dock icon; quit it from Activity Monitor.

## Build

```sh
./run.sh            # build, sign with your Developer ID, launch
./run.sh release    # notarize and zip to .build/Soundwave.zip (needs a "notary" notarytool profile)
```

To publish a release, bump `CFBundleShortVersionString` in `Info.plist` and push a matching tag (`git tag v1.0.1 && git push origin v1.0.1`); GitHub Actions builds, notarizes and publishes it.

## License

MIT
