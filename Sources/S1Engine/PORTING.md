# S1Engine — the portable engine

The C++17 engine both product families build from (ADR-057): the Catalyst app and AUv3 through
XcodeGen, and the JUCE VST3/AU/standalone through CMake. **No Apple headers, no Objective-C** —
`Tests/Engine/NoAppleHeaders.cmake` fails the build's tests if any appears here or in
`Sources/Soundpipe`.

```bash
export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)   # macOS only; see "Gotchas"
cmake -S . -B build/engine && cmake --build build/engine && ctest --test-dir build/engine --output-on-failure
```

## What is here, by task

| Task | What arrived | From |
|---|---|---|
| X1-1 | `soundpipe` (CMake target over `Sources/Soundpipe`, compiled in place, `NO_LIBSNDFILE=1` as in `project.yml`) and `s1engine` with `S1EngineInfo` | new |
| X1-2 | `Kernel/S1HeldNotes.hpp`, `Kernel/S1KernelListener.hpp` (ADR-066) | new |
| X1-3 | **the kernel** — `Kernel/`, `Note State/`, `Sequencer/`, `Rate/`, `S1Parameter.h` — as `.cpp`; `S1EngineTypes.h`, `Kernel/S1KernelBase.hpp`, `Kernel/S1DSPKernel+events.cpp` (ADR-067) | `git mv` from `Sources/SynthOneCore/DSP`; history follows the files |
| X1-4 | `Tunings/` — `S1TuningTable` (AKTuningTable's table), `S1Scala` (the product's .scl parser), `S1FactoryTunings.cpp` (**generated** from the Swift list by `TuningFixtureTests`; `Scripts/write-tuning-fixtures.sh`) (ADR-068) | `Sources/S1Support/Microtonality`, `Sources/SynthOneCore/Tunings/Model` — ported, the Swift stays and stays the reference |
| X1-5 | `Presets/S1Preset` — transcribed from `Preset.swift`, `Preset+Synth.swift`, `saveValuesToPreset`; `third_party/nlohmann/json.hpp` 3.11.3 (MIT) (ADR-069) | `Sources/SynthOneCore/Presets` — the Swift stays and is the reference; `Scripts/write-preset-fixtures.sh` |
| X1-6 | `Wavetables/S1Wavetables` — the 52 oscillator tables and 13 band frequencies from the same JSON, through a `Source` callback; the kernel's destructor and `init()` free what they allocate (ADR-070) | `Sources/SynthOneCore/DSP/S1Wavetables.swift` — the Swift stays and is the reference; the JSON stays in `Sources/SynthOneCore/DSP/BandlimitedWavetables` |
| X1-7 | `Kernel/S1DSPKernel+prepare.cpp` (`prepareToRender`, out of the AU's `allocateRenderResources`); `Tests/Engine/GoldenHarness.cpp` + `WavFile.hpp`; `-ffp-contract=on`; the sanitizer CI job (ADR-071) | `S1AudioUnit.mm`; the recipe from `Tests/SynthOneTests/GoldenRenderTests.swift`, which stays |

## The engine's vocabulary (X1-3)

`S1EngineTypes.h` is plain C and self-contained apart from `S1Parameter.h`, which it includes by
bare name — the two are siblings here and in the framework's flattened `Headers/` (ADR-012), so
one include line serves both worlds. `S1ParameterAddress`/`S1ParameterValue`/`S1FrameCount` have
the widths of the AudioToolbox types they stand in for, `S1ParameterUnit` reuses
`AudioUnitParameterUnit`'s values, and `S1MIDIEvent` holds the two fields the kernel reads of an
`AUMIDIEvent`, so `S1KernelAUAdapter` (in `S1AudioUnit.mm`) converts by assignment.

`S1Event` is a parameter change or a MIDI message at a sample offset;
`S1DSPKernel::processWithEvents(frames, events, count)` cuts the cycle at each offset exactly as
Apple's `DSPKernel::processWithEvents` cuts it at `AURenderEvent`s (with the P4-2 clamps). The AU
keeps using Apple's splitter through the adapter, so its path is byte-for-byte what it was; JUCE
will feed `S1Event`s. `Tests/Engine/KernelEventTests.cpp` plays a note from a MIDI event at sample
128 of 256 and measures silence before it and sound after.

The kernel needs its 52 wavetables before the first `process` — `initializeNoteStates` hands them
to `sp_oscmorph2d_init` — so a host without them crashes on the first frame, not on the first
note. The engine test fills them with sines; the loader arrives at X1-6.

## Changes the compilers asked for (X1-3)

All marked `PORT` in the source. GCC and MSVC found them, one CI run each; Apple's libc++ had
hidden every one.

| Change | Where | Why |
|---|---|---|
| `nil` → `nullptr` | `Kernel/S1DSPKernel+process.cpp`, `Note State/S1NoteState.cpp` | Objective-C's null in C++ files |
| `BOOL` → `bool`, `UInt32` → `uint32_t` | `Sequencer/S1Sequencer.cpp`, `Kernel/S1DSPKernel.hpp` | Foundation typedefs |
| Standard headers spelled out (`<memory>`, `<functional>`, `<cmath>`, `<algorithm>`, `<cfloat>`, …) | `Kernel/S1KernelBase.hpp`, `Sequencer/S1Sequencer.cpp`, `Kernel/S1DSPKernel+tapers.cpp` | libc++ supplies them transitively; libstdc++ and MSVC do not |
| An include guard | `Sequencer/S1SeqNoteNumber.hpp` | Included twice once the sequencer and arpeggiator headers meet in one file |
| `_USE_MATH_DEFINES` | `CMakeLists.txt` (MSVC) | `M_PI` in the LFO code |
| `S1_PARAMETER_ENUM` | `S1Parameter.h` | `enum_extensibility(open)` is Clang's; Swift keeps seeing the open enum, GCC and MSVC see an int-backed enum |


## Rules

- **No value-changing float options.** No `-ffast-math`, no `/fp:fast`; `-ffp-contract=off` and
  `/fp:precise` are set. The goldens compare this build's output with the Xcode build's.
- **Soundpipe is listed, not globbed,** in `CMakeLists.txt`. A new module must be added there and
  to `Sources/Soundpipe/VENDORING.md`.
- **Warnings are errors in `s1engine`**, and off in `soundpipe` (vendored C, as in Xcode).

## Gotchas

- **CMake cannot link with the Command Line Tools SDK on this machine.** `/usr/bin/cc` picks
  `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`, whose `libSystem.tbd` names an
  architecture (`arm64e.x1-macos`) the linker rejects — "tapi error: malformed file", reported as
  "the C compiler is not able to compile a simple test program". Export `SDKROOT` to Xcode's SDK
  first. CI runners are unaffected.

## Tunings (X1-4)

The Swift tuning code is the reference and is not removed; `S1TuningTable` and `S1Scala` are
line-for-line ports, and `S1FactoryTunings.cpp` is generated from `Tunings+DefaultTunings.swift`.
`TuningFixtureTests` (Xcode) writes `Tests/Engine/Fixtures/factory-tunings.txt` and the generated
file in write mode and fails in check mode when either is stale; `TuningTableTests` (CMake) reads
the fixture and reports how many of the 194 tables are bit-exact (all of them, on every OS so
far). **`s1::powerOfTwo`, not `pow(2, x)`**: LLVM turns the latter into `exp2`, one bit off libm's
`pow` for some cents values, and the Swift gets `pow`.

## Presets (X1-5)

`s1::Preset` is a transcription of the Swift (a script emitted it from the three source files;
the ADR says how). `PresetFixtureTests` (Xcode) writes `Tests/Engine/Fixtures/factory-presets.txt`
— every factory preset's decoded fields and its 150 values after `apply`, in bank order on one
synth — and fails in check mode when it is stale; `PresetTests` (CMake) reads it and reports
mismatches (0 of 695 on every OS). **`std::fabs`, never `abs`, on a float**: libstdc++'s
unqualified `abs(float)` is `abs(int)`, and it cost 2,513 wrong tempo-synced values before it was
found. The engine's JSON is nlohmann/json; `Preset::toJSON` writes exactly `JSONEncoder`'s keys.

## Wavetables (X1-6)

`s1::Wavetables::loadFromDirectory(dir)` (or `load(source)` with any name → JSON text callback),
then `apply(kernel)` **after the kernel is constructed and before its first `process()`** — the
kernel crashes on a note without its tables. One value serves every kernel. `WavetableFixtureTests`
(Xcode) writes `Tests/Engine/Fixtures/wavetables.txt` (size + FNV-1a 64 of the bit patterns per
table); `WavetableTests` (CMake) reports 52 of 52 exact on every OS and makes and destroys ten
kernels. **The kernel now frees what it allocates** (`PORT FIX`, ADR-070): upstream's destructor
was `= default` and `init()` dropped the note states' modules — 79.6 MB over eleven kernels under
`leaks`, 0 after. To check a test that makes kernels: `leaks --atExit -- build/engine/Tests/Engine/<test> <args>`.

## The golden harness (X1-7)

`GoldenHarness <Tests/Goldens> <bank dir> <wavetable dir>`: the twenty goldens through this
directory alone. **Hosting the engine, in order:** construct `S1DSPKernel`; `s1::Wavetables::apply`;
`prepareToRender(channels, sampleRate)` (again on every sample-rate change; it carries parameters
and tuning across `init`); `s1::Preset::apply`; then per block `setOutput` + `processWithEvents`.
The harness's `makeEngine` is the reference for that order.

- **Apple Silicon: bit-exact or fail** (`--require-exact`). Elsewhere: relative RMS ≤ 3.16e-3
  (−50 dB) and ≤ 1 sample in 200 over 0.001. Measured on Linux/Windows: worst 6.9e-4.
- **`-ffp-contract=on` is part of the sound.** It is what Xcode has always compiled with; `off`
  reproduces 3 of 20 goldens on this Mac. `-DS1_FP_CONTRACT=off` is for studying what a machine
  without FMA does, never for shipping.
- One-sample differences of ~0.02 off the Mac are the **bit-crusher's sample-and-hold** landing a
  sample over (a float counter, `exp2(log2(rate))`); read them with `--list-differences` /
  `--write-renders <dir>` before suspecting anything else.
- `GoldensReject-*` tests render with a deliberate fault and must be *rejected*: if you loosen the
  criterion, they tell you what you stopped catching.
- The `sanitizers` CI job runs everything under ASan/LSan/UBSan. RTSan waits for X2 (Clang 20).

## Hosted by JUCE (X2-1)

`Sources/S1Plugin` hosts this directory in the harness's order and is held to it sample for sample
by `Tests/Plugin/PluginRenderTests` (ADR-072). What that test found about *this* code:

- **Upstream's render depends on where `process()` calls are cut — a lot, for arpeggios**
  (ADR-072 found it, ADR-074 measured and settled it). `process()` frees released voices once per
  call, and `turnOnKey` hands a still-sounding key its old voice back, state and all; so a
  retriggered note gets a continuing or a fresh voice according to the host's buffer boundary.
  Against the goldens upstream's path is 20/20 exact at 512 and 16/20 *within tolerance* at 64,
  worst relative RMS 0.73. **`freeReleasedVoicesEveryFrame`** moves the same check to every frame
  (= upstream in 1-frame buffers, proved by `GoldenHarness --check-block-independence`); the JUCE
  plugin sets it, the Mac products do not (the goldens are theirs). With the option off,
  exactness is only meaningful between two renders cut identically.
- `GoldenHarness --block-size N` plays the goldens' performance in N-frame blocks, notes on the
  goldens' samples; `--free-voices-every-frame` sets the option. Neither goes with `--require-exact`.
- **`prepareToRender` carries what each parameter was set to** (`PORT FIX`, X2-2, ADR-073).
  Upstream saved `parameters` across `init`; for the 45 smoothed parameters that is the glide's
  position, so a value set just before allocation — a host restoring a session — was lost. It
  saves `getSynthParameter` (the target) now. Equal whenever nothing is gliding, so the goldens
  and the Mac tests see no change. Still upstream's: after any `init` the smoothed parameters
  glide up from 0 (ADR-013).
- **What a preset makes of the 150 values depends on the ORDER of `Preset::apply`, and on what was
  there before** (X2-5, ADR-076). `delayTime` is written while the previous sync setting stands
  and is quantised by it, before the preset's own `tempoSyncToArpRate` arrives. To know a preset's
  values, apply it to a new kernel and read them back (`S1PluginState.cpp` does); never map fields
  to parameters one by one. `Preset::capture` has a form that reads from a function, for hosts
  that may not touch the kernel from the saving thread. `frequencyA4` is stored and read by nothing.
- **`prepareToRender` empties the host-MIDI router's keys** (`PORT FIX`, X2-10, ADR-081):
  `init` drops the voices and held notes, and a router that still held a key swallowed that
  key's next note-on. Every re-prepare — a device change in a standalone, a host changing its
  sample rate — goes through it. Settings (channel, omni, octave, hold) are kept.
- **`init` re-makes the three compressors** (`PORT FIX`, X2-9, ADR-080). Upstream makes them in
  the kernel's constructor, where `sp_compressor_init` fixes their time constants to the
  constructor's sample rate; a kernel constructed at 44.1 kHz and prepared at 96 kHz — what every
  host does — compressed 2.2× too fast. Anything else that takes `sp->sr` at construction and is
  not re-made in `init` has the same fault: look there first when a render differs between a
  kernel made at the rate and one prepared to it. (`PluginRender` compares exactly those two.)
- **"Init" is the factory bank `User`'s one preset, not `s1::Preset()`.** The model's bare
  defaults are a different sound, 28 parameters away (bend range 0, compressor ratios clamped
  from 0, tempo sync on); the golden "User--Init" is the shipped one.
- **Nothing under `process` / `processWithEvents` allocates, and a job proves it** (X2-8,
  ADR-079): `-DS1_RTSAN=ON` (Clang 20+) marks them `[[clang::nonblocking]]` and every test runs
  under `-fsanitize=realtime` — `Scripts/validate-linux.sh rtsan`. Two `PORT FIX`es came of its
  first run: **`prepareToRender` makes the voices** (upstream made them in the first `process`
  call: some ninety `malloc`s in a host's first render cycle), and `S1Sequencer`'s last-notes
  list is a vector at a fixed capacity (it was a `std::list`: a node per arpeggio note). Both
  bit-exact against the goldens. Call `prepareToRender` AFTER the wavetables are applied — it
  always needed them (`updateWavetableIncrementValuesForCurrentSampleRate`), and now the voices do.
- **Wrap the render call in flush-to-zero** (X2-7, ADR-078). The engine does not set a
  floating-point mode — it is per thread and the host's to own — and it does need one: the effects
  run without notes, decay into subnormals and stay there (output parked at 1.4e-45), 1.15–1.8×
  the cost of silence on x86, ~5% on Apple Silicon. JUCE: `juce::ScopedNoDenormals`; the AU:
  `S1ScopedFlushToZero` (`fesetenv(FE_DFL_DISABLE_DENORMS_ENV)`); CoreAudio's render thread does
  not do it for you (probed). The goldens are bit-exact under it: `GoldenHarness --flush-to-zero`
  (macOS), the CTest `GoldensFlushToZero`.
- **Tempo and transport: two calls, every render cycle, before the cycle's first frame** —
  `handleTempoSetting(bpm)` then `handleTransportState(isMoving)` (ADR-025, ADR-077). Both act on
  a difference only, so calling them every cycle is the intended use; do not call either when the
  host gives no value. The tempo is compared with `arpRate` as the kernel holds it, so a host's
  tempo corrects a preset's. **A stop is an all-notes-off** (`PORT FIX`, X2-6): it releases the
  voices — running each polyphonic voice's envelopes once with the gate down, as `turnOffKey`
  does; without that a voice already under the release threshold is freed with its envelope held
  open and its next note is silent — forgets the router's keys (`S1HostMIDI::transportDidStop`,
  CC123's lines) or calls `stopAllNotes`, and rewinds the sequencer. The sequencer counts beats
  and steps every `arpSeqTempoMultiplier` of a beat: 0.25 is a sixteenth note, which upstream's
  readout names "1/4 note". **A host's tempo keeps the NOTE VALUE of what is synced to it**
  (ADR-082; upstream re-quantised by time, and a far jump changed the note). For the `arpRate`
  parameter that is `tempoParameterKeepsNoteValues` — off by default, on in the JUCE plugin — and
  `s1::Preset::apply` always switches it off while it runs: a preset's `arpRate` is not a tempo
  change, and upstream's re-quantising is what reads its times back as notes (ADR-076).
- **Do not take parameter identifiers from `presetKey`.** 19 differ from the enum names, the
  compressor ones have spaces, and `compressorMasterMakeupGain` is there twice. The preset JSON
  and the AUv3 use them; the JUCE plugin's IDs are the enum names (ADR-058).
- `setSynthParameter(frequencyA4, x)` stores `truncf(x)`; the five rate-like parameters are
  quantised or re-driven by the kernel (ADR-022). A host of the engine must read those back.
- The plain MIDI path (`handleMIDIEvent` with `hostMIDI` disabled) starts a voice for a note-on
  with velocity 0. No product uses that path for host MIDI: the AUv3 and the JUCE plugin both
  enable `S1HostMIDI`, which reads it as a note-off.
- **Hosting `S1HostMIDI`** (X2-4, ADR-075): `hostMIDI.enabled = true`; once per render cycle
  `hostMIDI.beginRenderCycle(kernel)` *before* `processWithEvents`; settings through its atomics;
  a `listener` for what it forwards (controllers, program change, the held-key set), called on
  the render thread. `Tests/Engine/HostMIDITests.cpp` is the reference host and holds the router
  to `Fixtures/host-midi.txt` — what the standalone's Swift chain played, written by
  `HostMIDIParityTests` (`Scripts/write-host-midi-fixtures.sh`).
