# S1Plugin — Arcade Ruins as a JUCE plugin (X2)

VST3 and Standalone, built with CMake on macOS, Windows and Linux — **and an AU on macOS** since the
X3 gate (`aumu`/`ArRu`/`BP03`, ADR-092/093; `Scripts/validate-plugin.sh --au` installs it and runs
`auval`). The Catalyst app and AUv3 — "Arcade Ruins Classic", `ruin` — are not built here and do not
contain JUCE.

```bash
export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)      # this Mac only (CLAUDE.md)
cmake -S . -B build/plugin -DS1_BUILD_PLUGIN=ON
cmake --build build/plugin -j8
ctest --test-dir build/plugin                              # the engine's tests + PluginRender
open "build/plugin/Sources/S1Plugin/ArcadeRuins_artefacts/Release/Standalone/Arcade Ruins.app"
```

Nothing is installed by the build (`COPY_PLUGIN_AFTER_BUILD FALSE`). To try the VST3 in a host,
copy `ArcadeRuins_artefacts/Release/VST3/Arcade Ruins.vst3` to `~/Library/Audio/Plug-Ins/VST3/`.

## Rules

- **JUCE is fetched, never vendored.** `FetchContent`, pinned to the 9.0.2 *commit*. The JUCE 9
  EULA (§1.17) does not let the framework be distributed on its own, and the public mirror is a
  `git archive` of this tree. Licence: Starter tier (ADR-054, `NOTICE.md`). Moving to a new JUCE
  version means re-reading the EULA first.
- **The engine is hosted in `GoldenHarness`'s order** (`Sources/S1Engine/PORTING.md`): construct →
  `s1::Wavetables::apply` → parameters read and written back → Init (the parameters' starting
  values, X2-2) → `prepareToRender` (in `prepareToPlay`) → `setOutput` + `processWithEvents` (in
  `processBlock`).
  `PluginRenderTests` holds the processor to the bare engine **sample for sample**; if it fails,
  the wrapper changed the sound.
- **State is `S1PluginState`'s JSON (ADR-076). `Tests/Plugin/Fixtures/state-v1.json` is rewritten
  ONLY when a field is ADDED** (`PluginStateTests <fixture> <banks> --write-fixture`, and the diff
  must be purely additive) — **a field that changes meaning, moves or disappears gets a new format
  version and a new fixture, and the old one keeps being read.** What the fixture protects is that
  a state written by an older build still loads: whatever a state does not name stays as it was, and
  `PluginStateTests` holds a state with the field removed to that. Amended at X3-8 (ADR-090), which
  added `window.keyboardShown` — four lines, nothing else moved.
  `getStateInformation` reads host parameters and the processor's own copies, never the kernel;
  `setStateInformation` writes those and lets `deliverPendingToKernel` (top of `processBlock`,
  `prepareToPlay`) do the rest. A *preset's* values come from applying it to a scratch kernel in
  upstream's order — the order decides some of them — never field by field.
- **MIDI goes through the engine's router, `S1HostMIDI`** (ADR-075, ADR-031) — never straight to
  `startNote`. Its rules are the standalone's, held to them by `Tests/Engine/HostMIDITests` and a
  fixture the Swift parity test writes: **change the router, the Swift chain and the fixture
  together** (`Scripts/write-host-midi-fixtures.sh`). What the router forwards arrives at the
  processor's `S1KernelListener` methods *on the render thread*; the mod wheel (`S1ModWheel.hpp`)
  is done there. Nothing MIDI may hop to the message thread and back: a bounce will not wait.
- **The render must not depend on the host's buffer size** (ADR-074). The processor sets
  `kernel->freeReleasedVoicesEveryFrame`; `PluginRenderTests` holds the engine to identical samples
  at six block sizes and `GoldensBlockIndependence` holds all twenty golden presets to it. Anything
  new that happens "once per `processBlock`" and reaches the sound breaks this — do it per frame
  or not at all.
- **The host's tempo is the tempo** (ADR-077). The play head is read at the top of every
  `processBlock` — it is valid nowhere else — and given to the kernel's own `handleTempoSetting`
  and `handleTransportState` before the block's first sample. While the host has a tempo the
  `arpRate` parameter is *reported, not obeyed*: never sent to the kernel, and put back to the
  host's tempo after the render. No play head, no position or no bpm: the parameter applies (the
  standalone). A transport stop is an all-notes-off; the sequencer is not locked to the host's
  beat position (ADR-025) — an arpeggio starts on the sample its keys arrive on.
