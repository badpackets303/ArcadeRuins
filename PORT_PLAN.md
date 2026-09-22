# Synth One → macOS / AUv3 — Master Plan

Status lives in `STATE.md`. This file is the stable reference: what the phases are, what each
task means, and how we know it's done. Task IDs are permanent — cite them in commits.

---

## 1. What we are porting (survey of upstream @ `6466a37`, 2022-03-14)

| | |
|---|---|
| Swift | 153 files, ~20,700 lines |
| Obj-C / Obj-C++ / C | 47 files, ~6,000 lines (the DSP kernel) |
| Storyboards | 12 (`Main`, `Generators`, `Envelopes`, `Effects`, `Sequencer`, `TouchPad`, `Tunings`, `Presets`, `Header`, `About`, `MailingList`, `Dev`) |
| Localizations | 8 (en, fr, ja, pt-BR, tr, zh-Hans, zh-Hant, zh-Hant-TW) |
| Synth parameters | 150 (`S1Parameter.h`) |
| UIKit reach | 75 of 153 Swift files `import UIKit` |
| Deployment target | iOS 10.3 / 11.3, Swift 5.0, Xcode ~11 project (`objectVersion = 46`) |

**DSP architecture.** `S1DSPKernel` (Obj-C++, split across 12 `.mm` files) is a real-time synth
kernel already wrapped in an `AUAudioUnit` subclass (`S1AudioUnit`). It leans on:
- **Soundpipe** — 21 modules: `sp_adsr sp_butbp sp_buthp sp_compressor sp_crossfade sp_delay
  sp_fosc sp_ftbl sp_gen_sine sp_moogladder sp_noise sp_osc sp_oscmorph2d sp_pan2 sp_phaser
  sp_phasor sp_port sp_revsc sp_vdelay` (+ a local `oscmorph2d.c`).
- **TAAE** (The Amazing Audio Engine 2) — already vendored in-tree under `DSP/TAAE/`, MIT,
  portable. Used for lock-free main↔render thread messaging. **No port work needed.**
- **AudioKit 4.9.2** — only as thin glue: `AKAudioUnit`, `AKSoundpipeKernel`, `AKInterop.h`/`AK_ENUM`.

`S1AudioUnit.h` contains the comment `///auv3, not yet used` over `setParameter:`/`getParameter:`/
`createParameters`. **The AU parameter tree was never implemented upstream.** This is net-new work
and is the single largest new-feature item in the port (task P4-3).

**AudioKit Swift API surface** (small and easily replaced — full inventory in
`docs/02-audiokit-api-surface.md`): `AKLog`(120 uses), `AKTuningTable`(34), `AKSettings`(29),
`AKPolyphonicNode`(19), `AKTable`(11), plus the AudioKitUI views `AKTouchPadView`, `AKVerticalPad`,
`AKADSRView`, `AKKeyboardView`, `AKNodeOutputPlot`, `AKLinkButton`, `AKBluetoothMIDIButton`.

**Dependencies to remove.** `AudioKit 4.9.2`, `Audiobus` (iOS-only, 8 files), `OneSignal` (push,
3 files), `AppCenter` (analytics, 2 files), `Disk 0.3.3` (file storage, 9 files), `LinkKit`
(Ableton Link, iOS-only static lib, 2 files).

---

## 2. Strategy

### The UI decision — Mac Catalyst

Requirement #1 (preserve the UI) drives everything. A native AppKit rewrite of 12 storyboards and
~75 UIKit files is a large, high-risk, fidelity-losing job. **Mac Catalyst compiles the existing
UIKit code and storyboards for macOS essentially unchanged**, and it also brings `AVAudioSession`
(which does not exist on native macOS) along with it — removing a second chunk of porting work.

**The catch, and why Phase 0 exists:** an AUv3 app extension inside a Mac Catalyst app is built for
the `macabi` ABI. Whether such a plugin loads cleanly in every major host — in particular whether
hosts that request in-process instantiation can load it — is the make-or-break unknown for this
whole approach. **We verify that with a throwaway spike before porting a single line of Synth One.**

- **Track A (preferred): Catalyst.** Spike passes → one UIKit codebase serves the standalone app
  and the plugin view. Requirement #1 is satisfied nearly for free.
- **Track B (fallback): native macOS AUv3 + SwiftUI UI.** Spike fails → the DSP work (Phases 1–2)
  is unaffected and still lands, but the UI is rebuilt in SwiftUI reproducing the existing design
  from the same asset catalog. Roughly doubles the project and is a visual-fidelity risk. Phases 3
  and 4 get rewritten if we end up here.

### The DSP decision — drop AudioKit, vendor Soundpipe

AudioKit 4.9.2 is a 2019 binary-distributed pod with no Catalyst slice and no realistic path to one.
Rather than resurrect it, we cut it: vendor Soundpipe (MIT, plain C, fully portable) and reimplement
the handful of thin AudioKit shims ourselves. `S1DSPKernel` itself — the actual synth — is
platform-agnostic C++ and should port with near-zero changes. This is the difference between
maintaining a dead 2019 framework forever and owning ~400 lines of glue.

### Build system — XcodeGen

The upstream `.xcodeproj` is a 2019 artifact and we're adding targets, dropping CocoaPods, and
enabling Catalyst. Project structure is declared in `project.yml` and generated. Text-based,
diffable, reviewable, and survivable across many sessions — hand-merging `pbxproj` across a
multi-month port is not.

### Target graph

```
Soundpipe            static lib, vendored C
S1Support            AudioKit replacement shims (AKLog/AKTable/AKTuningTable/AKSettings)
SynthOneCore         framework: DSP kernel, S1AudioUnit, model, presets, tunings, ALL UI
 ├── SynthOne        Catalyst app  (standalone; hosts SynthOneCore UI)
 └── SynthOneAU      AUv3 app extension  (aumu / ruin; hosts the same UI)
SynthOneTests        unit + render-regression
```

