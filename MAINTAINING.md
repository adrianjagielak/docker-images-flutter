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

- pushes to the default branch that touch `versions.json`, `sdk/**`, the smoke-test script, or the workflow itself
- the version checker after it commits a bump
- a weekly cron (`Monday 05:00 UTC`) so base-image security updates land even when Flutter does not move
- manual `workflow_dispatch`, with an optional `flutter_version` filter to rebuild just one entry

`prepare` turns `versions.json` into a matrix — one entry per unique Flutter version, carrying that version's normalized image tag and every channel tag pointing at it. `build` then runs once per entry, and each entry does the whole release itself:

1. **Build** into the runner's Docker daemon (`load: true`, `push: false`) rather than straight to the registry.
2. **Smoke test** that loaded image with [`scripts/smoke_test.sh`](./scripts/smoke_test.sh).
3. **Push** — reached only if the test passed — tagging the image with its exact Flutter version and then every channel tag.

Building into the daemon first is what makes the ordering possible: **nothing reaches GHCR until a real Flutter app has been built inside the image.** A version that fails to build or fails its test publishes nothing at all, and every tag it would have moved keeps pointing at the last image that passed. That is the same failure behaviour the workflow always had — a failed build has always meant tags stay put — except that "failed" now also covers an image that builds but cannot compile an app. Watch for a red run; nothing else will tell you a channel has stopped moving.

`fail-fast: false` keeps the versions independent: a broken beta publishes nothing but does not stop a good stable from going out.

All matrix entries share one `type=gha` cache scope. Since the image builds the Android SDK itself rather than inheriting it from a prebuilt base, the Android layers are byte-identical across Flutter versions, and a shared scope lets a build of a brand-new Flutter version start from them instead of rebuilding the Android half from scratch. The Flutter-specific layers are a cache miss for a new version either way, so nothing is lost by not scoping per version — and one scope rather than N keeps the repository under the 10 GB GitHub Actions cache limit.

Only `linux/amd64` is built, so there is no QEMU anywhere in the pipeline and the image can be loaded into the daemon at all — a multi-arch build cannot be. See the Android SDK layers section for why arm64 is not published.

### `.github/workflows/pr-build.yml`

Pre-merge validation. The release workflow only runs on pushes to the default branch, so without this a structural change to the image would first be exercised *after* it had been merged.

On a pull request touching `sdk/**`, the smoke-test script, or either build workflow, it builds the current `stable` entry from `versions.json` and runs the same smoke test against it, with `push: false`. No registry credentials, no tags, result discarded. Version bumps to `versions.json` deliberately do not trigger it: those change nothing that can break the image, and they land on `master` directly rather than through a PR anyway.

It reads the release build's `type=gha` cache scope so the Android layers start warm, but never writes to it — a pull request must not be able to influence what the release build reuses. That means a PR build is cold apart from the Android prefix, which is a few minutes; adding a PR-scoped `cache-to` would speed up repeat pushes but count against the same 10 GB budget and risk evicting the release cache, which is the more valuable one.

## The smoke test

[`scripts/smoke_test.sh`](./scripts/smoke_test.sh) takes an image reference and an optional platform, and is what both the PR check and the release build use:

```bash
bash scripts/smoke_test.sh ghcr.io/adrianjagielak/flutter:stable
```

Inside the image it checks the tool versions, asserts `flutter doctor` does not report a problem with the Android toolchain, then creates a throwaway Flutter app and runs `flutter analyze`, `flutter test` and `flutter build apk --debug` against it.

The APK build is the part that earns its keep. It is the only step that exercises the Android SDK, build-tools, accepted licenses, Gradle and the JDK *together* — which is most of what `sdk/Dockerfile` can get wrong, and none of which is caught by the image merely building. Expect it to dominate the runtime, since Gradle downloads its distribution and the Android dependencies on each run. It is also the step most exposed to upstream rate limits, since it pulls from `plugins.gradle.org` and Maven Central; Flutter retries once internally, and a run that fails there with HTTP 429 is worth re-running before treating it as a real failure.

The `flutter doctor` assertion fails only on an explicit `[✗]` or `[!]` against the Android toolchain rather than matching the success glyph, so a cosmetic change to Flutter's output cannot turn a release red on its own; the APK build is the real check behind it. That split matters more than it looks: `flutter doctor` reported the Android toolchain as `[✓]` on arm64 even when `adb` there could not execute at all, and only the APK build caught it.

The script skips the APK build where `aapt2` will not run. CI never takes that branch now that only `linux/amd64` is published; it is there for anyone running the script by hand against an image built on an arm64 machine, where it explains the problem instead of leaving Gradle to report it as a mystery.

## Local development

Build a single version locally:

```bash
docker buildx build \
    --platform linux/amd64 \
    --build-arg flutter_version=3.41.9 \
    --tag ghcr.io/adrianjagielak/flutter:3.41.9 \
    sdk
```

`sdk/Dockerfile` has two linear stages, `android-sdk` and `flutter`. To iterate on the Android half without paying for the Flutter clone and precache, build the first stage on its own:

```bash
docker buildx build --target android-sdk --tag android-sdk-local sdk
```

Smoke-test an image you just built:

```bash
bash scripts/smoke_test.sh ghcr.io/adrianjagielak/flutter:3.41.9
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

### Why `linux/arm64` is not published

This repository used to publish an arm64 image, and it was broken in a way nothing tested for: `adb` and `aapt2` in it were x86-64 binaries, so they could not execute and no APK could be assembled. Google publishes the Android `platform-tools` and `build-tools` for `linux-x86_64` only, and `sdkmanager` installs those regardless of host architecture. `ghcr.io/cirruslabs/android-sdk:36` has exactly the same x86-64 binaries in its arm64 image, so this long predates the inlining — it was simply invisible until the smoke test tried to build an app.

Rather than keep shipping an image that cannot do the thing it exists for, arm64 was dropped. It was a real if narrow loss: the arm64 image did work for `flutter test`, `flutter analyze`, `flutter pub` and web builds, and anyone using it that way now needs `--platform linux/amd64` and emulation.

Publishing it again is a small change — `platforms:` in `build-and-push.yml` plus the `load: true`/push flow, which only works because the build is single-arch — but only worth doing if Google ships `linux-arm64` build-tools. The smoke test would pick that up on its own: it gates the APK build on whether `aapt2` actually runs, not on `uname`.

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
- **The smoke test fails.** Nothing was published for that version, so users are still on the last good image while you look. Reproduce by building locally and running `bash scripts/smoke_test.sh <image>`. If Flutter changes the generated app template or its tooling output, the fix may belong in `scripts/smoke_test.sh` rather than in the image.
- **The Android SDK pins need moving.** Bump `ANDROID_PLATFORM_VERSION` / `ANDROID_BUILD_TOOLS_VERSION` / `ANDROID_SDK_TOOLS_VERSION` in `sdk/Dockerfile` as described above. Nothing polls for these, so it takes a human noticing.
- **Flutter changes its release feed.** Update `scripts/update_flutter_versions.sh`.
- **A new channel needs tracking** (e.g. you want to publish `dev` or `master` builds). Add it to the matrix produced in `scripts/update_flutter_versions.sh` and to the `images` array in `versions.json`.
- **Build runs exhaust disk space.** The `jlumbroso/free-disk-space` step is generous already; if it stops being enough, drop more of its `false` flags to `true`, or split arm64 onto a dedicated runner.
- **GitHub deprecates a workflow API used here.** Most commonly: `actions/checkout` and `docker/*` action major versions, or the `type=gha` cache backend.