- **Presets load through a scratch kernel, never field by field, and the tuning table is not a
  preset's to change yet** (ADR-080, ADR-076). `loadPreset(preset, asEdit)`: `asEdit` for a
  person's choice (a gesture per changed parameter, so hosts record it), not for a host's program
  change. A host's programs are the 695 factory presets in the Mac AUv3's order and names —
  `Tests/Plugin/Fixtures/factory-programs.txt` is written from the Swift side
  (`Scripts/write-factory-program-fixtures.sh`); lines are only ever added at the end. User
  presets are never programs. The factory banks are the Mac app's files, linked in; do not edit
  a copy. The user's folder is `S1SharedPresets::defaultUserDirectory()`; **constructing the
  processor must never touch the disk** (hosts scan plugins), and **tests give the library a
  temporary folder before saving anything** — the default one is the owner's.
- **The standalone is JUCE's holder and window with OUR application object**
  (`S1StandaloneApp.cpp`, ADR-081): it opens every MIDI input by itself and keeps its settings in
  `<application data>/BadPackets/Arcade Ruins/`. It has no audio input. An audio device change
  reaches the processor as `releaseResources` + `prepareToPlay` at the new rate — anything that
  must outlive that lives in the host parameters and the processor's own copies, never only in
  the kernel (`PluginStandalone` holds it to this).
- **The plugin starts with the SHIPPED Init** (factory bank `User`), not `s1::Preset()`: the
  model's bare defaults are 28 parameters away from it (no bend, compressors at their stops).
- **`processBlock` begins with `juce::ScopedNoDenormals`** (ADR-078). The engine's effects run
  when no note sounds and decay into subnormals for good (it parks at 1.4e-45); unprotected that
  costs a silent instance 1.15–1.8× per block on x86. Anything else that ever renders — an
  offline preview, a second entry point — wraps its call the same way. Bit-exact: the goldens do
  not change under it.