Both products consume identical UI and DSP from `SynthOneCore`. That is what keeps the plugin and
the standalone app from drifting apart.

---

## 3. Phases

Each task lists **Do** and **Done when**. A phase ends at a milestone that is objectively checkable.

### Phase 0 — Feasibility & foundations  ⟵ *gate; do not start Phase 1 until P0-4 resolves*

- **P0-1 Toolchain.** Install Xcode (full, not just Command Line Tools — currently
  `xcode-select` points at `/Library/Developer/CommandLineTools`). Install `xcodegen`.
  *Done when:* `xcodebuild -version` succeeds and reports Xcode 16+.
- **P0-2 Repo location + git init.** Decide where the repo lives (see Risk R-7: this directory is
  in iCloud Drive, which is hostile to Xcode builds) and `git init`.
  *Done when:* repo initialized, first commit contains the planning docs.
- **P0-3 Vendor upstream.** Clone AudioKitSynthOne pinned to `6466a37` into `upstream/`,
  committed as reference. *Done when:* `upstream/` present and gitignored from builds.
- **P0-4 ⚑ CATALYST AUv3 SPIKE — the gate.** Build a throwaway Catalyst app + AUv3 instrument
  extension: one sine oscillator, one AU parameter, one trivial UIKit view.
  *Done when:* `auval -v aumu <sub> <mfr>` passes clean, **and** the plugin instantiates, makes
  sound, shows its UI, and responds to automation in **Logic Pro, Ableton Live, and Reaper**.
  Record the result and the Track A/B decision as ADR-001 in `docs/01-decisions.md`.
- **P0-5 Reference baseline.** Get a running reference of the original for parity checking —
  install Synth One from the App Store on an iPad, or build `upstream/` for the iOS Simulator
  (expect fights with the 2019 pod setup; the App Store route is fine and cheaper).
  Capture screenshots of all 12 panels into `docs/reference/`.
  *Done when:* screenshots captured, `docs/03-parity-checklist.md` filled in from them.

**Milestone 0:** we know which track we're on and have a reference to port against.

### Phase 1 — Build system + AudioKit excision

- **P1-1 XcodeGen spec.** ✅ Done — all 6 targets, and the AU stub has been `auval`-clean since
  (ADR-008), making AU validation a per-phase regression check.
- **P1-2 Vendor Soundpipe.** ✅ Done — but **from AudioKit's fork, not canonical upstream**
  (ADR-011). Canonical lacks the band-limited `sp_oscmorph2d` that is Synth One's anti-aliasing,
  and `upstream/DSP/Kernel/oscmorph2d.c` is a stale decoy. 19 modules + `oscmorph2d`.
- **P1-3 `S1Support` shims.** ✅ Done. Turned out to be ~1,600 lines, not ~700 — `AKTuningTable`
  drags in the whole Microtonality folder. **AudioKit 4.9.2 does not compile under modern Swift**;
  three narrowing bugs fixed, each with a regression test.
- **P1-4 AudioUnitBase.** ✅ Done. Headers placed under `AudioUnitBase/AudioKit/` so ported kernel
  sources keep their `#import "AudioKit/..."` lines verbatim. Proven by `S1TestToneAudioUnit`.
- **P1-5 Port the DSP kernel.** ✅ Done — and it *was* mostly mechanical: 8 edited lines across 8
  files. It also exposed ADR-011.
- **P1-6 ⚑ Headless render harness. DONE.** `Tests/SynthOneTests/S1AudioUnitRenderTests.swift`
  instantiates `S1AudioUnit` directly (no UI, no engine), loads the 52 band-limited wavetables,
  plays MIDI notes and pulls `internalRenderBlock` offline. 10 tests assert audible output, the
  fundamental across four octaves, transpose, note-off release, four-voice polyphony (spectrally),
  and survival of repeated allocation; one writes `Renders/p1-6-first-sound.wav` to listen to.
  Required making `S1AudioUnit.h`/`S1Parameter.h` public and correcting our `AK_ENUM` shim
  (ADR-012), and surfaced the post-allocation pitch sweep (ADR-013).

**Milestone 1 — REACHED:** the Synth One DSP renders audio on macOS with zero AudioKit and zero UI.

### Phase 2 — Audio engine & regression safety net

- **P2-1 Replace the AudioKit engine. DONE.** `S1AudioEngine` replaces `AudioKit.engine` /
  `.output` / `.start()` — an object, not a global (ADR-014). `AKNode`, `AKPolyphonicNode`,
  `AKMixer` and `AKComponent` ported into `SynthOneCore/Nodes/`; `AKSynthOne.swift` ported with
  three changed lines. `Conductor.swift` itself is **deferred to Phase 3** — it is more UI
  controller than audio, and its audio half is what `S1AudioEngine` now is. ADR-015 records the
  ordering rule that made offline rendering usable.
- **P2-2 Platform abstraction. DONE.** `S1AudioSession` protocol with two implementations —
  `S1SystemAudioSession` for the app, `S1HostedAudioSession` (no-op) for the plugin. **The no-op is
  the default**, so forgetting to configure fails loudly in the app rather than silently in
  someone's DAW.
- **P2-3 Recorder. DONE.** `S1NodeRecorder` taps an `AVAudioNode` into an `AVAudioFile`, writing
  WAV directly — which deletes AudioKit's asynchronous CAF-to-WAV export step entirely.
  `AudioRecorder.swift` ported on top of it.
- **P2-4 ⚑ Golden-WAV regression tests. DONE.** 20 of Synth One's **own shipped presets**, selected
  by greedy coverage over 23 sonic features across all 695 and spread across all 13 banks, rendered
  offline and committed as float32 WAV in `Tests/Goldens/`. Required porting the preset model early
  (`Preset.swift` + the mapping out of `PresetDataManager.loadPreset()`).
  *Measured sensitivity:* a **0.24%** change to one internal LFO constant fails **17 of 20**.
  Determinism is asserted, not assumed. ADR-016.

