FROM ghcr.io/cirruslabs/android-sdk:36

LABEL org.opencontainers.image.source=https://github.com/adrianjagielak/docker-images-flutter
LABEL org.opencontainers.image.description="Flutter SDK on top of the Android SDK. Continued fork of cirruslabs/docker-images-flutter."
LABEL org.opencontainers.image.licenses=MIT

USER root

# The flutter wrapper prints a superuser warning for a root shell. The wrapper
# stays quiet for Docker, for CI, and for a bot. Docker creates /.dockerenv, but
# containerd, Podman and a microVM sandbox do not. The image therefore creates
# the marker file and sets the bot flag.
ENV BOT=true
RUN touch /.dockerenv

ARG flutter_version

ENV FLUTTER_HOME=${HOME}/sdks/flutter \
    FLUTTER_VERSION=$flutter_version
ENV FLUTTER_ROOT=$FLUTTER_HOME

ENV PATH=${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME}

RUN yes | flutter doctor --android-licenses \
    && flutter doctor \
    && chown -R root:root ${FLUTTER_HOME}

RUN flutter precache --android
