#!/bin/bash
# Fetch the pinned third-party sources this port is derived from, into .references/
# (gitignored). Phases 2 and 3 still need AudioKit for AKPolyphonicNode, the MIDI
# layer, and the AudioKitUI views (AKADSRView, AKNodeOutputPlot, AKKeyboardView).
#
# Nothing in the build depends on .references/ — it is reading material. The code
# we actually ship is vendored under Sources/ with its own PORTING/VENDORING notes.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .references

# AudioKit 4.9.2. Also contains the Soundpipe fork we vendor:
#   AudioKit/Core/Soundpipe           (ADR-011)
#   AudioKit/Core/SoundpipeExtension  (band-limited sp_oscmorph2d)
AUDIOKIT_REV="03fecf80a66be88f6ac0356cd532c72dbe09922d"
if [ -d .references/AudioKit ]; then
    echo "AudioKit already present: $(git -C .references/AudioKit rev-parse --short HEAD)"
else
    echo "Cloning AudioKit v4.9.2..."
    git clone --depth 1 --branch v4.9.2 https://github.com/AudioKit/AudioKit.git .references/AudioKit
fi

HAVE=$(git -C .references/AudioKit rev-parse HEAD)
if [ "$HAVE" != "$AUDIOKIT_REV" ]; then
    echo "WARNING: AudioKit is at $HAVE, expected $AUDIOKIT_REV"
    echo "         Ports were made against the expected revision."
fi

# AudioKit Synth One itself, read-only, in upstream/. The private working repository tracks it; the
# public repository does not, so fetch it only when it is missing.
UPSTREAM_REV="6466a37"
if [ -d upstream ]; then
    echo "upstream/ already present"
else
    echo "Cloning AudioKit Synth One at $UPSTREAM_REV into upstream/..."
    git clone --quiet https://github.com/AudioKit/AudioKitSynthOne.git upstream
    git -C upstream checkout --quiet "$UPSTREAM_REV"
fi

echo
echo "Reference sources in .references/ :"
echo "  AudioKit/AudioKit/Common/Internals/Microtonality/   -> ported at P1-3"
echo "  AudioKit/AudioKit/Common/Internals/Table/           -> ported at P1-3"
echo "  AudioKit/AudioKit/Common/Internals/CoreAudio/       -> ported at P1-4"
echo "  AudioKit/AudioKit/Core/Soundpipe{,Extension}/       -> vendored at P1-5 (ADR-011)"
echo "  AudioKit/AudioKit/iOS/AudioKit/User Interface/      -> still to port (Phase 3)"
echo
echo "The Synth One original is already vendored read-only at upstream/ (commit 6466a37)."