**Milestone 2 — REACHED:** audio path is ours, and DSP regressions are caught automatically.

### Phase 3 — Standalone Catalyst app  *(Track A; rewritten if Track B)*

- **P3-1 Compile the UI under Catalyst. DONE.** All 12 storyboards and **153** Swift files (the
  original "75" undercounted) build inside `SynthOneCore`; the app launches and every panel loads and
  lays out, verified headlessly by `UILoadTests` and rendered to PNGs in `Renders/ui/`. Required
  `SynthOneApp` as the framework's public façade (ADR-017), shims for `AKADSRView`,
  `AKNodeOutputPlot`, `Disk` and the MIDI protocol, and correcting 18 `customModule` attributes in
  two storyboards. Four real bugs found in the process — see `Sources/SynthOneCore/PORTING-UI.md`.
- **P3-2 Excise iOS-only services. DONE.** `S1PlatformServices` with a do-nothing implementation
  (default), covering the StoreKit review prompt, Audiobus/IAA host registration, host icon and
  host switching. Call sites stay where upstream put them. Push and analytics turned out to be
  unreachable under Catalyst already — upstream guards them with `#if`. Removed AudioKit's live
  Audiobus credential; the `"***REMOVED***"` MailChimp placeholders are **load-bearing** and stay.
- **P3-3 Storage. DONE — with one half unsolved.** `Disk` on `FileManager`, writing to
  `~/Library/Application Support/SynthOne/`, with a once-only migration out of the old sandbox
  container. **Not an App Group**: unavailable without a Team ID, and the documented
  temporary-exception fallback is *denied under ad-hoc signing* — measured, see ADR-018. The app is
  therefore unsandboxed; the AUv3 stays sandboxed and **still cannot see these files**. P4-1 has to
  establish whether an ad-hoc extension can be unsandboxed.
- **P3-4 MIDI. DONE.** `S1MIDI` over CoreMIDI: source enumeration, connect/disconnect by name, a
  virtual destination and source, and hot-plug via the client notify block. Incoming Universal MIDI
  Packets (MIDI 1.0 protocol) are parsed into the existing `AKMIDIListener` calls, so MIDI learn and
  CC mapping port untouched. Verified against real hardware on the owner's machine. The Bluetooth
  MIDI button now opens Audio MIDI Setup rather than hiding.
  *Found on the way:* the app took **72 seconds to show its window** because upstream's
  `.playAndRecord` session category prompts for microphone access. Synth One never records input on
  macOS — `.playback` now, no prompt, instant launch. See the P3-4 correction on ADR-015.
- **P3-5 ⚑ Pointer input fidelity. DONE.** Knobs gained the scroll wheel and ⌥ fine-drag;
  double-click-to-default already worked. **Computer-keyboard note entry added** (GarageBand/Logic
  Musical Typing) — the real answer to one pointer, since chords by mouse otherwise need Hold. Touch
  pads and the ADSR editor already track a single pointer correctly and were left alone; right-click
  MIDI-learn turned out to be unnecessary. Found and fixed a latent upstream bug: `Knob` wired its
  gestures only in `init?(coder:)`, so a knob built in code had none.
- **P3-6b Resizable window. DONE.** `S1ScalingContainer` scales the fixed 1024×768 interface to fit
  the window uniformly, rather than relayouting it — the storyboards have no adaptive layout, so a
  stretch would strand controls. Opens at 1:1, resizes from 0.5× to 3×. ADR-019.
- **P3-6c Keybed. DONE, at the owner's request (2026-09-10).** The interface is 1024×868:
  upstream's layout plus 100 points. The keyboard is hidden by default at 4 octaves, and hidden keys
  fill that space instead of running off the bottom of the window. The keys are shaded. ADR-035.
  Then, after the owner tried it in Logic, Show and Hide resize the window: shown 1024×868, hidden
  1024×768 with 88-point keys, never covering the panels. ADR-037.
- **P3-6 Window & chrome. DONE.** A `SceneDelegate` that sets the window title, bounds it between
  0.75× and 2× the 1024×768 design size, and hides the title bar. A macOS menu bar that *removes*
  what a synth has no use for (Format, New Window, Recents, spelling, substitutions, speech) and
  adds **Panic (⌘.)** plus a discoverable Musical Typing section.

- **P3-7 Ableton Link decision.** `ABLLinkManager.swift` (543 lines) targets the iOS-only LinkKit.
  Options: port to the open-source Link C++ SDK (macOS-supported), or ship without Link in v1 and
  rely on host sync in the plugin. Record as an ADR. *Default: defer to post-1.0.*

**Milestone 3:** a standalone macOS Synth One at UI/functional parity per `docs/03-parity-checklist.md`.

### Phase 4 — The AUv3 plugin

- **P4-1 Extension target + `AudioComponents`. DONE.** The target and component metadata were
  already `auval`-clean from P1-1; P4-1's real content was **answering ADR-018's open question**.
  Measured: a sandboxed extension can read the framework bundle (factory banks, wavetables,
  storyboards) but **not** the app's shared preset folder, and an **unsandboxed** extension will not
  load at all — macOS refuses to open the component. So the plugin ships factory presets only, and
  the Team ID question is now a product decision rather than a technical unknown. ADR-020. Six tests
  guard the component identity, because `aumu`/`ruin`/`BP03` is what every saved session references.
  type `aumu`, subtype `ruin`, a manufacturer code we own, `sandboxSafe`, tags.
