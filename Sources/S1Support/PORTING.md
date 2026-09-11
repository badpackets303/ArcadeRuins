# S1Support — porting record (P1-3)

Replacements for the AudioKit 4.9.2 glue Synth One depends on. Two kinds of file live here:

- **Ported from AudioKit** (MIT) — `Microtonality/`, `Table/`, and the slice of helpers in
  `AKHelpers.swift`. Source: `github.com/AudioKit/AudioKit` @ `v4.9.2` (`03fecf80`, recorded in
  `.audiokit-revision`). Upstream copyright headers are intact; licence in `LICENSE-AudioKit`.
- **Written by us** — `AKLog.swift`, `AKSettings.swift`, `AKTypes.swift`, `include/AKInterop.h`.

## Why the names still start with `AK`

See **ADR-009**. Keeping upstream names means ~190 call sites across Synth One port with no edits at
all — 120 `AKLog`, 34 `AKTuningTable`, 29 `AKSettings`, 11 `AKTable`. Every avoided edit is an
avoided bug, and it keeps `diff upstream/ Sources/` readable, which `CLAUDE.md` asks for.

`SynthOneCore` re-exports this module (`@_exported import S1Support`), so a ported Synth One file
only needs `import AudioKit` → `import SynthOneCore`.

## What was ported

| From AudioKit | Files | Notes |
|---|---|---|
| `Common/Internals/Microtonality/` | all 9 | ~1,000 lines of tuning maths — the Tunings panel depends entirely on this |
| `Common/Internals/Table/AKTable.swift` | 1 | must decode Synth One's shipped band-limited wavetable JSON |
| `Common/Internals/AudioKitHelpers.swift` | 3 fragments | `ClosedRange.clamp`, `Array.init(zeros:)`, and the `❗️` prefix operator |

**Deliberately not ported:**
- `AKTable+AdditiveSynthesis.swift` — Synth One defines its own `saw`/`square`/`triangle` in
  `AKTable+AKSynthOne.swift`. Add it only if P1-5 turns out to need it.
- `AKTable+AKAudioFile.swift` and the `init(file: AKAudioFile)` convenience initialiser — pull in
  `AKAudioFile`, which is out of scope and unused by Synth One.
- Session handling from `AKSettings` — an AU extension must never configure the audio session.
  That split becomes `S1AudioSession` at P2-2.

## ⚠️ AudioKit 4.9.2 does not compile under a modern Swift

Three genuine type errors had to be fixed before this code would build at all. Each is a *narrowing*
bug where upstream mixes integer and floating-point arithmetic. This is worth knowing: it retroactively
justifies ADR-002 — there was never a version of "just keep using AudioKit 4.9.2" that was going to work.

| File | Upstream | Fixed to | Consequence if fixed carelessly |
|---|---|---|---|
| `AKTuningTableBase.swift` | `exp2((noteNumber - 69) / 12)` | `exp2(Double(noteNumber - 69) / 12.0)` | `noteNumber` is `Int`, so upstream is **integer division**. Casting only the *result* would collapse all 128 notes onto ~11 frequencies |
| `AKTuningTable+EqualTemperament.swift` | `Frequency(i) / npo` | `Frequency(i) / Frequency(npo)` | `Double / Int` |
| `AKTable.swift` (`phaseOffset`) | `Int(phase * count)` | `Int(phase * Float(count))` | `Float * Int` |

Each fix carries a `PORT FIX:` comment at the site, and each has a regression test in
`Tests/SynthOneTests/S1SupportTests.swift` — notably `testBaseClassDefaultIs12ETNotIntegerDivision`,
which asserts adjacent semitones are distinct.

**Also required:** `import Foundation` added to 7 files (they relied on AudioKit's umbrella header).
No other changes were made to ported code.

## Verified

16 tests green, covering:
- 12-TET: A4 = 440 Hz, middle C = 261.6256 Hz, octaves double across 24–96, semitone ratio = 2^(1/12)
- The base-class 12-TET regression described above
- 19-tone equal temperament — strictly ascending, `npo` correct
- **Scala import** of a 5-limit just major scale, checked against exact ratios (9/8, 5/4, 4/3, 3/2, 5/3, 15/8)
- `AKTable` decoding a **real shipped band-limited wavetable** from `upstream/` (4,096 points), plus
  a Codable round trip

## Updating

Re-copy from the same AudioKit tag, then re-apply the three PORT FIXes and the `Foundation` imports.
`S1SupportTests` must stay green — especially the base-class 12-TET test.
