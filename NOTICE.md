# Third-party notices

Arcade Ruins is a port and derivative of several open-source projects. Their licences are
reproduced in this repository as listed below, and their copyright notices are intact in the
source files themselves.

**Nothing in this file, and nothing in this project, implies affiliation with or endorsement by
any of the parties named here.** See "Trademarks" at the end.

---

## Barlow Condensed (the JUCE plugin's typeface on Windows and Linux)

`Sources/S1Plugin/Fonts/BarlowCondensed-{Regular,Medium,SemiBold}.ttf`, linked into the JUCE
plugin and used wherever the system has no Avenir Next Condensed — which is everywhere but macOS,
where the Mac's own face is used and these are not (ADR-088, the owner's choice of 2026-09-20).

Copyright 2017 The Barlow Project Authors (<https://github.com/jpt/barlow>), under the **SIL Open
Font License, Version 1.1**. The licence is in `Sources/S1Plugin/Fonts/OFL.txt` beside the files,
as the OFL requires it to travel with them. The OFL permits bundling in a product, including a
commercial one; the font is not sold on its own and its name is not changed.

## AudioKit Synth One

Copyright © 2017 Aurelius Prochazka · MIT
<https://github.com/AudioKit/AudioKitSynthOne> · pinned at `6466a37`

The origin of this project. The DSP kernel, the 150-parameter model, the 12 storyboard panels, the
custom controls, the 695 factory presets and the microtonal tuning system are all ported from it.
Its licence: <https://github.com/AudioKit/AudioKitSynthOne/blob/6466a37/LICENSE>.
`Scripts/fetch-references.sh` places a read-only copy of the upstream tree at that commit in
`upstream/`, for comparison.

Ported code deliberately keeps its original file names, `AK` type prefixes and copyright headers,
so a diff against `upstream/` stays readable. See `docs/01-decisions.md` (ADR-009).

## AudioKit 4.9.2

Copyright © 2019 Aurelius Prochazka and the AudioKit contributors · MIT
Licence: [`Sources/S1Support/LICENSE-AudioKit`](Sources/S1Support/LICENSE-AudioKit)

Synth One was built on AudioKit, which this project does not depend on (ADR-002). What it needed
was ported instead: the microtonal machinery (`Microtonality/`), `AKTable`, and a small set of
helpers. See [`Sources/S1Support/PORTING.md`](Sources/S1Support/PORTING.md).

## Soundpipe (AudioKit fork)

Paul Batchelor and the AudioKit contributors · MIT
Licence: [`Sources/Soundpipe/LICENSE-AudioKit`](Sources/Soundpipe/LICENSE-AudioKit)

The DSP primitives the kernel is built from. **AudioKit's fork, not canonical Soundpipe** — the
band-limited `sp_oscmorph2d` exists only in the fork, and vendoring upstream Soundpipe would
silently remove the synth's anti-aliasing. See
[`Sources/Soundpipe/VENDORING.md`](Sources/Soundpipe/VENDORING.md) and ADR-011.

## The Amazing Audio Engine 2 (TAAE)

Copyright © 2016 A Tasty Pixel · zlib
Licence text in the header of each file in [`Sources/SynthOneCore/DSP/TAAE/`](Sources/SynthOneCore/DSP/TAAE/)

`AEMessageQueue` and `AEArray` — the lock-free channel the render thread uses to reach the main
thread. The zlib licence asks that an acknowledgement appear in product documentation, and this is
it: **Arcade Ruins uses The Amazing Audio Engine 2 by A Tasty Pixel.**

---

## JSON for Modern C++ (nlohmann/json)

Copyright © 2013–2022 Niels Lohmann · MIT
Licence: [`Sources/S1Engine/third_party/nlohmann/LICENSE.MIT`](Sources/S1Engine/third_party/nlohmann/LICENSE.MIT)

Version 3.11.3, the single header, vendored unmodified at
[`Sources/S1Engine/third_party/nlohmann/json.hpp`](Sources/S1Engine/third_party/nlohmann/json.hpp).
The portable engine reads and writes presets with it (X1-5, ADR-069); the Catalyst products keep
using Foundation's JSON.

---

## JUCE (the cross-platform plugin only)

Copyright © Raw Material Software Limited · used under the **JUCE 9 End User Licence Agreement,
Starter tier** (ADR-054; terms re-read 2026-09-18 for ADR-072) — not under the AGPLv3.
<https://juce.com/legal/juce-9-licence/>

JUCE 9.0.2 is **not in this repository**. The CMake build of "Arcade Ruins" — the VST3, the
Audio Unit and the standalone ([`Sources/S1Plugin`](Sources/S1Plugin)) — fetches it from
<https://github.com/juce-framework/JUCE> at a pinned commit when it is configured; the EULA does
not allow the framework to be distributed on its own. "Arcade Ruins Classic", the Catalyst app
and its AUv3, does not contain JUCE. The binaries built with it also contain, through JUCE, the
**VST 3 SDK 3.8.0** (© Steinberg Media Technologies GmbH, MIT), in the Audio Unit **Apple's
AudioUnitSDK 1.1.0** (© Apple Inc., Apache License 2.0, <https://github.com/apple/AudioUnitSDK>), and the
third-party code listed in JUCE's own `JUCE.spdx.json` (zlib, HarfBuzz, SheenBidi, libpng, jpeglib,
FLAC, Ogg Vorbis, CHOC and others, under their permissive licences). *VST is a registered
trademark of Steinberg Media Technologies GmbH. Audio Units is a trademark of Apple Inc.*

---

## Fonts

The interface uses **Avenir Next**, which ships with macOS. No font files are redistributed.

## Factory presets

All 695 presets in [`Sources/SynthOneCore/Presets/Data/`](Sources/SynthOneCore/Presets/Data/) come
from AudioKit Synth One under the MIT licence above, contributed by volunteer sound designers. Each
preset carries its designer in its `bank` field, and the bank names are preserved exactly:

> BankA · Bonus · Brice Beasley · DJ Puzzle · Electronisounds · Francis Preve · JEC ·
> Red Sky Lullaby · Sound of Izrael · Sound of Izrael 2 · Spidericemidas · Starter Bank · User

Please keep them that way. They are the credit those designers were given, and they are also load
order, which fixes the preset *numbers* a host writes into a saved session (ADR-024).

## Trademarks

"AudioKit" and "Synth One" are marks of AudioKit Pro, LLC. "Arcade Ruins" is an independent,
unofficial project and is **not affiliated with, authorised, sponsored or endorsed by** AudioKit,
AudioKit Pro, LLC, or any contributor to AudioKit Synth One. References to those names here are
factual statements of this project's origin, as the MIT licence requires — no more than that. All
AudioKit branding, wordmarks and logo artwork have been removed from this project.

A small number of factory presets are named after the instruments whose character they evoke
(for example "DX7 Harmonica", "Moogy Glide Bass"). All product names, trademarks and artists'
names are the property of their respective owners, and are used solely to identify the sounds
those presets are describing.