- **P4-2 `S1Engine` abstraction (standalone vs AU). DONE.** The plugin vends the real
  `S1AudioUnit` — the P1-1 silence stub is gone. Wavetable loading extracted from `AKSynthOne.init`
  into `S1Wavetables`, because the AUv3 has no `AKSynthOne`; the AU path creates no engine at all,
  since the host owns the graph. **Found and fixed a render-thread segfault** in vendored Apple
  sample code that had never executed in Synth One's history — see ADR-021. `auval` passes in 2s
  with all 150 parameters tested.
  Introduce an `S1Engine` protocol implemented by both the standalone engine and the AU, so the
  UI binds to one thing in both products. This is the main structural refactor of the port.
- **P4-3 ⚑ AUParameterTree.** Build the tree from the 150 `S1Parameter` entries — identifiers,
  display names, units, min/max/default (already exposed by `getMinimum:`/`getMaximum:`/
  `getDefault:`), and the existing taper curves from `S1DSPKernel+tapers.mm`. Wire two-way binding:
  host automation → DSP → UI, and UI → DSP → host.
  The tree itself already exists and `auval` exercises all 150; the concrete gap is
  `S1DSPKernel::startRamp`, an empty function — see STATE.md's Next action for the full call path
  and the `notifyMainThread` decision it forces.
  *Done when:* every parameter automates from Logic and the UI tracks it live.
- **P4-4 State & presets.** Implement `fullState` / `fullStateForDocument` using the existing
  `Preset` codec so host sessions save and restore, and expose the factory banks as AU
  `factoryPresets`.
- **P4-5 Host transport.** MIDI in via the AU; tempo and transport via `musicalContextBlock` and
  `transportStateBlock`, driving the arpeggiator, sequencer, tempo-synced LFOs and delay — the
  role Ableton Link plays in the iOS app.
- **P4-6 Plugin view.** ✅ **Done 2026-09-09** (ADR-026, ADR-027, ADR-028). `AUAudioUnitViewController` hosting the same storyboard UI;
  `preferredContentSize`, resize/scaling behavior in hosts that allow it.
- **P4-7 ⚑ Host validation matrix.** `auval` clean, then Logic Pro, Ableton Live, GarageBand,
  Reaper, Bitwig: instantiate, sound, UI, automation, state save/restore, multiple instances,
  offline bounce. Track results in a table in `STATE.md`.

**Milestone 4:** a working AUv3 instrument.

### Phase 5 — Packaging & release

- **P5-1** Sandbox entitlements, App Group, hardened runtime.
- **P5-2** Developer ID signing, notarization, stapling. (AU registration requires the containing
  app to have been launched at least once, conventionally from `/Applications` — document this.)
  **Measured 2026-09-09:** Gatekeeper (`spctl -a`) rejects the ad-hoc build, and a downloaded copy
  fails as "damaged". This task is what makes public binaries usable without an `xattr` step.
- **P5-3** Installer (DMG or pkg), first-run experience.
- **P5-4** ✅ **Done 2026-09-09 (ADR-029).** Licensing & attribution: `LICENSE` (MIT, ours) and
  `NOTICE.md` covering AudioKit Synth One (MIT), AudioKit 4.9.2 (MIT), Soundpipe (MIT) and TAAE
  (**zlib**, not MIT as this line assumed — it asks for acknowledgement in product documentation).
  `README.md` written. About panel rewritten, contributor list preserved. Named **Arcade Ruins**;
  AU subtype `aks1` → `ruin`; all wordmarks and the app icon replaced.
  ⚠️ P5-5 inherits a consequence: seven stale `About.strings` were deleted, so the About panel is
  English-only until that pass.
- **P5-5** Localization pass across all 8 languages under Catalyst.
- **P5-6** Accessibility pass (VoiceOver on knobs/pads — weak upstream, desktop raises expectations).

### Phase 6 — The desktop layout  *(added 2026-09-12, ADR-045; branch `desktop-ui`, version 0.2.0)*

The owner's chosen redesign: a single Mac window with a preset sidebar, every section visible in four
rows, a textured finish, and no virtual keyboard. Design: the canvas at
<https://claude.ai/code/artifact/4623edc1-39b7-4667-a58d-eb810d176f41>, page 1. The classic layout
stays behind `S1ClassicLayout` and tag `v0.1.0-classic-ui`.

- **P6-0** ✅ Baseline: tag, branch, version bump, `S1Layout` switch, View ▸ Classic Layout, window
  sizing per layout, test bundle pinned to classic.
- **P6-1** ✅ Shell and rows: toolbar (preset navigator, dice, Save, scope, Record, Panic, About,
  Settings, Presets), four rows of sections re-homing the Generators, Envelopes, Effects, Sequencer
  and Touch Pad controls, play bar (Hold, Mono, MIDI Learn, Transpose, Octave, Wheels), status bar
  (tuning chip → sheet). Accepted on a render of the running app.
- **P6-2** ✅ **Done 2026-09-12.** Readouts and formats: the four tempo-syncable rate knobs (LFO 1,
  LFO 2, delay time, auto-pan) read the nearest musical rate when tempo sync is on and Hz/seconds
  otherwise, following `.tempoSyncToArpRate`, `.arpRate` and the dependent parameters through
  `Manager.updateUI` → `S1DesktopLayout.parameterDidChange`; the filter mode is a Low/Band/High picker
  (`S1SegmentedControl`) that drives and follows the classic cycling button; LFO target chips and wave
  pickers draw in the desktop style. Found and fixed on the way: `LFOToggle` split its hit-test at a
  constant 100 points, so at any other width LFO 2 was nearly unclickable. Detune stays a plain
  decimal — the DSP treats it as a generic ±4 (`S1DSPKernel.hpp`), and upstream never gave it a unit.
