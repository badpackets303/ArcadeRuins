#!/bin/bash
# X4-1 (ADR-094): the Linux release — a tarball with the VST3, the standalone, install.sh and
# uninstall.sh — built in Docker on this Mac, on Ubuntu 22.04 so that it runs on glibc 2.35 and
# newer. Every CTest test runs on the binaries being packaged.
#
#   Scripts/release-linux.sh            # this Mac's architecture: aarch64 (Raspberry Pi 5, Asahi, ARM servers)
#   Scripts/release-linux.sh --x86      # x86-64, EMULATED here: the one most Linux musicians need; an hour or more
#
# Output: build/release-linux/ArcadeRuins-<version>-linux-<arch>.tar.gz and its SHA-256.
# Linux binaries are not signed; the checksum published with the release is the check.
set -euo pipefail
cd "$(dirname "$0")/.."
platform=linux/arm64; name=arm64
if [ "${1:-}" = "--x86" ]; then platform=linux/amd64; name=amd64; fi
docker info > /dev/null 2>&1 || { echo "❌ Docker is not running" >&2; exit 1; }
mkdir -p build/release-linux
docker build --quiet --platform "$platform" -f Scripts/linux/Dockerfile.release -t "arcade-ruins-linux-release:$name" Scripts/linux > /dev/null
docker run --rm --platform "$platform" \
    -v "$PWD":/src:ro -v "arcade-ruins-linux-release-$name":/work -v "$PWD/build/release-linux":/out \
    "arcade-ruins-linux-release:$name" bash /src/Scripts/linux/package.sh