- **Tempo changes keep note values** (ADR-082): a host's tempo always; the Tempo parameter because
  the processor sets `kernel->tempoParameterKeepsNoteValues` — AFTER Init is applied, and never
  apply a preset to the rendering kernel (presets arrive as parameter values; under a host's
  tempo `loadPreset` first moves their synced values to the host's tempo by note value).
- **Nothing on the audio thread allocates, locks or throws.** MIDI goes into a fixed
  `std::array<S1Event, 512>`; a block with more events is rendered in pieces.
- **No fast-math, no LTO flags from JUCE, `-ffp-contract=on` stays** — the engine's arithmetic is
  the goldens' arithmetic (ADR-071). This directory has no DSP of its own and should not grow any.
- **The kernel is touched only from `processBlock`** (and `prepareToPlay`, when nothing renders).
  A host writes an `S1HostParameter` from any thread; each block, values that differ from what the
  kernel was last given go in as `S1Event`s — the sync switch and tempo first. The five parameters
  the engine rewrites itself (`engineMayChange` in `S1ParameterCatalog.hpp`) are read back after
  the render and reported to the host *from the audio thread*: in JUCE's VST3 wrapper that is an
  output parameter change, where the same call on the message thread is an edit a host would
  record (ADR-073, ADR-022).
- **A parameter's ID is its `S1Parameter` enum case's name, generated by CMake from the header —
  not the kernel's `presetKey`** (19 of those differ; one is a duplicate).
  `Tests/Plugin/Fixtures/parameter-ids.txt` freezes index, ID and version hint: lines may be
  added (`PluginParameterTests <fixture> --write-fixture`), never changed. Names, readouts, tapers
  and step names in `S1ParameterCatalog.cpp` are presentation and may change.
- **The interface is laid out from `Layout/layout-spec.json`, and that file is MEASURED, never
  edited** (ADR-083). `Tests/SynthOneTests/LayoutSpecFixtureTests.swift` builds the Mac desktop
  layout at 1440 × 900 under each skin and writes every section, control (with its parameter's ID),
  plot, pad, button, label, font and colour; `Scripts/write-layout-spec.sh` runs it, and the
  normal Xcode suite fails while the file is stale. Cabinet's rectangle table is in it as the Mac
  skin has it. `s1plugin::LayoutSpec` (no JUCE) reads it strictly; `S1LinkedLayoutSpec()` is the
  linked-in copy, for the editor only. **Never type a frame, a colour or a binding in C++** —
  change the Mac layout and regenerate. `Scripts/check-layout-spec.sh` holds the file to the
  RUNNING Mac app (every frame within 1 point) and draws the wireframe over its render.
  26 parameters have no control there — `PluginLayoutSpecTests` lists them and why.
- **The controls kit is `UI/`: `s1ui::Style` draws, `S1KitControls` are the components** (ADR-084).
  `Style` is `S1DesktopStyle.swift` ported function for function and owns no colour or size — the
  specification's palette, dress and accent. Every control edits through a
  `juce::ParameterAttachment` **as a gesture** (begin / values / end; a click is one complete
  gesture): never `setValueNotifyingHost` by hand, never the processor. Double-click reset, wheel,
  keys, Alt-fine, focus ring and accessibility are `ParameterControl`'s — a new control inherits
  them. **Mouse handlers only translate**: behaviour goes in a plain method (`grab` / `dragBy` /
  `letGo`, `pressAt`, `press`, `moveTo`) that `PluginControlsKitTests` can call with no window.
  `ControlsKitSheet` paints the whole kit on the specification's frames; hold it beside
  `Scripts/check-layout-spec.sh`'s Mac renders after touching any drawing. A change to how the Mac
  draws a control is ported here by hand — only the LAYOUT is generated.
- **The editor is `UI/S1PluginEditor`, and it knows no frame, colour or binding** (ADR-085):
  controls from `makeControl` on the specification's frames, a `ValueReadout` on every
  `valueFrame`, plots and pads from `makeDisplay`, toolbar / play-bar pieces from `items`; what
  never moves is one buffered `Backdrop` (Cabinet: the owner's painting, linked in as
  `ArcadeRuinsArt`). What spans controls runs from `refreshLiveState()` (a 30 Hz timer; tests call
  it): the playing step, the host-owned tempo, rate readouts, Mono, the preset's name, the scope.
  **The message thread never touches the kernel**: Panic is `requestAllNotesOff()`, a flag the
  next block turns into CC 123 through the router; the scope reads a lock-free ring the render
  fills. **The five dependent parameters sit by note value** (`dependentPositionMap`, the engine's
  own `S1Rate` arithmetic) — never map them through the host parameter's range. A piece that is
  not built yet says which task brings it (`say`); it never pretends. After touching drawing or
  layout, hold `EditorSnapshot --program …` beside `desktop_render.py` with `RENDER_SELECT` on the
  same preset: `Scripts/debug/compare_editor_render.py` gives the numbers and the side-by-side.
- **The preset browser is a model plus a view, and the banks are the PERSON'S FILES** (ADR-086).
  `S1PresetBrowser` (no JUCE) is the Mac browser's own logic — `sortPresets`, the category rows'
  numbers, New, New Bank, duplicate, the star, save, delete, reorder, rename and delete a bank,
  import and export — and `UI/S1PresetPanel` only draws it and turns clicks into its calls; a new
  operation goes in the model, where `PluginPresetBrowserTests` can drive it with no window.
  **Its first `load()` writes the twelve banks the Mac starts with into the shared folder** (about
  2 MB, once, and only when a person asks for a preset — never on a host's scan), and from then on
  a file IS the bank. **What a host stores is untouched**: `factoryProgram` still reads the banks
  linked into the binary. A preset is named by its uid, so `readFolder` gives a repeated uid a
  fresh one and writes that bank back (the shipped banks hold 670 for 695 presets). The banks'
  order is `banks.order` beside them — never a `.json`, or `userBanks()` would read it as a bank.
  **Any file dialogue is `juce::FileChooser::launchAsync`, never modal** (ADR-044).
- **The tunings are a model and a view too, and a preset's scale is PLAYED now** (ADR-087).
  `S1TuningLibrary` (no JUCE) is the Mac's `Tunings` — three banks, the sort that keeps 12 ET at
  row 0, the user bank, Scala import; `UI/S1TuningsPanel` draws it. Its file is `tunings_v1.json`
  in the folder **above** the banks (beside them, `userBanks()` would read it as a bank), and the
  library's folder FOLLOWS the preset library's, so one redirect in a test covers both.
  `loadPreset` applies a preset's own master set (`saveTuningWithPreset`, true as on the Mac) and
  `retune()` rebuilds the 128 frequencies; the kernel gets them at the top of the next block, never
  from the message thread. **`frequencyA4` is live here and inert on the Mac** — it moves the
  table's reference (`middleC = A4 × 2^(-9/12)`), which changes five factory presets and no golden,
  because the change is the plugin's and not the engine's.
- **The skin is chosen in the window, and the cabinet is whole** (ADR-088). `applySkin` re-dresses
  in place from the specification (the cards go first: they hold the style), and the choice lives
  in `interface.json` beside the banks. **The joystick's boxes are MEASURED** — the Swift writer
  emits `template.joystick`; never type a sprite's frame here. It drives the mod wheel through the
  processor's interface path (an atomic the next block applies, never the kernel from this thread)
  and the pitch through the `pitchbend` parameter, and upstream's 15% dead zone is the pitch's,
  not the picture's. The pads' starfield is upstream's emitter cell's MOTION drawn as small bright sparks that leave from the
  touch and stream behind it, and the target is half the Mac's size (the owner's, 2026-09-21 — the Mac emits soft discs from the centre);
  the CRT frame's glow must stay OUTSIDE what it frames, or it tints it.
- **The typeface** (ADR-088): Barlow Condensed (SIL OFL) is linked in and used wherever there is
  no Avenir Next Condensed. A change to any label or frame is held to `PluginTypefaceTests`, which
  forces the linked face so macOS cannot pass by measuring Avenir.
- **Identity is permanent** (ADR-058): manufacturer `BP03`, plugin code **`ArRu`** (it was `Ruin` until
  2026-09-21, changed while nothing had shipped — ADR-093; one code serves the AU's subtype and the VST3), VST3 class ID
  `ABCDEF019182FAEB4250303341725275` (controller `ABCDEF011234ABCD4250303341725275`). JUCE has one
  `BUNDLE_ID` for every format, so the `.vst3` bundle carries the standalone's
  `com.badpackets303.ArcadeRuinsStandalone` too; neither is the Catalyst app's ID.

## Validating it

```sh
Scripts/validate-plugin.sh   # Steinberg's validator, then pluginval at strictness 10 (ADR-079)
```

Builds both tools from pinned sources into `build/validation` the first time (some minutes).
`Scripts/validate-linux.sh` does the same and more in Docker (GCC build, every test, the
validators, the RealtimeSanitizer), and `Scripts\validate-windows.ps1` is the Windows side, run on
the owner's machine. There is no CI at present (ADR-079, second amendment).
pluginval without `--vst3validator` SKIPS that test and still prints `SUCCESS`; the script and the
workflow fail on a skipped test.

## What is here, by task

| Task | What arrived |
|---|---|
| X3-8 | `S1Keybed` (upstream's keyboard geometry, no JUCE), `UI/S1Keyboard` (the drawer's keys), the editor's drawer + Command-K + musical typing + the Wheels card, `sendMIDIFromInterface` / `isHolding` / `octaveShift` / `heldKeys` / `keyboardShown` on the processor, `window.keyboardShown` in the state, `Tests/Plugin/PluginKeyboardTests.cpp`, `EditorSnapshot --keyboard` (ADR-090) |
| X3-9 | `S1PowerCycle` (the schedule, no JUCE), `Style::setDim` / `dimmed`, a Style per zone in the editor (`styleFor`, `zoneOfSection`, `zoneOfItem`), `applyPower` / `advancePowerTo` / `restorePower`, `Backdrop::paintDeadZones`, `LayoutPower` in the specification and its Swift writer, `EditorSnapshot --power` (ADR-091, in `docs/private/`) |
| X3-7 | The editor's `stage` — everything built at the design size under one component, scaled to the window by a single transform, uniform, centred and letterboxed; `interfaceScale()`, `layoutStage()`, `paint` (the margin), `setResizable` + the limits and the fixed aspect ratio; `EditorSnapshot --window WxH` and the `EditorSnapshotLaptop` test (ADR-089) |
| X3-6 | `Fonts/` + `ArcadeRuinsFonts` (Barlow Condensed), `Style::preferLinkedTypeface` / `drawCRTFrame` / `drawPadParticles`, `applySkin` + the Settings card + the `Joystick` in `S1PluginEditor`, `LayoutJoystick` in the specification and its Swift writer, `setModWheelFromInterface` / `interfaceSkin` on the processor, `Tests/Plugin/PluginTypefaceTests.cpp` (ADR-088) |
| X3-5 | `S1TuningLibrary` (the model, no JUCE), `UI/S1TuningsPanel` (banks, tunings, the pitch wheel, the master-tuning knob), `loadPreset` applying a preset's tuning, `retune()` / `tuningLibrary()` / `savesTuningWithPreset` on the processor, `Tests/Plugin/PluginTuningsTests.cpp`, `EditorSnapshot --tunings` (ADR-087) |
| X3-4 | `S1PresetBrowser` (the model, no JUCE), `UI/S1PresetPanel` (the Mac's 380 × 720 card), the editor's preset name / Presets / Save / dice / previous / next wired to it, `PresetLibrary::removeBank` and `presetDefaults()`, `Tests/Plugin/PluginPresetBrowserTests.cpp`, `EditorSnapshot --presets` (ADR-086) |
| X3-3 | `UI/S1PluginEditor` (what `createEditor` returns: both skins, the Every-parameter panel, About), `ArcadeRuinsArt` (the painting and the wordmark, linked in), `PositionMap` / `dependentPositionMap` in the kit, `requestAllNotesOff` / `readScope` / `currentPresetName` in the processor, `Tests/Plugin/PluginEditorTests.cpp`, `Tests/Plugin/EditorSnapshot.cpp`, `Scripts/debug/compare_editor_render.py` (ADR-085) |
| X3-2 | `UI/S1KitStyle` (the Mac drawing on `juce::Graphics`), `UI/S1KitControls` (`ParameterControl` and a component per kind, `XYPad`, `EnvelopeView`, `ValueReadout`, `makeControl` / `makeDisplay`), `Tests/Plugin/PluginControlsKitTests.cpp`, `Tests/Plugin/ControlsKitSheet.cpp`; the specification gained chip titles, the `twoWay` kind and the plots' colours (ADR-084) |
| X3-1 | `Layout/layout-spec.json` (generated from the Mac layout: `LayoutSpecFixtureTests.swift`, `Scripts/write-layout-spec.sh`), `S1LayoutSpec` (JUCE-free reader), `S1LinkedLayoutSpec` (the linked-in copy), `Tests/Plugin/PluginLayoutSpecTests.cpp`, `Tests/Plugin/LayoutWireframe.cpp`, `Scripts/check-layout-spec.sh` + `Scripts/debug/compare_layout_frames.py` + `desktop_render.py`'s `RENDER_FRAMES` (ADR-083) |
| X2-10 | `S1StandaloneApp.cpp` (Standalone target only: every MIDI input open, settings beside the banks), `Tests/Plugin/PluginStandaloneTests.cpp` (the processor in JUCE's `AudioProcessorPlayer` across device changes); engine `PORT FIX`: `prepareToRender` clears the router's keys (ADR-081) |
| X2-9 | `S1PresetLibrary` (JUCE-free: linked-in factory banks, user banks as files), `S1SharedPresets`, the 695 host programs, `loadPreset` / `saveCurrentPreset`, the shipped Init as the starting sound, `PluginState::capturedPreset`; `Tests/Plugin/PluginPresetTests.cpp` + `Fixtures/factory-programs.txt` (from `FactoryProgramFixtureTests.swift`); engine `PORT FIX`: compressors re-made at the prepared sample rate (ADR-080) |
| X2-8 | `plugin.yml`: Steinberg's `validator -e` built from the pinned SDK, pluginval `v1.0.4` strictness 10 (pinned by SHA-256) with the validator handed to it, a skipped test fails; `Scripts/validate-plugin.sh` for this machine; `getProgramName` never empty; `-DS1_RTSAN=ON` + the `realtime-sanitizer` job (ADR-079) |
| X2-7 | `juce::ScopedNoDenormals` first in `processBlock`; `Tests/Plugin/PluginDenormalTests.cpp` (the mode seen from inside the call, nothing subnormal out, the tail timed on x86 in CI, the unprotected engine beside it); `GoldenHarness --flush-to-zero` + CTest `GoldensFlushToZero`; the Mac render block guarded too (`S1ScopedFlushToZero` in `S1AudioUnit.mm`) (ADR-078) |
| X2-6 | `readHostTransport` + the kernel's two handlers at the top of `processBlock`, `arpRate` skipped and put back under a host tempo, `isUsingHostTempo()` and `arpBeatCounter()` for X3; `Tests/Plugin/PluginTransportTests.cpp`; engine `PORT FIX`es in `handleTransportState` (keys released, envelopes see the gate fall) with `Tests/SynthOneTests/PluginTransportTests.swift`'s new case (ADR-077) |
| X2-5 | `S1PluginState` (JUCE-free JSON: parameters by ID, the engine's preset, tuning table, router settings), `currentState`/`applyState`/`deliverPendingToKernel` in the processor, `Tests/Plugin/PluginStateTests.cpp` + `Fixtures/state-v1.json`, `Tests/SynthOneTests/PluginStateFixtureTests.swift` (ADR-076) |
| X2-4 | The router on (`hostMIDI.enabled`, `beginRenderCycle`), the processor as `S1KernelListener`, `S1ModWheel.hpp`, `pitchbend` and `cutoff` read back and reported, `setModWheelRouting` for X2-5; `Tests/Plugin/PluginMIDITests.cpp`; `Tests/Engine/HostMIDITests.cpp` + `Fixtures/host-midi.txt` (ADR-075) |
| X2-3 | `freeReleasedVoicesEveryFrame` set in the processor; ramps left to the engine's smoothing, measured; checks at 48/96 kHz, a note's onset on its sample, the cutoff ramp's bound (ADR-074). No new plugin source. |
| X2-2 | `S1ParameterCatalog` (JUCE-free: IDs generated from `S1Parameter.h`, ranges from the kernel, names/readouts/tapers from the Mac interface), `S1HostParameter`, parameter events and engine read-back in the processor, the parameters start as Init, computed tail length, `Tests/Plugin/PluginParameterTests.cpp` + the frozen identity list (ADR-073) |
| X2-1 | `CMakeLists.txt` (JUCE 9.0.2, `juce_add_plugin`, the 54 wavetable JSON files as `S1BinaryData`), `S1PluginProcessor` (Init, MIDI notes, the host's generic editor; no parameters, state or tempo yet), `Tests/Plugin/PluginRenderTests.cpp`, `.github/workflows/plugin.yml` (ADR-072) |

## Known, and whose job it is

- **The plugin is not bit-identical to the goldens for every preset, by decision** (ADR-074): 8 of
  20 exact, 16 within tolerance, four arpeggios outside it — as upstream's own path is at any
  buffer size but 512. Whether the Mac products take the same option (and 12 goldens are rewritten)
  is the owner's call at the X2 gate.
- **The interface's type is not settled** (ADR-084): Avenir Next Condensed on macOS, a narrowed default sans elsewhere, until the owner picks a face that can ship.
- Wavetables are 5.5 MB of JSON inside each binary, parsed once per process (shared between
  instances). A generated float blob would be 852 KB; not worth a generator until X4 sizes the installers.
- The router's settings (channel, octave shift, white keys, hold) sit at the standalone's defaults
  until an interface exists (X3-8). Program change and bank select are forwarded and ignored until
  the preset library (X2-9). Init's pitch-bend range is 0, as upstream's Init is.
- "Tuning A4" (`frequencyA4`) is saved and shown but changes no pitch: nothing in the engine reads
  it, upstream included. The tuning *table* makes the pitch; rebuilding it from A4 is X3-5's.
- Tail length is an estimate (release + delay repeats to −60 dB + a guess at `sp_revsc`'s RT60).
- One value per parameter per block (JUCE's), applied at its first sample; the 45 smoothed parameters glide from there (`sp_port`, half-time 0.1 s), the rest step. Decided in ADR-074.
- After `prepareToPlay` every smoothed parameter glides up from 0 for about a second — upstream's
  `sp_port` quirk (ADR-013), in the goldens, the same in the AUv3.
