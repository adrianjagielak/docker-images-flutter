# Docker Images for [Flutter](https://flutter.dev/)

[![Build and push Docker images](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/build-and-push.yml)
[![Check Flutter versions](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/check-flutter-versions.yml/badge.svg)](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/check-flutter-versions.yml)

Pre-built Docker images of the Flutter SDK, suitable for CI and local builds.

This is a community continuation of [`cirruslabs/docker-images-flutter`](https://github.com/cirruslabs/docker-images-flutter), which Cirrus Labs stopped updating in May 2026. The images and tag scheme here are intended to be drop-in compatible — change the registry prefix and existing workflows should keep working.

## Usage

Run `flutter test` against the current working directory:

```bash
docker run --rm -it -v "${PWD}:/build" --workdir /build \
    ghcr.io/adrianjagielak/flutter:stable \
    flutter test
```

Pull a specific Flutter version:

```bash
docker pull ghcr.io/adrianjagielak/flutter:3.41.9
```

## Available tags

Channel tags float to the latest release on that channel and are refreshed automatically. A channel tag is only moved onto an image after that image has passed an end-to-end smoke test — creating a Flutter app and building a debug APK — on both architectures, so a channel never points at an image that cannot build an app:

| Tag      | Tracks                              |
| -------- | ----------------------------------- |
| `latest` | latest Flutter **stable**           |
| `stable` | latest Flutter **stable**           |
| `beta`   | latest Flutter **beta** pre-release |

In addition, every build is tagged with its exact Flutter version (e.g. `3.41.9`, `3.44.0-0.3.pre`). `+` characters in pre-release versions are normalized to `-` so the tag is valid in OCI references.

Images are built for `linux/amd64` and `linux/arm64`.

For the full set of published image tags, see the package page on [GHCR](https://github.com/adrianjagielak/docker-images-flutter/pkgs/container/flutter).

## What's in the image

The image is built from `ubuntu:24.04` and contains, in one layer stack:

- **JDK 21**, plus the build tooling the Android SDK expects (`git`, `curl`, `wget`, `unzip`, `ruby`, `build-essential`, `sqlite3`, and the shared libraries the x86 emulator needs).
- **Android SDK** — command-line tools, `platform-tools`, `platforms;android-36`, `build-tools;36.0.0`, all licenses accepted. The emulator is installed on `linux/amd64` only; [it is not published for `linux/arm64`](https://issuetracker.google.com/issues/227219818).
- **Flutter SDK** at the requested version, cloned to `/sdks/flutter`, with `flutter precache --android` already run.

`ANDROID_HOME`/`ANDROID_SDK_ROOT` point at `/opt/android-sdk-linux` and `FLUTTER_HOME`/`FLUTTER_ROOT` at `/sdks/flutter`. Both SDKs, and the Dart SDK at `${FLUTTER_HOME}/bin/cache/dart-sdk/bin`, are on `PATH`.

> **`linux/arm64` cannot build Android APKs.** Google publishes the Android `platform-tools` and `build-tools` for `linux-x86_64` only, and `sdkmanager` installs those whatever the host architecture is — so on `linux/arm64` the `adb` and `aapt2` binaries in the image are x86-64 and do not run. Dart and Flutter themselves are native and fully working there: `flutter test`, `flutter analyze`, `flutter pub` and web builds are all fine. Use `linux/amd64` for anything that assembles an Android artifact. This is inherited from the Android SDK image this one was previously based on, which has the same limitation.

The Android half used to come from `ghcr.io/cirruslabs/android-sdk:36`. Those instructions now live in [`sdk/Dockerfile`](./sdk/Dockerfile) alongside the Flutter ones, so this repository builds the whole stack itself and depends on no Cirrus Labs image.

## Package

GHCR: <https://github.com/adrianjagielak/docker-images-flutter/pkgs/container/flutter>

## Maintaining this repository

See [`MAINTAINING.md`](./MAINTAINING.md) for how the build automation works, first-time setup, dependencies that may need attention over time, and the long-term maintenance checklist.
