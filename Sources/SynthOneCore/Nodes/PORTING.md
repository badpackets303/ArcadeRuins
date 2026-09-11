# SynthOneCore/Nodes — porting record (P2-1)

The audio-graph layer: what replaces AudioKit's `AudioKit` global, `AKNode`, `AKPolyphonicNode`,
`AKMixer` and `AKComponent`.

## Why this is not in `S1Support`

It was, for about an hour, and the build broke in a way worth knowing about. `AKSynthOne` is `@objc`
and subclasses `AKPolyphonicNode`, so Xcode emitted that superclass into `SynthOneCore-Swift.h`
along with `@import S1Support;` — and `S1Support` is a **static library**, so no consumer of the
framework can resolve it.

The rule that came out of it (ADR-014):

> `S1Support` is the value layer — tables, tunings, settings, logging. Nothing in it may appear in
> `SynthOneCore`'s Obj-C surface. Graph objects, and anything Obj-C must see, live here.

## Files

| File | Origin | Notes |
|---|---|---|
| `AKNode.swift` | AudioKit 4.9.2 `AKNode.swift` (MIT) | `AKNode`, `AKPolyphonic`, `AKPolyphonicNode`. Trimmed: the `AKOutput` connection-point DSL (Synth One builds its graph by hand), the deprecated members, `AKToggleable` (unused), and every reference to the global engine |
| `AKComponent.swift` | AudioKit `AKComponent.swift` + `AudioKitHelpers.swift` (MIT) | `AKComponent.register()`, `fourCC`, `AudioComponentDescription(instrument:)`, `AVAudioUnit._instantiate` |
| `AKMixer.swift` | stands in for `AKMixer` | Records its inputs; `S1AudioEngine` does the connecting. Synth One uses exactly one, in `Conductor.start()` |
| `S1AudioEngine.swift` | ours | Replaces `AudioKit.engine` / `.output` / `.start()`. `S1` prefix per ADR-009 |

## Deviations from upstream, and why

- **No global engine.** ADR-014.
- **`AKPolyphonicNode.tuningTable` is not `@objc`.** `AKTuningTable` is an `S1Support` type; marking
  the property `@objc` drags it into the generated header. Nothing calls it from Obj-C.
- **`AKNode.init(avAudioUnit:attach:)` lost its `attach` parameter**, and `_instantiate` no longer
  attaches. There is no singleton to attach to; `S1AudioEngine` attaches when given the node.
- **No `.loadInProcess`** in `_instantiate` — the option is *unavailable in Mac Catalyst*, which
  gets the iOS API surface. Registered subclasses load in process there regardless, but since the
  shipping AUv3 registers the same `aumu`/`ruin`/`BP03` description system-wide,
  `S1AudioEngineTests` asserts the instance really is our `S1AudioUnit` and not the installed
  extension.
- **The manufacturer code is `BP03`, not AudioKit's `AuKt`**, so the in-process node and the plugin
  describe the same instrument.

## ⚠️ Ordering that is load-bearing

`enableManualRenderingMode` must be the first thing that touches the engine — `outputNode` blocks
for **90 seconds** in a process with no output device. `S1AudioEngine` is built around this: `output`
records, `start`/`startOfflineRendering` build. **ADR-015.**

## `AKSynthOne.swift` (in `../DSP/`)

Ported with three changes, all marked `PORT`:

| Change | Why |
|---|---|
| `import AudioKit` → `import S1Support` + `AVFoundation` | the file lives inside `SynthOneCore` now, so it imports directly rather than through the framework's re-export |
| `Bundle.main` → `AKSynthOne.bundle` (3 sites) | the wavetables are framework resources; `Bundle.main` was the iOS app bundle, and is not somewhere the AUv3 could look either |
| — | nothing else. The parameter accessors, the `AVAudioUnit._instantiate` init, the note routing and the `S1TuningTable` conformance are byte-for-byte upstream |

**Not ported:** `AKTable+AKSynthOne.swift` (`saw`/`square`/`triangle`/`pwm` table generators) — it
has **no call sites** anywhere in upstream. The band-limited tables come from JSON. Grep-verified.

## Verified

`S1AudioEngineTests`: the audio unit instantiated is our own in-process subclass; wavetables resolve
from the framework bundle; the `synth -> mixer -> output` graph renders audible audio; played notes
sound at 440 / 220 / 329.63 Hz; note off releases; mixer volume reaches the output; and it all works
at 48 kHz as well as 44.1.
