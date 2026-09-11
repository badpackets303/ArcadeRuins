# DSP — porting record (P1-5)

Synth One's synthesis engine, ported out of `upstream/AudioKitSynthOne/DSP/` into
`Sources/SynthOneCore/DSP/`. **The kernel compiles on macOS.**

## What was ported

| | |
|---|---|
| `Kernel/` | `S1DSPKernel` — 12 `.mm` partials + `.hpp` + `S1DSPCompressor.hpp` |
| `Audio Unit/` | `S1AudioUnit.h/.mm` |
| `Note State/` | `S1NoteState.hpp/.mm` |
| `Sequencer/` | `S1Sequencer`, `S1Arpeggiator`, `S1ArpModes`, `S1SeqNoteNumber` |
| `Rate/` | `AKSynthOneRate.h`, `S1Rate.hpp` |
| `TAAE/` | 8 classes (lock-free main↔render messaging), unchanged |
| | `S1Parameter.h` (150 parameters), `BandlimitedWavetables/` (54 JSON, bundled as resources) |

`Kernel/oscmorph2d.c` was **not** ported — see ADR-011; it is a stale copy and the real module is
vendored in `Sources/Soundpipe/`.

## How little had to change

The base layer built at P1-4 was shaped to accept this code, and it did. `S1DSPKernel.hpp` keeps
`#import "AudioKit/AKSoundpipeKernel.hpp"` verbatim, `S1Parameter.h` keeps
`#import "AudioKit/AKInterop.h"`, and `S1AudioUnit.mm` keeps `#import "AudioKit/BufferedAudioBus.hpp"`
— all resolved by putting our headers under `AudioUnitBase/AudioKit/` and that directory on the
header search path.

**Total edits to ported DSP sources: 8 lines across 8 files.**

| Change | Files | Why |
|---|---|---|
| Removed `#import <AudioKit/AudioKit-Swift.h>` | 7 | **Vestigial** — verified by grep that none of these files reference any `AK*` symbol. The only apparent use, `AKPolyphonicNode` in `S1DSPKernel+startStopNotes.mm`, is inside a comment |
| `AKSettings.{rampDuration,sampleRate,channelCount}` → `ak_settings_*()` | `S1AudioUnit.mm` | ADR-010 — the Swift class has no Obj-C interface across the static-library boundary |

Nothing else. No logic was touched.

## What P1-5 pulled in

- **`TPCircularBuffer`** — TAAE's `AEMainThreadEndpoint`/`AEAudioThreadEndpoint` import
  `AudioKit/TPCircularBuffer.h`. Vendored from AudioKit into `AudioUnitBase/`. Only the base buffer
  is used; the `+AudioBufferList` and `+Unit` variants are not.
- **`pow2`** — used in `S1DSPKernel+toggleKeys.mm` as a velocity curve, defined in AudioKit's
  `AKBankDSPKernel.hpp`. **It squares its argument; it is not 2^x.** Reading the name literally would
  have changed how the instrument responds to velocity. Added to `AudioUnitBase/AudioKit/AKDSPKernel.hpp`
  with a comment saying so.
- **`gnu11` / `gnu++17`** — TAAE uses `typeof()`. The project had been set to strict `c11`, which
  rejected it. Apple's own default is `gnu11`.

## Not yet ported (deliberately)

The Swift half of `DSP/`: `AKSynthOne.swift`, `AKTable+AKSynthOne.swift`, `Conductor.swift`,
`Conductor+Platform.swift`, `S1Control.swift`, `S1TuningTable.swift`, `SDSustainer.swift`,
`AudioRecorder.swift`. These depend on `AKPolyphonicNode` and the AudioKit engine, which are P2-1's
business. `S1AudioUnit` itself is C++/Obj-C and is here.

## Verified

Framework contains 62 `S1DSPKernel` symbols, 32 objects, and 55 bundled wavetable resources.
22 tests green; the app builds; `auval` still passes.

As of P1-6 this is verified by rendering, not by inspection. See below.

## P1-6 — edits to make `S1AudioUnit` reachable from Swift

Two more lines, both in headers, both marked `PORT FIX` at the site. Running total: **10 lines
across 9 files.**

| Change | File | Why |
|---|---|---|
| `#import <AudioKit/AKAudioUnit.h>` and `#import "S1Parameter.h"` → `<SynthOneCore/...>`, `#pragma once` → `S1_AUDIO_UNIT_H` guard | `Audio Unit/S1AudioUnit.h` | The header is public now, and Xcode flattens public headers into `Headers/` |
| `#import "AudioKit/AKInterop.h"` → `<SynthOneCore/AKInterop.h>`, `#pragma once` → `S1_PARAMETER_H` guard | `S1Parameter.h` | Same, plus: `#pragma once` keys on file identity, and inside the framework build this header is legitimately reached both from the source tree and from the copied public header |

Our own `AKInterop.h` shim was also corrected — it had spelled `AK_ENUM` as `NS_ENUM`, which is not
what AudioKit does and is not interchangeable with it. See ADR-012.

## P1-6 — what rendering actually showed