- **P6-3** ✅ **Done 2026-09-12.** The sequencer in the desktop style: `VerticalSlider` (ticked
  groove, 32×14 cap, longer travel), `ArpButton` (glowing note-on bar), `SliderTransposeButton`,
  `ToggleSwitch` as an Arp | Seq two-way switch, `ArpDirectionButton` as three arrow cells,
  `Stepper` as `[−] value [+]`, `TempoStepper` as a draggable display over − and +. Found and fixed
  on the way: `Stepper`, `TempoStepper` and `ArpDirectionButton` hit-tested against rectangles fixed
  for their storyboard sizes, so at the desktop sizes the plus button and the third direction cell
  were partly or wholly unreachable; each now derives its zones from its bounds in the desktop dress
  (`hitZone(for:)`, `cellWidth`), and the classic dress keeps the storyboard paths.
- **P6-4** ✅ **Done 2026-09-12.** Window polish. Measured, not assumed: row one's fixed sections plus
  the sidebar need 1,416 points and the fourth row starves below 900 tall, so the minimum window is
  the design size, 1440×900, until the sidebar can collapse (P6-6; then ~1240 wide). Above it the
  fourth row alone grows and the flexible sections spread; rendered at 1680×1100. The layout and the
  window are pinned to Dark (`overrideUserInterfaceStyle`), so sheets and popovers match; ADR-034's
  per-field Light pins are untouched. The unsatisfiable-constraint noise is gone: every explicit
  constraint in the hidden classic hierarchy is deactivated at install, and OSC 2's own width was
  one point short of its selector. `desktop_render.py` gained `RENDER_SIZE`, `RENDER_PRESS` and
  `RENDER_PRESENTED`. `MorphSelector` keeps its classic drawing: the owner declined a change to its
  highlight plate earlier and did not ask for one now.
- **P6-5** ✅ **Done 2026-09-12 (owner to confirm in Logic).** The plugin gets the same desktop layout,
  sidebar included (the owner wants the sidebar, 2026-09-12). `preferredContentSize` is 1440×900 and
  `Scripts/debug/auhost.swift` gave the plugin a 1440×932 window (content plus title bar), so a host
  honours it. In the plugin: no Record, the scope fed from the render thread's ring (ADR-028), the
  "Following host transport" caption, the view pinned Dark, and the panel sheets presented as
  overlays inside the plugin's view (`overCurrentContext`, as the classic panels' own modals are)
  rather than as Mac sheets, which need a window the plugin does not own (ADR-044). Found and fixed:
  `AKTouchPadView` set a NaN layer position when a hosted synth's dependent parameters were read
  before render resources existed, which would have taken the plugin down in a host that builds the
  view first. `DesktopPluginTests` covers the differences.
- **P6-6** ✅ **Done 2026-09-12.** The preset sidebar: the classic browser re-homed as a 260-point
  column — search (⌘F, the classic search screen), the category and bank list (28-point rows), the
  presets of the selection taking the height (30-point rows, with the star, rename, duplicate and
  share buttons on the selected row as before), the selected preset's category and editable notes,
  and New · Import · Reorder · Import Bank · New Bank. Every table, cell and button is the
  storyboard's with its data source, delegate and callbacks; the category list's delegate is wired
  at install because the classic panel wired it in `viewDidAppear`. The toolbar's Presets button,
  ⌥⌘S and View ▸ Show/Hide Sidebar collapse it, and the window's minimum width follows
  (`SynthOneApp.desktopSidebarDidChange`): 1180 with the sidebar hidden. The Presets sheet is gone;
  `S1PanelSheet` serves Tunings only.
- **P6-7** ✅ **Done 2026-09-12.** The classic screens over the layout. Rendered each through its
  segue: Settings and Wheels are popovers anchored to their buttons and were right already; About
  (a 1024×768 scene) sat in the window's top-left corner, the preset and bank editors floated near
  the top, and Search stretched to the whole window. Each of those four now presents as a centred
  card over a dimmed backdrop at its own size (`S1DesktopLayout.dressPresented`, called from the two
  `prepare(for:)`s; the controller's view becomes a backdrop holding its original view, so outlets
  and delegates are untouched). Keys settings is retired with the keyboard. Also: the preset
  sidebar's rows centre their label and buttons, which the storyboard placed for a 44-point row
  (`PresetCell.centresContentVertically`) — the owner saw the highlight off-centre.
- **P6-8** ✅ **Done 2026-09-13.** Release prep for 0.2.0. `docs/screenshots/` holds the final renders
  (`standalone.png`, `presets-sidebar.png`, `standalone-compact.png` at 1180×900, `classic-layout.png`
  being 0.1.0's capture; the P6 work renders are gone), made with `desktop_render.py`'s new
  `RENDER_SELECT` so a factory bank shows rather than the owner's. README rewritten around the desktop
  layout (status, screenshots, an "interface" section with the sidebar keys, window minimum and the
  classic switch); `docs/release-notes.md` started with 0.2.0 and 0.1.0. Both `Info.plist`s carry
  `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` — they were literal 1.0 / 1. Found on the way:
  after hiding the sidebar in an 1180-wide window the Steps stepper rendered as a horizontal smear —
  the old bitmap stretched over new bounds — so every desktop dress sets `contentMode = .redraw`.
  The Logic screenshot is still 0.1.0's; the owner takes the new one.

---

### Phase 7 — Skins  *(added 2026-09-13, ADR-046; branch `desktop-ui`, version 0.3.0)*

The owner's synthwave mock-up of the desktop layout as a skin, built fully procedural (owner's
decision, 2026-09-13: "finish P6-8 first, then do the skin fully procedural"). A skin is a palette and
decoration; it never moves anything.

- **P7-0** ✅ **Done 2026-09-13.** Plumbing: `S1Skin` / `S1Palette` / `S1SkinChoice` (`S1Skin` default,
  View ▸ Skin ▸ Studio | Arcade, next launch), `S1DesktopTheme` reading the palette with its names kept,
  `S1DesktopStyle`'s 32 inline colours as palette entries, Studio's values exact to 0.2.0.
