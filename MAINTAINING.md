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

Two workflows keep this repository running without manual intervention, and a third gates changes to the image before they merge.

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

For each unique Flutter version in `versions.json` it builds a single multi-arch image and pushes it to GHCR under both its version tag and every channel tag that points at it.

All matrix entries share one `type=gha` cache scope. Since the image builds the Android SDK itself rather than inheriting it from a prebuilt base, the Android layers are byte-identical across Flutter versions, and a shared scope lets a build of a brand-new Flutter version start from them instead of rebuilding the Android half from scratch. The Flutter-specific layers are a cache miss for a new version either way, so nothing is lost by not scoping per version — and one scope rather than N keeps the repository under the 10 GB GitHub Actions cache limit.

`arm64` is built via QEMU emulation on the same `ubuntu-latest` runner as `amd64`. This matches the original Cirrus setup, but note that emulated arm64 now covers the Android SDK install (`apt`, and several JVM `sdkmanager` runs) as well as the Flutter steps, so a cold cache is considerably slower than it used to be. If `arm64` build time becomes painful, the matrix can be split across `ubuntu-latest` + `ubuntu-24.04-arm` so each architecture builds natively, with a separate `docker buildx imagetools create` job to merge the manifest.

### `.github/workflows/pr-build.yml`

Pre-merge validation. The release workflow above only runs on pushes to the default branch, so without this a structural change to the image would first be exercised *after* it had been merged.

On a pull request touching `sdk/**` or either build workflow, it builds the current `stable` entry from `versions.json` for both published architectures with `push: false` — no registry credentials, no tags, result discarded. Version bumps to `versions.json` deliberately do not trigger it: those change nothing that can break the build, and they land on `master` directly rather than through a PR anyway.

It reads the release build's `type=gha` cache scope so the Android layers start warm, but never writes to it — a pull request must not be able to influence what the release build reuses. Runs are capped at 240 minutes and superseded by the next push to the same PR.


## Local development

Build a single version locally:

```bash
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --build-arg flutter_version=3.41.9 \
    --tag ghcr.io/adrianjagielak/flutter:3.41.9 \
    sdk
```

`sdk/Dockerfile` has two linear stages, `android-sdk` and `flutter`. To iterate on the Android half without paying for the Flutter clone and precache, build the first stage on its own:

```bash
docker buildx build --target android-sdk --tag android-sdk-local sdk
```

Refresh `versions.json` against the upstream release index (requires `jq`):

```bash
bash scripts/update_flutter_versions.sh
```

Pin a Flutter version manually by editing `versions.json` and pushing to `master` — the build workflow will run.

## Dependencies that may need attention over time

### The Android SDK layers

The image used to be built `FROM ghcr.io/cirruslabs/android-sdk:36`, from the same wound-down Cirrus Labs project as the upstream Flutter image — so it would never have received another Android SDK bump, and would have broken outright (`manifest unknown`) if the package were ever deleted.

Those instructions are now inlined into the `android-sdk` stage of [`sdk/Dockerfile`](./sdk/Dockerfile), copied from `cirruslabs/docker-images-android` (`sdk/tools` + `sdk/36`) as of its final state. The image builds `FROM ubuntu:24.04` and there is no Cirrus Labs dependency left anywhere in the chain. The one behavioural difference from the old base image is the container-global git identity, which used to be `Cirrus CI <support@cirruslabs.org>` and is now `CI <ci@localhost>`.

Three pins in that stage are ours to move now, and nothing bumps them automatically:

| `ENV`                         | Currently  | Where to check                                                 |
| ----------------------------- | ---------- | -------------------------------------------------------------- |
| `ANDROID_SDK_TOOLS_VERSION`   | `13114758` | <https://developer.android.com/studio#command-line-tools-only>  |
| `ANDROID_PLATFORM_VERSION`    | `36`       | <https://developer.android.com/tools/releases/platforms>        |
| `ANDROID_BUILD_TOOLS_VERSION` | `36.0.0`   | <https://developer.android.com/tools/releases/build-tools>      |

Bump them when Flutter's minimum supported `compileSdk` moves past the pinned platform, or when a Flutter release starts warning about the build-tools version in `flutter doctor`. Changing any of them invalidates the shared build cache, so the next build is a slow one.

### `ubuntu:24.04` (base image)

Pinned by tag rather than digest, deliberately: the weekly rebuild is what picks up Ubuntu security updates. When 24.04 goes out of standard support, bump the `FROM` line and expect package-name churn in the big `apt-get install` (24.04 already renamed `libasound2` to `libasound2t64`, for example).

### `sdk/android-wait-for-emulator`

The Android SDK image downloaded this helper from `travis-ci/travis-cookbooks@master` during every build. It is vendored in-tree instead, so no build step depends on an unpinned third-party branch. It is public-domain, ~25 lines, and only useful if you run an emulator in the container; it exists for compatibility with the old image.

### Flutter's release index

`scripts/update_flutter_versions.sh` reads `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`. If Flutter ever moves or restructures that feed, the script needs updating. The JSON shape it depends on is:

- `.current_release.<channel>` → commit hash
- `.releases[] | select(.hash == <hash>) | .version` → version string

### Third-party GitHub Actions

`build-and-push.yml` and `pr-build.yml` use `jlumbroso/free-disk-space@main` (unpinned). If you prefer supply-chain pinning, replace `@main` with a commit SHA. The other actions (`docker/setup-qemu-action`, `docker/setup-buildx-action`, `docker/login-action`, `docker/build-push-action`, `actions/checkout`) are pinned to major versions.

## Maintenance checklist

Expect occasional human attention when:

- **A Flutter release breaks the build.** Inspect the failing job in **Build and push Docker images**. Fix `sdk/Dockerfile` (e.g. Flutter adds a new precache requirement, changes its repository layout, or drops support for the current Dart/Android baseline) and push.
- **The Android SDK pins need moving.** Bump `ANDROID_PLATFORM_VERSION` / `ANDROID_BUILD_TOOLS_VERSION` / `ANDROID_SDK_TOOLS_VERSION` in `sdk/Dockerfile` as described above. Nothing polls for these, so it takes a human noticing.
- **Flutter changes its release feed.** Update `scripts/update_flutter_versions.sh`.
- **A new channel needs tracking** (e.g. you want to publish `dev` or `master` builds). Add it to the matrix produced in `scripts/update_flutter_versions.sh` and to the `images` array in `versions.json`.
- **Build runs exhaust disk space.** The `jlumbroso/free-disk-space` step is generous already; if it stops being enough, drop more of its `false` flags to `true`, or split arm64 onto a dedicated runner.
- **GitHub deprecates a workflow API used here.** Most commonly: `actions/checkout` and `docker/*` action major versions, or the `type=gha` cache backend.
