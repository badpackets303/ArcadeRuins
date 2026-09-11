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