- **P7-1** ✅ **Done 2026-09-13.** Arcade's controls: neon orange and cyan palette, glow ×2.2 on knob arcs,
  indicators, lit switches, fader caps, note-on bars and wave pickers; cyan readouts; orange section
  borders with an outer glow; grunge texture over every section.
- **P7-2** ✅ **Done 2026-09-13.** Arcade's art, in code: `S1ArcadeHeaderArt` (sky, stars, sun with
  cuts, two mountain ranges, grid, horizon), `S1ArcadeSidebarArt` (starfield, mountains, floor grid,
  joystick), `S1NeonWordmark`, `S1CRTFrame` round the sidebar's lists and the XY pads.
- **P7-3** ✅ **Done 2026-09-13.** `SkinTests` (6), both skins rendered at 1440×900 and 1180×900,
  `docs/screenshots/arcade-skin.png`, README and release notes for 0.3.0, installed and `auval` passed.
  The plugin takes the same default from its own container (untested in Logic).
- **P7-8** ✅ **Done 2026-09-14.** Owner: "Can we make the default layout the classic one. And then
  let's assign this icon to it for MacOS." A fresh install opens **classic** (absent
  `S1ClassicLayout` means classic now; Settings ▸ Layout changes it), and the app has **an icon at
  last** — the owner's artwork as `Sources/SynthOne/ArcadeRuins.icon`, an Icon Composer bundle.
  A mac-idiom icon set was tried first and macOS 26 drew the owner's rounded square nested inside
  its own on a light plate; the `.icon` bundle is the artwork the system shapes. ADR-052. 54 green.
- **P7-9** ✅ **Done 2026-09-17** (branch `cabinet-skin`, unreleased). Owner: "another similar skin … use this as
  the background template. All you need to do is place the knobs and controls over it." The Cabinet
  skin: a painted window with the sections pinned to its frames. ADR-059, which amends ADR-046.
- **P7-10** ✅ **Done 2026-09-17** (unreleased). Owner: "get rid of the neon arcade skin and replace it with
  the cabinet skin." Skins are Studio | Cabinet; a stored Neon Ruins opens Cabinet. ADR-060.
- **P7-11, P7-12** ✅ **Done 2026-09-17**, released in 0.5.0. Two Cabinet extras, not published:
  `docs/private/cabinet-extras.md` (ADR-061, ADR-062).
- **P7-7** ✅ **Done 2026-09-14.** Owner: "Remove the 'Arcade' skin as an option." Neon Ruins is the
  same idea done properly, and nothing had shipped with Arcade. `S1SkinChoice` is `studio |
  neonRuins`; the skin, its header and browser art, its drawn wordmark and its grunge tile are
  deleted; `S1ArcadeArt` becomes `S1SynthwaveArt`, the kit both skins always shared. A stored
  `S1Skin = arcade` opens Studio. ADR-051. 45 tests green.
- **P7-6** ✅ **Done 2026-09-14.** Owner: "I would still like to access the original iPad-based
  interface by changing the setting. Can we include that in the release?" **Layout ▸ Desktop |
  Classic** joins Skin in the Settings popover (`S1AppearanceSettings`), installed from
  `MIDISettingsViewController` so the **classic** layout carries it too — otherwise Classic was a
  one-way trip in a host, which has no menu bar. The skin picker dims and reads `SKIN · DESKTOP
  ONLY` under Classic. Also: the layout and skin defaults go through `S1Preferences.store`, which
  the test bundle points at a scratch suite — P7-5's tests had been writing and deleting the
  owner's real settings (ADR-036's hazard, preferences edition). ADR-050. 58 tests green.
- **P7-5** ✅ **Done 2026-09-14.** Owner: "Can we allow skin selection through the Settings menu
  within the app? Going through Terminal is not a feasible option." `S1SkinPicker` in the Settings
  popover's right column, added by the desktop layout when it dresses `SegueToMIDI` (no ported file
  changes); Studio | Arcade | Neon Ruins, applied at the next launch, with wording that differs in
  the plugin. **The plugin can be re-skinned from inside a host for the first time** (it has no menu
  bar). ADR-049. `SkinTests` 11, `DesktopPluginTests` 5.
- **P7-4** ✅ **Done 2026-09-14.** The **Neon Ruins** skin (ADR-048), from the owner's second
  reference and four rounds on the design canvas: one neon per section (orange, mint, pink, violet,
  gold, cyan — a spectrum across each row; Mix mint like Delay at the owner's word), 2-point neon
  borders with a bloom over near-black worn-metal panels, halo'd knobs with a bright core and a white
  pointer, lit fader tracks, cyan readouts and outlines, a sunset header with the owner's wordmark
  lit, nebulae and a magenta floor under a translucent play bar. Plumbing: `S1Skin.sectionAccent(for:)`,
  `S1SectionView.accent`, `UIView.s1Accent`, an `accent` argument on every `S1DesktopStyle` drawing,
  `S1SkinDress`, `makeBackdropArt()`, the `s1_wordmark_neon` asset. Studio and Arcade unchanged.
  `SkinTests` 10.

---

### Phase 8 — Layout revisions the owner asks for  *(added 2026-09-13; branch `desktop-ui`, version 0.3.0)*

The desktop layout in use, adjusted at the owner's direction. Each task is one request.

- **P8-0** ✅ **Done 2026-09-13.** "Let's have it as a drop-down when a user clicks on the preset name
  at the top of the window. Get rid of the side panel." ADR-047: the browser column drops down from
  the toolbar's preset name (chevron, ⌥⌘P, View ▸ Preset Browser; closes on a click outside, Escape,
  or any card presentation); the sidebar region, its window notification and the toolbar's Presets
  button are gone; the rows have the whole 1440 and were re-spaced (wider OSC/Filter/Voice sections,
  44-point knobs, a wider LFO section whose readouts no longer overlap, 400-point pads; rows one and
  two 158/220 tall). The Find menu is removed (⌘F conflict since P6-6). Found by the owner right
  after ("Where did the preset editor go?"): the preset row's rename, duplicate and share buttons had
  been off the right edge since the P6-6 sidebar — the storyboard fixed them at x 324…487 of a
  499-point cell — so `PresetCell` lays them out from the trailing edge in the desktop dress.
