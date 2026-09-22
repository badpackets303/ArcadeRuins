#!/bin/bash
# The Linux side of CI, on this Mac, in Docker (ADR-079's second amendment): what the workflows'
# ubuntu jobs do — GCC build, every CTest test, Steinberg's validator, pluginval at strictness 10
# under xvfb, and the RealtimeSanitizer build under Clang 20.
#
#   Scripts/validate-linux.sh [all|tests|validate|rtsan] [--x86]
#
# Docker Desktop must be running. The container is this Mac's architecture (arm64) by default:
# quick, and GCC/libstdc++/glibc/X11 are where Linux differs. --x86 runs an emulated x86-64
# container instead — several times slower; its point is arithmetic without fused multiply-add
# (ADR-071), so use it with `tests`. The repository is mounted read-only; build trees live in a
# Docker volume per architecture (docker volume rm arcade-ruins-linux-arm64 to start clean).
set -euo pipefail
cd "$(dirname "$0")/.."
stage=all; platform=linux/arm64; name=arm64
for argument in "$@"; do
    case "$argument" in
        --x86) platform=linux/amd64; name=amd64 ;;
        all|tests|validate|rtsan) stage=$argument ;;
        *) echo "usage: $0 [all|tests|validate|rtsan] [--x86]" >&2; exit 2 ;;
    esac
done
docker info > /dev/null 2>&1 || { echo "❌ Docker is not running" >&2; exit 1; }
docker build --quiet --platform "$platform" -t "arcade-ruins-linux:$name" Scripts/linux > /dev/null
docker run --rm --platform "$platform" \
    -v "$PWD":/src:ro -v "arcade-ruins-linux-$name":/work \
    "arcade-ruins-linux:$name" bash /src/Scripts/linux/run.sh "$stage"
