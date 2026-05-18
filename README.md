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

Channel tags float to the latest release on that channel and are refreshed automatically:

| Tag      | Tracks                              |
| -------- | ----------------------------------- |
| `latest` | latest Flutter **stable**           |
| `stable` | latest Flutter **stable**           |
| `beta`   | latest Flutter **beta** pre-release |

In addition, every build is tagged with its exact Flutter version (e.g. `3.41.9`, `3.44.0-0.3.pre`). `+` characters in pre-release versions are normalized to `-` so the tag is valid in OCI references.

Images are built for `linux/amd64` and `linux/arm64`.

For the full set of published image tags, see the package page on [GHCR](https://github.com/adrianjagielak/docker-images-flutter/pkgs/container/flutter).

## What's in the image

Each image is layered on the Android SDK image, clones the requested Flutter ref, accepts the Android SDK licenses, and runs `flutter precache --android`. The Dart SDK is on `PATH` via `${FLUTTER_HOME}/bin/cache/dart-sdk/bin`.

## Package

GHCR: <https://github.com/adrianjagielak/docker-images-flutter/pkgs/container/flutter>

## Maintaining this repository

See [`MAINTAINING.md`](./MAINTAINING.md) for how the build automation works, first-time setup, dependencies that may need attention over time, and the long-term maintenance checklist.