- **P8-1** ✅ **Done 2026-09-13.** Owner: "The LFO/Mod Target panel looks clunky and haphazard, with
  the 4 tiny knobs scrunched up on the right. Most of the knobs in general could be bigger as there
  is still plenty of wiggle room in the Effect panels, Filter Amplitude and Envelope panels. The OSC 2
  knobs are scrunched together and need to be spaced apart equally." LFO & Mod Targets is two columns:
  each LFO's name, wave picker, rate and amount (40-point knobs) on the left, the twelve targets as a
  3 × 4 grid on the right; the section is ×1.25 of Filter Envelope. Knobs: effects 38→48, envelopes
  36→46, cutoff 60→68 with 52s beside it, Mix and Glide 44→52. OSC 2's two knobs each take half the
  section (`fillEqually`); its selector is centred on its own line. Row heights unchanged.

---

## 4. Risk register

| ID | Risk | Impact | Mitigation |
|----|------|--------|------------|
| ~~R-1~~ | ~~Catalyst AUv3 not viable in real hosts~~ | — | **CLOSED 2026-09-08.** P0-4 spike passed auval and loads in- and out-of-process. See ADR-001 |
| R-2 | Multi-touch → single pointer fidelity loss | Keyboard/pads feel worse than iPad | P3-5 designed as a first-class task, not an afterthought; computer-keyboard input added |
| R-3 | DSP behaves subtly differently (denormals, FP, buffer sizes) | Sound drift users would notice | P2-4 golden-WAV tests. **This risk already fired once** — ADR-011's wrong Soundpipe fork would have silently removed anti-aliasing. Do not defer P2-4 |
| R-4 | 150-parameter AU tree is a large surface for automation bugs | Host automation misbehaves | Generate the tree programmatically from `S1Parameter`, not by hand; test all 150 in a loop |
| R-5 | Real-time safety in AU context (allocations/locks in render) | Crackles, dropouts | TAAE messaging is already lock-free upstream; audit with Instruments' thread checks |
| R-6 | Old Swift 5.0 code vs modern compiler (concurrency checking) | Compile churn | Pin the Swift language mode to 5 initially; modernize deliberately, later |
| ~~R-7~~ | ~~Repo in iCloud Drive~~ | — | **CLOSED 2026-09-08.** Repo moved to `~/Developer/SynthOne` |
| R-8 | Upstream is archived — no upstream fixes | We own all bugs | Pin `6466a37`, keep `upstream/` for diffing, keep port diffs minimal and readable |
| R-9 | Catalyst's 77% scaling shrinks the fixed iPad layout | UI reads smaller than the original | ADR-007; compare both idioms at P3-1 against P0-5 reference shots |

---

## 5. Rough sizing

Phase 0 is small but decisive. Phases 1–2 are the well-understood mechanical core. Phase 3 is the
long tail of UIKit-on-macOS fixes. Phase 4 is the largest chunk of genuinely new code (the AU
parameter tree and state model never existed upstream). Phase 5 is short but has hard external
dependencies (Apple Developer account, notarization).

Expect Phase 3 and Phase 4 to each span several sessions. Keep task granularity at "one commit,
one verification" so a session ending mid-phase never loses ground.

---

## 6. Cross-platform plugin — phases X0–X4 *(added 2026-09-16, ADR-054; rebased on 0.5.0 2026-09-17, ADR-065; X1 complete 2026-09-18, ADR-065–071)*

A second product on the same engine: a JUCE 9 build shipping VST3, AU and a standalone on macOS,
Windows and Linux. The full plan, with acceptance criteria per task, is the page at
<https://claude.ai/artifact/9zr5fP3KeuYMt5kvcmcaDH>. Task IDs are permanent and use the prefix `X`.

