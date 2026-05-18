# Docker Images for [Flutter](https://flutter.dev/)

[![Build and push Docker images](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/build-and-push.yml)
[![Check Flutter versions](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/check-flutter-versions.yml/badge.svg)](https://github.com/adrianjagielak/docker-images-flutter/actions/workflows/check-flutter-versions.yml)

This is a community continuation of [`cirruslabs/docker-images-flutter`](https://github.com/cirruslabs/docker-images-flutter), which Cirrus Labs stopped updating in May 2026 after the company was acquired. The images, build pipeline, and update automation here are equivalent to the originals but published from `ghcr.io/adrianjagielak/flutter` and driven entirely by GitHub Actions instead of Cirrus CI.

## Usage

Run a Flutter command against the current working directory:

```bash
docker run --rm -it -v "${PWD}:/build" --workdir /build \
    ghcr.io/adrianjagielak/flutter:stable \
    flutter test
```

Pull a specific Flutter version:

```bash
docker pull ghcr.io/adrianjagielak/flutter:3.41.9
```

### Available tags

Channel tags float to the latest release on that channel and are refreshed automatically:

| Tag      | Tracks                                |
| -------- | ------------------------------------- |
| `latest` | latest Flutter **stable**             |
| `stable` | latest Flutter **stable**             |
| `beta`   | latest Flutter **beta** pre-release   |

In addition, every build is tagged with its exact Flutter version (e.g. `3.41.9`, `3.44.0-0.3.pre`). `+` characters in pre-release versions are normalized to `-` so the tag is valid in OCI references.

Images are built for `linux/amd64` and `linux/arm64`.

The currently-published versions are tracked in [`versions.json`](./versions.json).

### Image contents

Each image is layered on top of [`ghcr.io/cirruslabs/android-sdk:36`](https://github.com/cirruslabs/docker-images-android), clones the requested Flutter ref, accepts the Android SDK licenses, and runs `flutter precache --android`. The Dart SDK is on `PATH` via `${FLUTTER_HOME}/bin/cache/dart-sdk/bin`.

> **Note on the Android base image:** the `cirruslabs/android-sdk` image is also part of the wound-down Cirrus Labs project. The tag `:36` is pinned and continues to be served by GHCR. If that image ever disappears, the `FROM` line in [`sdk/Dockerfile`](./sdk/Dockerfile) will need to be repointed at an alternative.

## How the automation works

Two workflows keep this repository running without manual intervention.

### `check-flutter-versions.yml`

Runs every two hours (and on demand). For each release channel it:

1. Fetches `releases_linux.json` from Flutter's release index.
2. Resolves the current `stable` and `beta` hashes to version strings.
3. Rewrites [`versions.json`](./versions.json).
4. If anything changed, commits the file directly to the default branch and dispatches the build workflow. The commit summary lists every channel/version pair (`chore: update Flutter versions (latest/stable: 3.x.y, beta: 3.x.y-N.N.pre)`).

Because pushes made by `GITHUB_TOKEN` do not trigger downstream workflows, the build is started with an explicit `gh workflow run` call from the same job.

### `build-and-push.yml`

Triggered by:

- pushes to the default branch that touch `versions.json`, `sdk/**`, or the workflow itself
- the version checker after it commits a bump
- a weekly cron (`Monday 05:00 UTC`) so base-image security updates land even when Flutter does not move
- manual `workflow_dispatch`, with an optional `flutter_version` filter to rebuild just one entry

For each unique Flutter version in `versions.json` it builds a single multi-arch image and pushes it to GHCR under both its version tag and every channel tag that points at it. A per-Flutter-version `type=gha` cache keeps incremental builds fast without cross-version invalidation.

## Local development

Build a single version locally:

```bash
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --build-arg flutter_version=3.41.9 \
    --tag ghcr.io/adrianjagielak/flutter:3.41.9 \
    sdk
```

Refresh `versions.json` against the upstream release index (requires `jq`):

```bash
bash scripts/update_flutter_versions.sh
```

Pin a Flutter version manually by editing `versions.json` and pushing to `master` — the build workflow will run.

## First-time setup

These are one-time steps after forking or creating the repository:

1. **Enable GitHub Actions** under the *Actions* tab if it is not on by default.
2. **Allow Actions to write to the repository.** Settings → Actions → General → *Workflow permissions* → "Read and write permissions". This is required for the version checker to commit directly and to dispatch the build workflow.
3. **Run the build at least once** — either let the next scheduled check fire or trigger `Build and push Docker images` manually from the Actions tab. This is what creates the `flutter` package under your user/organization.
4. **Make the package public** (optional, but the standard for this image): on the package page (`https://github.com/<owner>/docker-images-flutter/pkgs/container/flutter`) → *Package settings* → *Change visibility* → *Public*. Until you do this, pulls require `docker login ghcr.io`.

## Maintenance checklist

The pipeline is designed to run unattended, but expect occasional human attention when:

- **A Flutter release breaks the build.** Inspect the failing job in the **Build and push Docker images** workflow. Fix `sdk/Dockerfile` (for example, if Flutter adds a new precache requirement or changes its repository layout) and push.
- **The Android base image changes.** Bump the `FROM` tag in `sdk/Dockerfile` if a newer `android-sdk` image is required, or repoint to a replacement registry if `cirruslabs/android-sdk` becomes unavailable.
- **Flutter changes its release feed.** If `releases_linux.json` ever moves or changes shape, update `scripts/update_flutter_versions.sh`.
- **A new channel needs tracking.** Add an entry to the matrix produced in `scripts/update_flutter_versions.sh` and to the `images` array in `versions.json`.

## GitHub Container Registry

Image package page: <https://github.com/adrianjagielak/docker-images-flutter/pkgs/container/flutter>

## License

MIT. See [`LICENSE`](./LICENSE). Originally authored by Cirrus Labs; this fork continues the project under the same terms.
