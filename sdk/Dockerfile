# Flutter SDK image, built on top of an inlined Android SDK.
#
# The Android SDK half of this file used to come from
# ghcr.io/cirruslabs/android-sdk:36, built out of
# cirruslabs/docker-images-android (sdk/tools + sdk/36). Cirrus Labs stopped
# updating that project, so the instructions are vendored here: this
# repository now owns the whole chain from ubuntu:24.04 up and has no
# dependency on the Cirrus Labs registry.
#
# The `android-sdk` stage exists purely as a documented seam so the Android
# half can be built and inspected on its own:
#
#     docker buildx build --target android-sdk sdk
#
# It is a linear stage (the flutter stage builds FROM it), so the published
# image is the same single image it has always been.

FROM ubuntu:24.04 AS android-sdk

USER root

ENV ANDROID_HOME=/opt/android-sdk-linux \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

ENV ANDROID_SDK_ROOT=$ANDROID_HOME \
    PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator

# comes from https://developer.android.com/studio/#command-line-tools-only
ENV ANDROID_SDK_TOOLS_VERSION=13114758

RUN set -o xtrace \
    && cd /opt \
    && apt-get update \
    && apt-get install -y jq \
    && apt-get install -y openjdk-21-jdk \
    && apt-get install -y sudo wget zip unzip git openssh-client curl bc software-properties-common build-essential ruby-full ruby-bundler libstdc++6 libpulse0 libglu1-mesa locales lcov libsqlite3-dev --no-install-recommends \
    # for x86 emulators
    && apt-get install -y libxtst6 libnss3-dev libnspr4 libxss1 libasound2t64 libatk-bridge2.0-0 libgtk-3-0 libgdk-pixbuf2.0-0 \
    && apt-get install -y -qq xxd \
    && apt-get install -y lftp \
    && apt-get install -qq -y sqlite3 libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && sh -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen' \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS_VERSION}_latest.zip -O android-sdk-tools.zip \
    && mkdir -p ${ANDROID_HOME}/cmdline-tools/ \
    && unzip -q android-sdk-tools.zip -d ${ANDROID_HOME}/cmdline-tools/ \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && chown -R root:root $ANDROID_HOME \
    && rm android-sdk-tools.zip \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && yes | sdkmanager --licenses \
    && mkdir -p /root/.android \
    && touch /root/.android/repositories.cfg \
    && sdkmanager platform-tools \
    && git config --global user.email "ci@localhost" \
    && git config --global user.name "CI"

# Upstream downloaded this from travis-ci/travis-cookbooks@master during the
# build; it is vendored next to this Dockerfile instead.
COPY android-wait-for-emulator /usr/bin/android-wait-for-emulator
RUN chmod +x /usr/bin/android-wait-for-emulator

# emulator is not available on linux/arm64 (https://issuetracker.google.com/issues/227219818)
RUN if [ $(uname -m) = "x86_64" ]; then sdkmanager emulator ; fi

# https://developer.android.com/studio/releases/platforms
ENV ANDROID_PLATFORM_VERSION=36
# https://developer.android.com/studio/releases/build-tools
ENV ANDROID_BUILD_TOOLS_VERSION=36.0.0

RUN yes | sdkmanager \
    "platforms;android-$ANDROID_PLATFORM_VERSION" \
    "build-tools;$ANDROID_BUILD_TOOLS_VERSION"

FROM android-sdk AS flutter

LABEL org.opencontainers.image.source=https://github.com/adrianjagielak/docker-images-flutter
LABEL org.opencontainers.image.description="Flutter SDK on top of the Android SDK. Continued fork of cirruslabs/docker-images-flutter."
LABEL org.opencontainers.image.licenses=MIT

USER root

ARG flutter_version

# Historically written as ${HOME}/sdks/flutter. HOME is not an ENV in this
# image, so Docker expanded it to the empty string and the published images
# have always used /sdks/flutter -- spelled out here so it stays that way.
ENV FLUTTER_HOME=/sdks/flutter \
    FLUTTER_VERSION=$flutter_version
ENV FLUTTER_ROOT=$FLUTTER_HOME

ENV PATH=${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME}

RUN yes | flutter doctor --android-licenses \
    && flutter doctor \
    && chown -R root:root ${FLUTTER_HOME}

RUN flutter precache --android