| Phase | What | Gate |
|---|---|---|
| **X0** | Decisions and survey. **X0-1 framework: JUCE 9, Starter licence — decided (ADR-054).** **X0-2 Catalyst products: kept through X2, decided at the X3 gate; the JUCE build ships no AU before then (ADR-055).** **X0-3 repo shape: one repository, `Sources/S1Engine/` + `Sources/S1Plugin/`, JUCE by FetchContent (ADR-057, proposed).** **X0-4 identity: `BP03`/`Ruin`, parameter ID = `S1Parameter` case name, AU subtype deferred (ADR-058, proposed).**, **X0-5 scope: desktop layout only, preset files kept, MIDI learn deferred, Dev panel dropped (ADR-056).** | ADRs recorded |
| **X1** | **Complete (2026-09-18).** A portable C++ engine in `Sources/S1Engine`, compiled by both Xcode and CMake: Soundpipe + kernel with no Apple types (ADR-065–067), tunings (ADR-068), presets (ADR-069), wavetable loader and a kernel that frees its memory (ADR-070), and the golden harness — the twenty goldens through the engine alone, **bit-exact on Apple Silicon, within −50 dB (measured −63 dB) on Linux and Windows**, `-ffp-contract=on` (ADR-071). 3-OS CI plus a sanitizer job | Goldens **exact** on the Mac products — met; owner tried the installed app and AUv3 |
| **X2** | The plugin with the host's generic interface: JUCE project + 3-OS CI; 150 parameters generated from `S1Parameter.h` with dependents; sample-accurate events and ramps; MIDI through `S1HostMIDI`; state; host tempo/transport; flush-to-zero; `pluginval` level 10; preset library on disk; standalone shell | Goldens at 44.1/48/96 kHz and odd block sizes on all three OSes. **X2-1 done (ADR-072):** project, VST3 + Standalone, 3-OS `plugin` CI, processor = bare engine sample for sample. **X2-2 done (ADR-073):** 150 parameters, IDs generated from the enum and frozen, engine-driven rates reported back; `PORT FIX` in `prepareToRender`. **X2-10 done (ADR-081):** the standalone — JUCE's holder with our application object (every MIDI input open by itself, settings beside the banks, no audio input), checked live on the Mac (a keyboard appearing after launch plays; the sound and device come back after a quit) and by a test through JUCE's own player across device changes; `PORT FIX`: a re-prepared engine clears the router's keys (a key held across a device change was swallowed afterwards, the AUv3's too); the hardware checks are the owner's. **X2-9 done (ADR-080):** the preset library — the Mac app's thirteen bank files linked in (byte for byte), user banks as the same files in a per-user folder beside (not in) the App Group, a host's 695 programs numbered and named as the AUv3's, presets loaded through a scratch kernel and as recordable edits; the plugin starts with the SHIPPED Init (28 parameters from the model's bare defaults); `PORT FIX`: the compressors were built for the constructor's sample rate, 2.2× too fast at 96 kHz, the Mac AUv3's too. **X2-8 done (ADR-079):** pluginval strictness 10 and Steinberg's validator (537/537 after the host's program got a name; pluginval skips the validator unless handed one), the RealtimeSanitizer (two upstream allocations on the audio thread found and fixed, bit-exact); **CI replaced by three scripts** after GitHub stopped the jobs — macOS and Linux (Docker) here, Windows on the owner's machine (first run 2026-09-18, VS 2026: all green). **X2-7 done (ADR-078):** every render call flushes subnormals to zero (`juce::ScopedNoDenormals`; the Mac render block too); measured on the CI's x86 machines — unprotected the engine parks in subnormals and silence costs 1.15–1.8×, protected the tail is ≤ 1.01× the sounding part; goldens bit-exact under it. **X2-6 done (ADR-077):** host tempo and transport from the play head into the kernel's own handlers; the host's tempo wins over the tempo parameter (reported, not obeyed); 124.999 ms per sixteenth at 120 BPM from the rendered output; `PORT FIX`es in the stop handler, the Mac AUv3's too (keys released, the first note after a stop no longer silent). **X2-5 done (ADR-076):** state as JSON text — parameters by ID, the engine's preset (the Mac app reads it), tuning table, router settings; a committed v1 state read on three OSes. **X2-4 done (ADR-075):** host MIDI through `S1HostMIDI`, the mod wheel on the render thread, the router held to the standalone's notes on three OSes by a Swift-written fixture. **X2-3 done (ADR-074):** the plugin frees released voices every frame, so its render is the same at every buffer size (proved on all twenty golden presets); ramps are the engine's smoothing. **For this gate, the owner's:** whether the Mac products take the same option, which rewrites 12 of the 20 goldens; tempo-synced values keeping their note value across tempo changes was decided YES and done (ADR-082) |
| **X3** | The interface, rebuilt from the 0.5.0 desktop layout under the **Cabinet** skin (ADR-059: the painting plus a rectangle per section, already data) with Studio second: **X3-1 done 2026-09-19 — the layout specification, measured from the Mac layout by a Swift test into `Sources/S1Plugin/Layout/layout-spec.json` and held to the running app, 144 of 144 frames per skin at 0.00 points (ADR-083)**; **X3-2 done 2026-09-19 — the controls kit: the Mac drawing ported onto `juce::Graphics`, a component per kind bound by gesture to its host parameter, tested with no window (ADR-084)**; **X3-3 done 2026-09-19 — the editor: both skins from the specification and the kit, every parameter reachable, measured against the Mac app on the same preset (ADR-085); the owner's side-by-side sign-off is open**; **X3-4 done 2026-09-19 — the preset browser: the bundled banks written out as the person's files on first use, the Mac browser's logic as a model with no JUCE in it, its 380 × 720 card over it; a bank the Mac app exported reads unchanged (ADR-086)**; **X3-5 done 2026-09-20 — the Tunings panel: the Mac's three banks and its sort as a model, the pitch wheel, Scala import, a preset's own scale played (the eleven microtonal factory presets, measured from the audio) and A4 made live (ADR-087)**; **X3-6 done 2026-09-20 — the skins chosen in the window, a real Settings card, Barlow Condensed shipped for Windows and Linux, and the cabinet made whole: its joystick live again, the pads' starfield and their CRT frame (ADR-088); the red power buttons are their own task**; **X3-7 done 2026-09-21 — the window scales: everything is built at the design size on one stage and scaled to the host's window by a single transform, uniform, centred and letterboxed, 0.75x to 1.5x, with a 1280 x 800 laptop showing the whole interface at 0.85x (ADR-089)**; **X3-8 done 2026-09-21 — the keyboard drawer: the interface plays MIDI through the router, so a key in the drawer IS a host note (measured sample for sample); Hold, the octave, the Wheels card and musical typing; Command-K, closed by default and remembered per instance (ADR-090)**; **X3-9 done 2026-09-21 — the cabinet's power: sections and chrome alike, off-then-on pixel-identical to never darkened (ADR-091, private)**; controls kit; sections; Tunings; Studio + Cabinet skins, Cabinet the default; scaling; keyboard drawer and play bar | Owner finds nothing missing within the X0-5 scope |
| **X4** | Installers (pkg / Windows installer / tarball), signing (notarisation reused; Windows Authenticode is the owner's certificate), host matrix, docs, release | Tagged release, checksums, goldens green on the release commit |

The engine carries over; the sound is proven by the existing goldens, not assumed. The interface
is the bulk of the work (X3, 10–16 sessions against 4–6 each for X1 and X2).
