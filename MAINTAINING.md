# Maintaining this repository

This document is for anyone running the build pipeline — i.e. the repository owner or maintainers of a fork. End users of the published images do not need to read this; see [`README.md`](./README.md) instead.

The pipeline is designed to run unattended on GitHub Actions. In normal operation no human action is required: new Flutter releases are picked up, committed, built, and pushed automatically. The notes below cover the one-time setup, the moving parts, and the cases that eventually require manual attention.

## First-time setup

One-time steps after forking this repository or transferring it:

1. **Enable GitHub Actions** under the *Actions* tab if it is not on by default.
2. **Allow Actions to write to the repository.** Settings → Actions → General → *Workflow permissions* → "Read and write permissions". Required for the version checker to commit directly and to dispatch the build workflow.
3. **Run the build at least once** — either let the next scheduled check fire or trigger **Build and push Docker images** manually from the Actions tab. This is what creates the `flutter` package under your user/organization on GHCR.
4. **Make the package public** (optional but standard for this image): on the package page (`https://github.com/<owner>/docker-images-flutter/pkgs/container/flutter`) → *Package settings* → *Change visibility* → *Public*. Until you do this, pulls require `docker login ghcr.io`.

If you forked from `adrianjagielak/docker-images-flutter`, also update the image-source labels in [`sdk/Dockerfile`](./sdk/Dockerfile) and the badge / link URLs in [`README.md`](./README.md) to point at your fork. The registry path is derived from `${{ github.repository_owner }}` at build time, so no workflow change is needed for that.

## How the automation works

Two workflows keep this repository running without manual intervention.

### `.github/workflows/check-flutter-versions.yml`

Runs every two hours (and on demand). For each release channel it:

1. Fetches `releases_linux.json` from Flutter's release index.
2. Resolves the current `stable` and `beta` hashes to version strings.
3. Rewrites [`versions.json`](./versions.json).
4. If anything changed, commits the file directly to the default branch and dispatches the build workflow. The commit summary lists every channel/version pair (`chore: update Flutter versions (latest/stable: 3.x.y, beta: 3.x.y-N.N.pre)`).

Because pushes made by `GITHUB_TOKEN` do not trigger downstream workflows, the build is started with an explicit `gh workflow run` call from the same job. A direct push (not via `GITHUB_TOKEN`) to `master` will trigger the build via the normal `push` event instead.

### `.github/workflows/build-and-push.yml`

Triggered by:

- pushes to the default branch that touch `versions.json`, `sdk/**`, or the workflow itself
- the version checker after it commits a bump
- a weekly cron (`Monday 05:00 UTC`) so base-image security updates land even when Flutter does not move
- manual `workflow_dispatch`, with an optional `flutter_version` filter to rebuild just one entry

For each unique Flutter version in `versions.json` it builds a single multi-arch image and pushes it to GHCR under both its version tag and every channel tag that points at it. A per-Flutter-version `type=gha` cache keeps incremental builds fast without cross-version invalidation.

`arm64` is built via QEMU emulation on the same `ubuntu-latest` runner as `amd64`. This matches the original Cirrus setup. If `arm64` build time becomes painful, the matrix can be split across `ubuntu-latest` + `ubuntu-24.04-arm` with a separate manifest job.

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

## Dependencies that may need attention over time

### `ghcr.io/cirruslabs/android-sdk:36` (base image)

The Flutter image is built `FROM ghcr.io/cirruslabs/android-sdk:36`. That image is part of the same wound-down Cirrus Labs project as the upstream Flutter image. The tag `:36` is pinned and continues to be served by GHCR for now, but:

- it will not receive further Android SDK version bumps from upstream
- if the package is ever deleted, builds here will start failing with `manifest unknown`

When that happens, the `FROM` line in [`sdk/Dockerfile`](./sdk/Dockerfile) needs to be repointed at an alternative — either a fork of the Android image, or a different base image that provides the Android SDK that `flutter doctor --android-licenses` and `flutter precache --android` need.

### Flutter's release index

`scripts/update_flutter_versions.sh` reads `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`. If Flutter ever moves or restructures that feed, the script needs updating. The JSON shape it depends on is:

- `.current_release.<channel>` → commit hash
- `.releases[] | select(.hash == <hash>) | .version` → version string

### Third-party GitHub Actions

`build-and-push.yml` uses `jlumbroso/free-disk-space@main` (unpinned). If you prefer supply-chain pinning, replace `@main` with a commit SHA. The other actions (`docker/setup-qemu-action`, `docker/setup-buildx-action`, `docker/login-action`, `docker/build-push-action`, `actions/checkout`) are pinned to major versions.

## Maintenance checklist

Expect occasional human attention when:

- **A Flutter release breaks the build.** Inspect the failing job in **Build and push Docker images**. Fix `sdk/Dockerfile` (e.g. Flutter adds a new precache requirement, changes its repository layout, or drops support for the current Dart/Android baseline) and push.
- **The Android base image changes or disappears.** Bump the `FROM` tag in `sdk/Dockerfile` to a newer `android-sdk` image if one becomes available, or repoint to a replacement registry as described above.
- **Flutter changes its release feed.** Update `scripts/update_flutter_versions.sh`.
- **A new channel needs tracking** (e.g. you want to publish `dev` or `master` builds). Add it to the matrix produced in `scripts/update_flutter_versions.sh` and to the `images` array in `versions.json`.
- **Build runs exhaust disk space.** The `jlumbroso/free-disk-space` step is generous already; if it stops being enough, drop more of its `false` flags to `true`, or split arm64 onto a dedicated runner.
- **GitHub deprecates a workflow API used here.** Most commonly: `actions/checkout` and `docker/*` action major versions, or the `type=gha` cache backend.
