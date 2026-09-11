# Third-party notices

Arcade Ruins is a port and derivative of several open-source projects. Their licences are
reproduced in this repository as listed below, and their copyright notices are intact in the
source files themselves.

**Nothing in this file, and nothing in this project, implies affiliation with or endorsement by
any of the parties named here.** See "Trademarks" at the end.

---

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