`Tests/SynthOneTests/S1AudioUnitRenderTests.swift` drives `S1AudioUnit` with no engine and no UI:
create → load 52 wavetables → `allocateRenderResources` → `startNote` → pull `internalRenderBlock`.

**It works.** A note in produces audio out, in tune, polyphonic, releasing on note off, surviving
repeated allocation. An independent spectral analysis of the written WAV puts A3/C4/E4/A4 at
219.95 / 261.60 / 329.55 / 439.90 Hz — within 0.1 Hz of 12-ET.

Two things the harness had to learn, both of which will bite anyone writing the P2-1 engine:

- **Wavetables must be loaded before `allocateRenderResources`, not after.** `S1NoteState::init`
  hands `ft_array` straight to `sp_oscmorph2d_init`, and `allocateRenderResources` walks every table
  to rescale `sicvt`. Both dereference tables `setupWaveform` has to have created. `destroy()` does
  *not* free them, so loading them once outside the allocate/deallocate cycle is correct.
- **A note struck immediately after allocation sweeps up into tune over ~0.8 s.** Upstream
  behaviour, mechanism and reasoning in **ADR-013**. It is pinned by a test rather than fixed.

## P4-3 — the AU parameter path, which upstream never implemented

Two files changed, both marked `PORT FIX (P4-3)` at the site. Running total: **12 lines across
10 files** plus the parameter-tree edit below. Full reasoning in **ADR-022**.

| Change | File | Why |
|---|---|---|
| `startRamp` was `{}`; it now bounds-checks the address and calls `setSynthParameter` | `Kernel/S1DSPKernel+parameters.mm` | This is the render-thread end of host automation. Empty meant every automation move was received and discarded — `///auv3, not yet used` |
| `dependentParameters:nil` → the four tempo-synced addresses, for `arpRate` and `tempoSyncToArpRate` only | `Audio Unit/S1AudioUnit.mm` | `_setSynthParameterHelper` re-drives `lfo1Rate`, `lfo2Rate`, `autoPanFrequency` and `delayTime` when either changes, so one host move alters five DSP values |

`duration` is deliberately dropped rather than honoured: the kernel already smooths, per sample,
with `sp_port` on the 46 parameters whose `usePortamento` is true. `notifyMainThread` is
deliberately left `true`: for the eight dependent parameters `_rateHelper` **quantizes** the value
it is handed, so that notification is the only report of which value actually took effect.

**Do not test this through `internalRenderBlock`.** `scheduleParameterBlock` hands its event to the
framework, and it is `AUAudioUnit.renderBlock` that drains the pending list into
`internalRenderBlock`'s `realtimeEventListHead`. Driving `internalRenderBlock` directly delivers no
scheduled parameters at all and looks exactly like `startRamp` still being a no-op.

**An upstream quirk found while reading, and left alone.** `_setSynthParameterHelper` calls
`updatePortamento(getParameter(portamentoHalfTime))`. `portamentoHalfTime` has `usePortamento`, and
`getParameter` returns `parameters[i]` — the *ramping* value — rather than the portamento target,
so setting it applies the previous value. Preset load goes through `setupParameterTree`, which
writes both, so it is correct there. Fixing it would move the golden renders; not P4-3's call.

## ADR-031 — host MIDI in the plugin

Three edits to ported code, each marked at the site. Everything else is new code of ours
(`S1HostMIDI`) or new API on `S1AudioUnit` that upstream's code does not call. Full reasoning in
**ADR-031**.

| Change | File | Why |
|---|---|---|
| `handleMIDIEvent` hands the event to `hostMIDI` when routing is on (`PORT FIX`) | `Kernel/S1DSPKernel+MIDI.mm` | Upstream's body plays note on/off and CC123 and nothing else. The plugin needs the standalone's whole MIDI chain, on the render thread |
| `S1HostMIDI hostMIDI` member, and its import (`PORT`) | `Kernel/S1DSPKernel.hpp` | The router's state lives as long as the kernel, which is created once per unit |
| The render block polls `AEMessageQueue` and runs the router's once-a-cycle checks before `processWithEvents` | `Audio Unit/S1AudioUnit.mm` | Keys the interface queues are applied on the thread that plays host notes. Polling an empty queue is all the standalone pays |

New, ours: `Kernel/S1HostMIDI.hpp/.mm` — the render-thread port of `Manager+MIDIListener` →
`KeyboardView+Touches` → `Manager+Keyboard` → `SDSustainer`. **It has a Swift twin.** Change one and
`HostMIDIParityTests` fails until the other matches. There is no velocity-sensitivity step in either:
both products always play the velocity they receive (ADR-032).

New API on `S1AudioUnit`: `routesHostMIDI` (off by default; only `SynthOneApp.makePluginAudioUnit`
turns it on), `hostMIDISettings`, the `…OnRenderThread` key and reset methods, the test-only trace,
and two optional `S1Protocol` messages with their relay and passthrough methods.

**The standalone runs none of it.** Its unit never enables routing, nothing queues keys to it, and
no host calls `handleMIDIEvent` there. The golden renders do not move.

**Test host MIDI through `renderBlock`, as with parameters (P4-3).** `scheduleMIDIEventBlock` hands
the event to the framework, and only `AUAudioUnit.renderBlock` delivers it.
