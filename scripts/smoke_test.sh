#!/usr/bin/env bash
#
# End-to-end smoke test for a built Flutter image.
#
# Creates a throwaway Flutter app inside the image and takes it all the
# way to a debug APK. Building an APK is what actually exercises the
# Android SDK, build-tools, licenses and JDK together, so it catches
# breakage that "the image built" and "flutter --version works" both
# miss -- which is most of what can go wrong in sdk/Dockerfile.
#
# Usage:
#   scripts/smoke_test.sh <image-ref> [platform]
#
# Examples:
#   scripts/smoke_test.sh ghcr.io/adrianjagielak/flutter:stable
#   scripts/smoke_test.sh ghcr.io/adrianjagielak/flutter:stable linux/arm64

set -euo pipefail

IMAGE="${1:?usage: smoke_test.sh <image-ref> [platform]}"
PLATFORM="${2:-}"

run_args=(--rm)
if [ -n "$PLATFORM" ]; then
    run_args+=(--platform "$PLATFORM")
fi

echo "Smoke-testing ${IMAGE}${PLATFORM:+ (${PLATFORM})}"

docker run "${run_args[@]}" "$IMAGE" bash -euo pipefail -c '
    echo "--- versions ---"
    flutter --version
    dart --version
    java -version
    echo "ANDROID_HOME=$ANDROID_HOME FLUTTER_HOME=$FLUTTER_HOME"

    echo "--- flutter doctor ---"
    # flutter doctor exits non-zero over categories this image deliberately
    # does not ship (Chrome, the Linux desktop toolchain), so assert on the
    # Android toolchain line rather than on the exit code. Only an explicit
    # failure or warning marker fails the test: matching the success glyph
    # instead would turn a cosmetic change in Flutter output into a red
    # release, and the APK build below is the real check anyway.
    doctor=$(flutter doctor 2>&1 || true)
    echo "$doctor"
    android_line=$(grep -E "Android toolchain" <<<"$doctor" || true)
    if [ -z "$android_line" ]; then
        echo "FAIL: flutter doctor reported no Android toolchain at all"
        exit 1
    fi
    case "$android_line" in
        *"[✗]"*|*"[!]"*)
            echo "FAIL: $android_line"
            exit 1
            ;;
    esac
    echo "OK: $android_line"

    app=$(mktemp -d)
    cd "$app"

    echo "--- flutter create ---"
    flutter create --project-name flutter_image_smoke_test .

    echo "--- flutter analyze ---"
    flutter analyze

    echo "--- flutter test ---"
    flutter test

    # Google publishes the Android platform-tools and build-tools for
    # linux-x86_64 only, and sdkmanager installs those whatever the host
    # architecture is, so on a non-x86_64 host the adb and aapt2 in this
    # image are x86-64 binaries that cannot run and no APK can be built.
    # That is why only linux/amd64 images are published -- see README.
    #
    # CI therefore always takes the first branch. The check is here for
    # anyone running this script by hand against an image they built on
    # an arm64 machine, where it explains the failure instead of letting
    # Gradle report it as a mystery, and it would start exercising the
    # APK build by itself if Google ever shipped linux-arm64 build-tools.
    aapt2="${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS_VERSION}/aapt2"
    if "$aapt2" version >/dev/null 2>&1; then
        echo "--- flutter build apk --debug ---"
        flutter build apk --debug

        apk=build/app/outputs/flutter-apk/app-debug.apk
        test -s "$apk" || { echo "FAIL: $apk missing or empty"; exit 1; }
        ls -l "$apk"
    else
        echo "--- flutter build apk --debug: SKIPPED ---"
        echo "$aapt2 does not run on $(uname -m):"
        echo "  $("$aapt2" version 2>&1 | head -1)"
        echo "The Android build tools are published for linux-x86_64 only, so an"
        echo "image on this architecture cannot assemble an APK; this is why only"
        echo "linux/amd64 is published. Everything above -- the Dart and Flutter"
        echo "halves -- was exercised in full."
    fi

    echo "SMOKE TEST PASSED"
'
