# The Linux side of CI on the developer's Mac (ADR-079's second amendment): the image the
# `plugin` and `engine` workflows' ubuntu-latest jobs amount to — Ubuntu 24.04, GCC, JUCE's
# dependencies, xvfb for pluginval, gtkmm (Steinberg's SDK will not configure its hosting
# samples — the validator among them — without it), Clang 20 for the RealtimeSanitizer. Built by
# Scripts/validate-linux.sh; nothing of the repository is copied in.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates pkg-config wget gnupg lsb-release software-properties-common \
        libasound2-dev libjack-jackd2-dev libfreetype-dev libfontconfig1-dev \
        libx11-dev libxcomposite-dev libxcursor-dev libxext-dev libxinerama-dev \
        libxrandr-dev libxrender-dev libxi-dev \
        libcurl4-openssl-dev libglu1-mesa-dev mesa-common-dev ladspa-sdk libgtk-3-dev libgtkmm-3.0-dev \
        xvfb xauth \
    && wget -q https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 20 \
    && apt-get install -y --no-install-recommends libclang-rt-20-dev \
    && rm -rf /var/lib/apt/lists/* llvm.sh
WORKDIR /work
