# AudioKit 4.9.2 API surface to replace

Measured against `upstream/` @ `6466a37`. This is the complete list of what we owe ourselves once
the pod is dropped. Counts are reference-site counts, not file counts.

## Swift API (from `AudioKit` / `AudioKitUI`)

| Symbol | Uses | Replacement plan | Task |
|---|---:|---|---|
| `AKLog` | 120 | ✅ **done** — `os_log` wrapper, signature preserved | P1-3 |
| `AKTuningTable` | 34 | ✅ **done** — all 9 Microtonality files ported; needed 2 type fixes | P1-3 |
| `AKSettings` | 29 | ✅ **done** — 8 members; session handling deferred to `S1AudioSession` | P1-3 / P2-2 |
| `AKPolyphonicNode` | 19 | Drop. In `AVAudioEngine` the AU *is* the node; `AKSynthOne` becomes a plain wrapper | P2-1 |
| `AKSynthOne` | 15 | Ours already (`DSP/AKSynthOne.swift`) — just rebase off `AKPolyphonicNode` | P2-1 |
| `AKTable` | 11 | ✅ **done** — ported; it is a Codable **class**, not a value type (wavetables are JSON) | P1-3 |
| `AKMIDIStatusType`, `AKMIDIListener`, `AKMIDIStatus`, `AKMIDIControl`, `AKMIDIEvent` | ~14 | Reimplement over CoreMIDI, preserving the `AKMIDIListener` protocol shape so call sites don't move | P3-4 |
| `AKAudioFile`, `AKNodeRecorder` | 7 | `AVAudioFile` + an `installTap` recorder | P2-3 |
| `AKMixer`, `AKNode` | 4 | `AVAudioMixerNode` | P2-1 |
| `AKTry` | 2 | Obj-C exception bridge; likely deletable | P2-1 |
| `AKComponent`, `AKCallback` | 2 | Protocol/typealias, trivial | P1-3 |
| `AKAudioUnitType` | 3 | typealias | P1-4 |

## AudioKitUI views

Already vendored in-tree (**no work**): `AKTouchPadView`, `AKVerticalPad`, `AKLinkButton`.
`KeyboardView` is also local (`Keyboard/UI Components/`).

Still coming from the pod, must be ported (all are small UIKit views; port from AudioKit 4.9.2 source):

- `AKADSRView` — envelope editor, drag-to-edit
- `AKNodeOutputPlot` — output waveform display
- `AKBluetoothMIDIButton` — **iOS-only concept.** Drop on macOS; stub it out (P3-2)
- `AKKeyboardDelegate` / `AKKeyboard` protocols — protocol declarations only

## Obj-C / C++ layer

| Symbol | Uses | Replacement plan | Task |
|---|---:|---|---|
| `AKSynthOneRate` | 45 | Local header already (`DSP/Rate/`) — **no work** | — |
| `AKSoundpipeKernel` | 5 | ✅ **done** | P1-4 |
| `AKAudioUnit` | 2 | ✅ **done** — plus `DSPKernel`, `BufferedAudioBus`; one upstream bug fixed | P1-4 |
| `AKSettings` (ObjC) | 3 | ✅ **done** — via C storage bridge (ADR-010) | P1-4 |
| `AK_ENUM`, `AKInterop.h` | 4 | ✅ **done** | P1-3 |
| `AKOutputBuffered` | 1 | ✅ **done** | P1-4 |

## Soundpipe modules required (vendor as C, MIT)

`sp_adsr` · `sp_butbp` · `sp_buthp` · `sp_compressor` · `sp_crossfade` · `sp_delay` · `sp_fosc` ·
`sp_ftbl` · `sp_gen_sine` · `sp_moogladder` · `sp_noise` · `sp_osc` · `sp_oscmorph2d` · `sp_pan2` ·
`sp_phaser` · `sp_phasor` · `sp_port` · `sp_revsc` · `sp_vdelay`

Plus the in-tree `DSP/Kernel/oscmorph2d.c`.

**Resolved at P1-5 (ADR-011), correcting P1-2.** `sp_oscmorph2d` is an **AudioKit** addition, not a
Synth One one, and the in-tree `.c` is a stale non-band-limited copy — **not** the implementation.
The real module lives in `AudioKit/Core/SoundpipeExtension/` and is band-limited. Two further modules are required transitively and were not
on this list: **`base`** (`sp_auxdata_*`) and **`randmt`** (called by `ftbl.c`). All 21 entry points
verified present in the built archive. See `Sources/Soundpipe/VENDORING.md`.

## Not a dependency (good news)

`DSP/TAAE/` — The Amazing Audio Engine 2 primitives (`AEArray`, `AEMessageQueue`,
`AEMainThreadEndpoint`, `AEAudioThreadEndpoint`, `AEManagedValue`, `AETime`, `AEUtilities`,
`AEWeakRetainingProxy`) are already vendored in the repo, MIT, and platform-agnostic. These
provide the lock-free main↔render thread messaging the kernel depends on. **Port as-is.**
