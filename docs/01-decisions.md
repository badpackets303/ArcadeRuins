# Architecture Decision Record

One entry per non-obvious decision. Append; don't rewrite history. If a decision is reversed,
add a new ADR that supersedes the old one and mark the old one Superseded.

---

## ADR-000 — Format

**Status:** Accepted · **Date:** 2026-09-07

Each ADR records: Status, Date, Context, Decision, Consequences. Keep them short.

---

## ADR-001 — UI strategy: Mac Catalyst — **ACCEPTED, Track A**

**Status:** Accepted · **Date:** 2026-09-07, resolved 2026-09-08 by the P0-4 spike

**Context.** The owner's first requirement is preserving the existing user interface. The UI is
12 storyboards and ~75 UIKit files, ~20k lines of Swift. A native AppKit or SwiftUI rewrite is a
large job with real visual-fidelity risk. Mac Catalyst compiles UIKit and storyboards for macOS
largely unchanged, and additionally provides `AVAudioSession`, which native macOS lacks.

The open question is whether an AUv3 app extension built for the `macabi` ABI loads and behaves
correctly across the major AU hosts, particularly under in-process instantiation.

**Decision.** Adopt Catalyst *provisionally*. Before porting any Synth One code, build a throwaway
Catalyst app + AUv3 instrument extension and validate it under `auval`, Logic Pro, Ableton Live,
and Reaper (task P0-4). Phases 1 and 2 (DSP, engine, tests) are deliberately track-independent, so
they can proceed regardless of the outcome and no work is wasted either way.

**Consequences.**
- If the spike passes (Track A): one UIKit codebase serves both the standalone app and the plugin.
- If it fails (Track B): the DSP work still stands; the UI is rebuilt in SwiftUI from the same
  asset catalog, reproducing the existing design. Phases 3–4 are re-planned.

### P0-4 spike results (2026-09-08) — **Track A confirmed**

Throwaway Catalyst app + AUv3 instrument extension (`aumu`/`spk1`/`BP03`), ad-hoc signed, no
Apple Developer account. Sources under `Spikes/P0-4-CatalystAU/`.

| Check | Result |
|---|---|
| Builds for Mac Catalyst | ✅ `vtool` reports `platform MACCATALYST` |
| Ad-hoc signing sufficient | ✅ `Signature=adhoc`, `TeamIdentifier=not set` |
| Registers with the system | ✅ `auval -a` lists it ~10s after first app launch |
| **`auval -v aumu spk1 BP03`** | ✅ **AU VALIDATION SUCCEEDED** — render at 6 sample rates, parameter set/schedule, ramped parameters, MIDI, bad-max-frames |
| Instantiates **out-of-process** | ✅ audio peak 0.394 under offline render |
| Instantiates **in-process** (`.loadInProcess`) | ✅ audio peak 0.394 — **the R-1 concern does not materialise** |
| Vends a view controller | ✅ `AUAudioUnitRemoteViewController` |
| **UIKit storyboard loads in the extension** | ✅ confirmed in-band: the extension instantiated `MainInterface.storyboard`, resolved its custom VC class, and wired 3 subviews + outlets, then reported success back through the AU parameter tree |

**Decision: Track A. Keep the existing UIKit storyboard UI and ship it via Mac Catalyst.**
Track B (SwiftUI rewrite) is not needed and is withdrawn from the plan.

**Caveat on evidence.** Automated *visual* capture of the AU's remote view failed in this
environment — `screencapture` could not image the out-of-process remote view, on either display.
The storyboard-load proof above is in-band and deterministic, but a human should still open the
plugin in Logic Pro once and look at it. `SpikeAU.app` is installed in `/Applications` for exactly
that; delete it when done.

---

## ADR-002 — Drop AudioKit; vendor Soundpipe and write our own shims

**Status:** Accepted · **Date:** 2026-09-07

**Context.** Upstream pins AudioKit 4.9.2 (2019, CocoaPods, binary-distributed). It has no Mac
Catalyst slice and no realistic path to one. But the measured dependency (see
`docs/02-audiokit-api-surface.md`) is thin glue, not architecture: logging, a tuning table, a
wavetable type, a MIDI wrapper, an `AUAudioUnit` base class, and some small UIKit views. The
actual synthesis is `S1DSPKernel`, portable Obj-C++ over Soundpipe, plus TAAE which is already
vendored in-tree.

**Decision.** Remove the AudioKit dependency entirely. Vendor Soundpipe (MIT, plain C) and
reimplement roughly 400 lines of shims ourselves.

**Consequences.** We own the glue — but we were going to own it anyway, since nobody is
maintaining AudioKit 4. Removes CocoaPods, removes the Catalyst blocker, and makes the build
reproducible on modern Xcode. Cost is concentrated in P1-3 and P1-4.

---

## ADR-003 — Generate the Xcode project with XcodeGen

**Status:** Accepted · **Date:** 2026-09-07

**Context.** The upstream `.xcodeproj` is `objectVersion = 46` (2019). The port adds targets,
removes CocoaPods, and enables Catalyst — heavy structural churn, across many sessions, much of it
done by an assistant that must hand off cleanly.

**Decision.** Declare project structure in `project.yml` and generate with XcodeGen.

**Consequences.** Project structure becomes reviewable in diffs and reconstructible from source.
Cost: XcodeGen must be installed, and anyone editing targets in Xcode's UI will lose their changes
on the next generate. Documented in `CLAUDE.md`.

---

## ADR-004 — Drop Ableton Link

**Status:** Accepted · **Date:** 2026-09-08 · **Decided by:** project owner

**Context.** `Link/ABLLinkManager.swift` (543 lines) plus `LinkExtensions.swift` target LinkKit,
Apple's iOS-only static distribution of Ableton Link. A macOS port would mean adopting the
open-source Link C++ SDK and rewriting the manager. Task P3-7 held this open.

**Decision.** Drop Ableton Link. Do not port it.

**Consequences.**
- `Link/` is not ported. `AKLinkButton` (declared inside `ABLLinkManager.swift`) and the Link UI in
  the header panel are removed, and the parity checklist marks them intentionally dropped.
- Tempo sourcing simplifies to exactly two cases: the standalone app's own clock, and the host's
  `musicalContextBlock` in the plugin (P4-5). The plugin case is the one that actually matters for
  tempo-synced arp, sequencer, LFOs and delay — which is where Link was earning its keep on iOS.
- P3-7 is closed.

---

## ADR-005 — No Apple Developer Program account for now; local-only distribution

**Status:** Accepted · **Date:** 2026-09-08 · **Decided by:** project owner

**Context.** The owner is not publishing this and does not want to take on Developer Program
signing/notarization work now.

**Decision.** Target local installation only. Sign with an Xcode "Personal Team" (free Apple ID)
for development. Phase 5's notarization and installer tasks (P5-2, P5-3) are deferred, not deleted.

**Consequences.**
- **An AU still has to be signed to register with the system**, so a free Personal Team is a real
  requirement, not optional. The P0-4 spike will confirm this end-to-end.
- **App Groups become a live question.** P3-3 assumed an App Group container for sharing presets
  and settings between the standalone app and the sandboxed AU extension. App Group entitlements
  need a Team ID; a free Personal Team generally provides one for local development, but this is
  unverified. **Verify during P0-4 — if it does not hold, P3-3 needs a different shared-storage
  design** (a common path under `~/Music/Audio Music Apps/`, or relaxing the extension's sandbox
  at the cost of `sandboxSafe`).
- The AU manufacturer code can be a placeholder, since nothing is being registered with Apple.
  Using `BP03` for consistency with the owner's other Audio Unit work; trivially changed later.


---

## ADR-006 — App Groups are unavailable without a Team ID; P3-3 needs a different design

**Status:** Accepted · **Date:** 2026-09-08

**Context.** ADR-005 (no Apple Developer account) left open whether the standalone app and the
sandboxed AU extension could share presets and settings through an App Group container, as P3-3
assumed. The P0-4 spike tested it directly.

**Findings.**
- `com.apple.security.app-sandbox` on both the app and the extension builds and runs fine under
  ad-hoc signing. Sandboxing is not the problem.
- Adding `com.apple.security.application-groups` fails the build immediately:
  `"SpikeAU" requires a provisioning profile. Enable development signing…` — for **both** targets.
- With the entitlement removed, `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil
  inside the extension, as expected.

**Decision.** Do not depend on App Groups. P3-3 must use a shared location both processes can
reach without a group entitlement. Preferred: a common directory under
`~/Music/Audio Music Apps/`, which is conventional for audio software and reachable by a sandboxed
extension given the right file-access entitlement.

**Consequences.**
- P3-3 is re-scoped: design and verify the shared-storage mechanism, do not assume a group container.
- This is reversible. If the owner ever adds even a *free* Apple ID "Personal Team" in Xcode, a
  Team ID becomes available and App Groups likely start working — worth re-testing at that point.
- Nothing else in the port depends on this.

---

## ADR-007 — Catalyst renders the iPad UI at 77%; idiom choice deferred to P3-1

**Status:** Accepted (finding); the idiom choice itself is deferred · **Date:** 2026-09-08

**Context.** The spike set `preferredContentSize` to 600×180 inside the extension. The host received
**462×138** — exactly 77%. This is Catalyst's "Scale Interface to Match iPad" idiom, which scales
all UIKit content by 0.77 on macOS.

**Why it matters.** Requirement #1 is preserving the UI. Synth One is a fixed-layout iPad design
with custom-drawn controls (StyleKit knobs, pads, keyboard). The two idioms trade off differently:

- **Scaled to match iPad (77%, the default).** Layout is preserved *exactly* — every control keeps
  its relative position and proportion. But everything renders at 77% size, so the plugin window is
  smaller than the iPad original and fine detail in the custom drawing may soften.
- **Optimize Interface for Mac (100%, Mac idiom).** Renders at true size, but UIKit substitutes
  Mac-style metrics for standard controls and changes some spacing — which can disturb a
  pixel-tuned layout.

Because Synth One draws nearly all of its own controls rather than using stock UIKit ones, the Mac
idiom may disturb less than it usually would. That is an empirical question.

**Decision.** Record the finding now; make the choice at P3-1 once the real UI compiles and both
idioms can be compared side by side against the P0-5 reference screenshots. Add it to the parity
checklist as an explicit sign-off item rather than letting the default decide silently.

---

## ADR-008 — Target graph: static libraries under one framework, and a real AU from day one

**Status:** Accepted · **Date:** 2026-09-08 (P1-1)

**Context.** The architecture called for five build targets. Two shape questions had to be settled
when actually writing `project.yml`.

**Decisions.**

1. **`Soundpipe` and `S1Support` are static libraries, not frameworks.** They link into
   `SynthOneCore.framework` and leave no artifact behind. An AUv3 extension that has to locate,
   embed and sign several dynamic frameworks is a well-known source of loading and signing
   failures, and we are ad-hoc signing (ADR-005), so we have less room for error than usual. The
   logical separation the architecture wanted is preserved — the shims still cannot depend on
   Synth One code — without paying an embedding cost for it. Verified: the built app contains only
   `Frameworks/SynthOneCore.framework` and `PlugIns/SynthOneAU.appex`, no `.a` files.

2. **`SynthOneAU` exists and is `auval`-clean from P1-1, not P4-1.** It is a structurally complete
   AUv3 that renders silence. The cost is a few dozen lines; the benefit is that AU validation
   becomes a regression check we can run at every phase rather than a cliff we walk off at P4-7.
   `Scripts/validate-au.sh` runs it. The real kernel replaces the silent render block at P4-2.

**Also settled:** `IPHONEOS_DEPLOYMENT_TARGET = 14.0` (macOS 11 under Catalyst). The spike had
silently inherited `minos 26.5` because XcodeGen's `options.deploymentTarget` does not apply when
`supportedDestinations` is used — the setting has to be given explicitly. The built app now
correctly reports `platform MACCATALYST, minos 14.0`.

**Consequence for future sessions:** XcodeGen writes its own `CODE_SIGN_IDENTITY` preset at *target*
level, which silently overrides anything set in the project-level `settings.base`. Ad-hoc signing is
therefore applied through the `AdHocSigned` target template. Do not "tidy" it up into the project
base — it will stop working.

---

## ADR-009 — Ported AudioKit code keeps its `AK` names

**Status:** Accepted · **Date:** 2026-09-08 (P1-3)

**Context.** ADR-002 dropped the AudioKit dependency, to be replaced by our own shims. That left a
naming question: rename the replacements to `S1*`, or keep the upstream `AK*` names?

The call-site counts decide it. Renaming would touch roughly **190 sites** across Synth One —
`AKLog` 120, `AKTuningTable` 34, `AKSettings` 29, `AKTable` 11 — none of which are interesting
changes. `CLAUDE.md` asks that diffs against `upstream/` stay reviewable and that this be a port
rather than a redesign.

**Decision.** Keep the upstream names: `AKLog`, `AKSettings`, `AKTable`, `AKTuningTable`,
`AK_ENUM`, and the `Frequency`/`Cents`/`MIDINoteNumber` typealiases. `SynthOneCore` re-exports
`S1Support` with `@_exported import`, so porting a Synth One source file means changing
`import AudioKit` to `import SynthOneCore` and nothing else.

**Consequences.**
- ~190 call sites port untouched; the `upstream/` diff stays about *real* changes.
- The names no longer denote AudioKit, which could mislead. Mitigated by confining them to the
  `S1Support` module and documenting provenance in `Sources/S1Support/PORTING.md`.
- No collision risk: AudioKit is never coming back (ADR-002).
- Module-scoped things we own outright still use the `S1` prefix — `S1Parameter`, `S1DSPKernel`,
  `S1AudioUnit`, `S1Engine`. The `AK` prefix marks *ported* code specifically, which is a useful
  signal in its own right.

**Discovered while implementing this:** AudioKit 4.9.2 does not compile under a modern Swift. Three
integer/floating-point narrowing errors had to be fixed (see `PORTING.md`). Had we tried to keep the
dependency, we would have been patching its source anyway — ADR-002 was the right call for a reason
better than the one originally given.

---

## ADR-010 — `AKSettings` scalars are backed by C storage

**Status:** Accepted · **Date:** 2026-09-08 (P1-4)

**Context.** `AKAudioUnit` and (at P1-5) `S1AudioUnit` are Obj-C++ and need three values from
`AKSettings`: `sampleRate`, `channelCount`, `rampDuration`. Upstream gets them from
`<AudioKit/AudioKit-Swift.h>`. Ours is a Swift class in `S1Support`, which is a **static library**
(ADR-008) — it has no Obj-C interface header that another target can reliably import.

`AKSettings` cannot simply move to `SynthOneCore` where Swift header generation is standard:
`AKTuningTableBase.NYQUIST` reads `AKSettings.sampleRate`, so it must stay in `S1Support`.

**Options considered.**
1. Promote `S1Support` to a framework — gives a proper Swift header, but adds a binary to embed and
   sign inside the AU extension, which ADR-008 deliberately avoided.
2. Import the generated `S1Support-Swift.h` by pointing header search paths at DerivedSources —
   fragile across configurations and clean builds.
3. Reimplement `AKSettings` in Obj-C — but 19 of its 29 call sites use `bufferLength`, whose Swift
   enum has computed properties that would not survive the move.

**Decision.** Keep the rich `AKSettings` API in Swift, and move the storage for those three scalars
into C (`AKSettingsBridge.h/.c`). Swift's properties become computed accessors over the C storage;
Obj-C++ calls the C functions directly. One source of truth, no module gymnastics, no extra binary.

**Consequences.**
- Swift call sites are unchanged — `AKSettings.sampleRate` still works and still reads/writes the
  same storage the DSP sees.
- Obj-C++ uses `ak_settings_sample_rate()` rather than `AKSettings.sampleRate`. That costs 2 lines in
  our `AKAudioUnit.mm` and will cost 3 in `S1AudioUnit.mm` at P1-5 — a deliberate, documented
  exception to ADR-009's minimal-churn rule, taken because the alternatives are worse.
- Only these three scalars are shared. Anything else on `AKSettings` stays Swift-only, which is
  correct: the DSP layer has no business reading UI-oriented settings.

---

## ADR-011 — Vendor AudioKit's Soundpipe fork, not canonical Soundpipe

**Status:** Accepted · **Date:** 2026-09-08 (P1-5) · **Supersedes the vendoring choice made in P1-2**

**Context.** P1-2 vendored Soundpipe from canonical upstream (`PaulBatchelor/Soundpipe`), having
checked that every `sp_*` symbol the kernel calls existed there. That check was necessary but not
sufficient: it confirmed the *names* existed, not that the *signatures and semantics* matched.

P1-5 surfaced two divergences when the real kernel was compiled against it:

1. **`sp_port`** — canonical has `smooth` and `sp_port_init(sp, p)`; the fork has `htime` and
   `sp_port_init(sp, p, htime)`. The difference equation is identical, so this was cosmetic.
2. **`sp_oscmorph2d`** — canonical does not have it at all, and the copy sitting in
   `upstream/DSP/Kernel/oscmorph2d.c` (which P1-2 vendored) is a **stale, non-band-limited**
   version. AudioKit's real one, in `Core/SoundpipeExtension/`, selects among 13 band-limited
   tables per waveform by pitch. **That is Synth One's anti-aliasing**, and the 54 JSON files in
   `DSP/BandlimitedWavetables/` exist only to feed it.

The second one is the reason this ADR exists. The stale version compiles and runs. It would have
produced a synth that aliases audibly on high notes, with no error at any point to indicate why.
`S1NoteState.mm` failing to find `enableBandlimit` is what exposed it.

**Decision.** Re-vendor Soundpipe from `AudioKit/Core/Soundpipe` + `AudioKit/Core/SoundpipeExtension`
at the pinned AudioKit revision — the exact code Synth One's sound was tuned against.

**Consequences.**
- The kernel now compiles with **no** `sp_port` or `oscmorph2d` edits. The four kernel patches made
  earlier in P1-5 were reverted.
- The fork ships an assembled `soundpipe.h`, so `Scripts/assemble-soundpipe-header.sh` from P1-2 is
  deleted.
- `soundpipe.h` declares all ~125 modules, including `sp_wavin`, so `dr_wav.h` is vendored for its
  declarations. `dr_wav.c` is not compiled and `sp_wavin` is never called.
- `CLANG_ENABLE_MODULES: NO` is needed on the Soundpipe target: `oscmorph2d.c` includes
  `soundpipeextension.h` textually, and with modules on Clang also supplies it via the module,
  defining the typedef twice.

**The general lesson, worth carrying into P2-4:** when porting against a forked dependency, symbol
presence is not compatibility. Only compiling the real client against it — or better, comparing
rendered audio — actually settles the question. P2-4's golden-WAV tests are the systematic version
of this check, and this ADR is the argument for not deferring them.

---

## ADR-012 — The framework's public header surface is declared, not defaulted

**Status:** Accepted · **Date:** 2026-09-08 (P1-6)

**Context.** P1-6 needed Swift to see `S1AudioUnit`. In a framework target Swift reaches Obj-C
only through the umbrella header, so `S1AudioUnit.h` had to become public and be listed in
`SynthOneCore.h`. Three things fell out of that, none of them obvious:

1. **XcodeGen defaults every framework header to `public`.** All 30 headers — the C++ ones
   included — were already being copied into `SynthOneCore.framework/Headers`, and clang was
   emitting 25 "umbrella header does not include header X" warnings on every build. The explicit
   `headerVisibility: public` entries already in `project.yml` were no-ops.
2. **Public headers are flattened.** `Headers/` has no `AudioKit/` subdirectory, so
   `#import <AudioKit/AKAudioUnit.h>` and `#import "AudioKit/AKInterop.h"` cannot survive in a
   header that leaves the framework.
3. **`#pragma once` keys on file identity, not path.** Inside the framework build the same header
   is legitimately reached by two paths — the source tree (for the Obj-C++ kernel) and the copied
   public header (via `<SynthOneCore/...>`) — which are two different files on disk. `#pragma once`
   would let `S1Parameter`'s 150-value enum be defined twice.

**Decision.** Declare the public surface explicitly in `project.yml` and sweep everything else to
`headerVisibility: project`. The public set is exactly `SynthOneCore.h`, `AKAudioUnit.h`,
`AKInterop.h`, `S1TestToneAudioUnit.h`, `S1Parameter.h`, `S1AudioUnit.h`. The two ported headers
that join it get framework-style imports and named include guards, marked `PORT FIX`.

**Consequences.**
- Order matters in `project.yml`: XcodeGen keeps the *first* entry that matches a file, so the
  per-file `public` entries must be listed **before** the directory that sweeps up the rest. Listed
  after, they are silently ignored and the framework ships no public headers at all — and the build
  still succeeds, because within the target Xcode's own header map resolves `<SynthOneCore/...>`
  anyway. Only an external consumer notices. This was hit and fixed during P1-6.
- The build is now warning-clean on the umbrella, so the next such warning means something.
- No `.hpp` may ever be added to `SynthOneCore.h`. Swift parses the umbrella as Obj-C; C++ in it is
  a hard error.
- P4-6 will need `AKSynthOneRate.h` or others to go public if the AU view controller reaches them;
  add to the list rather than reverting to the default.

---

## ADR-013 — Synth One sweeps into tune after `allocateRenderResources`, and that is upstream

**Status:** Accepted (observed, preserved) · **Date:** 2026-09-08 (P1-6)

**Context.** P1-6's first pitch measurements came back consistently flat and *inconsistently* so:
434.9 Hz for A440 over one window, 431 → 429.5 → 427.9 Hz over three allocate/render cycles. A
windowed measurement showed why — a note struck immediately after `allocateRenderResources` starts
around 295 Hz and glides up, reaching 440 Hz at about 0.8 s and then holding at 440.1 Hz forever.

The mechanism is entirely upstream:

- `restoreValues` → `setupParameterTree` calls `sp_port_init` for every parameter with
  `usePortamento`, and **`sp_port_init` zeroes the filter state** (`p->yt1 = 0`). So after every
  allocation each of those parameters ramps 0 → target with `S1_PORTAMENTO_HALF_TIME` (0.1 s).
- `S1NoteState::run` — which executes **once per sample per voice** — computes
  `oscmorph1->freq = oscmorph1->freq * nnToHz(semitoneOffset) * detuningMultiplier * …`, reading and
  writing the same field. It is a multiplicative accumulator.
- `detuningMultiplier` is one of the ported parameters. While it is climbing from 0 toward its
  default of 1, every sample multiplies the oscillator frequency by a number below 1, walking the
  pitch down; as the parameter settles the pitch walks back up.

**Decision.** Preserve it. This is the shipping instrument's behaviour and P1-6 is a port, not a
redesign. `S1AudioUnitRenderTests.testPitchSweepsInWhileParametersSettle` pins it explicitly so a
future change to either the portamento or the oscillator frequency path fails a test instead of
becoming a mystery; every other pitch assertion waits one second (`settleTime`) first.

**Consequences.**
- **Hosts will hear this.** `allocateRenderResources` runs on load and on every sample-rate change,
  so a note played inside the first half second of either is out of tune. Worth a look at P4-7, and
  worth remembering before "fixing" it: changing it changes the instrument.
- It is also why the earlier numbers drifted across allocation cycles — different parts of the same
  sweep, not an accumulating defect.
- Once settled the tuning is exact: an independent spectral analysis of the rendered WAV measured
  A3/C4/E4/A4 at 219.95 / 261.60 / 329.55 / 439.90 Hz, all within 0.1 Hz of 12-ET.

---

## ADR-014 — The engine is an object, not a global; and where the S1Support boundary really is

**Status:** Accepted · **Date:** 2026-09-08 (P2-1)

**Context.** AudioKit exposes one process-wide `AVAudioEngine` behind statics — `AudioKit.engine`,
`AudioKit.output`, `AudioKit.start()` — and `AKNode.init(avAudioUnit:attach:)` reaches back into it
to attach itself. P2-1 has to replace all of that.

Faithfulness argued for reproducing the global: keep an `AudioKit` shim and the ~11 upstream call
sites port unchanged. Counting them killed the argument. Five are in `Conductor.start()`, which is
the very code P2-1 replaces; two are in `Audiobus`, stubbed at P3-2; two more are the iOS-only IAA
host icon, also P3-2. Almost nothing that survives to the end actually wants a global.

Against that: a process-wide engine is a liability for P2-4, which renders twenty presets offline
and needs each render independent.

**Decision.** `S1AudioEngine` — an object you hold. No `AudioKit` type, no global engine. `AKNode`
keeps its name and shape but loses the `attach:` parameter and detaches via
`avAudioUnitOrNode.engine` rather than a singleton. `AVAudioUnit._instantiate` no longer attaches;
the engine attaches when the node is handed to it.

P4-2's "`S1Engine` abstraction (standalone vs AU)" is now an extension of this rather than an
unpicking of a global.

**A second, forced decision: `S1Support` cannot own anything that reaches Obj-C.**

The node layer was written into `S1Support` first, where the AudioKit replacements live. That broke
the build in a way worth recording. `AKSynthOne` is `@objc` and subclasses `AKPolyphonicNode`, so
Xcode emitted `AKPolyphonicNode` into `SynthOneCore-Swift.h` and, with it, `@import S1Support;` —
a module every consumer of the framework then has to resolve, and none can: **`S1Support` is a
static library** (ADR-008), so its Swift module ships with nothing.

So the line is not "AudioKit replacements go in S1Support". It is:

> `S1Support` is the **value layer** — tables, tunings, settings, logging. Nothing in it may appear
> in `SynthOneCore`'s Obj-C surface. Anything that touches `AVFoundation`'s graph, or that Obj-C
> must see, belongs in `SynthOneCore`.

`AKNode`, `AKPolyphonicNode`, `AKMixer`, `AKComponent` and `S1AudioEngine` therefore live in
`Sources/SynthOneCore/Nodes/`. One `@objc` had to go with them: `AKPolyphonicNode.tuningTable`,
because `AKTuningTable` *is* an `S1Support` type. Nothing calls it from Obj-C.

**Consequences.**
- Adding `@objc` to anything in `SynthOneCore` that mentions an `S1Support` type will break every
  consumer of the framework, with an error that points at the generated header rather than at the
  cause. `Scripts/build.sh` catches it immediately; the fix is to drop the `@objc`, not to promote
  `S1Support` to a framework (ADR-008 explains what that costs).
- `Conductor.swift` is **not** ported at P2-1. It is more UI controller than audio: bindings,
  `viewControllers`, `updateAllUI`, five panel types. Its audio half is what `S1AudioEngine` now is;
  the rest waits for Phase 3, when the types it names exist.

---

## ADR-015 — Never let the engine touch `outputNode` before choosing manual rendering

**Status:** Accepted · **Date:** 2026-09-08 (P2-1)

**Context.** The first P2-1 test to build an `AVAudioEngine` took **90.8 seconds**, reproducibly,
and every test after it in the same process took milliseconds. Timing each step located it exactly:

```
AVAudioEngine()                 0.000s
engine.outputNode              90.580s     <-- here
enableManualRenderingMode       0.000s
engine.start()                  0.001s
first renderOffline             0.001s
```

`AVAudioEngine.outputNode` lazily creates the hardware output audio unit. In a process that cannot
get an output device — an `xctest` bundle, for one — that blocks for what is plainly a 90-second
timeout and then succeeds anyway. Configuring an `AVAudioSession` first does not help (measured).

Reordering does. With `enableManualRenderingMode` as the **first** call to touch the engine, the
hardware unit is never created: **0.009 s**. The whole class went from 92.9 s to 2.3 s.

**Decision.** `S1AudioEngine.output` only records its node; the graph is built by `start()` or
`startOfflineRendering()`. `startOfflineRendering` enables manual rendering *before* building
anything, so nothing has touched `outputNode` yet.

**Consequences.**
- P2-4's golden-WAV suite renders twenty presets. Getting this wrong would have made it unusable,
  and the cause would have looked like "AVAudioEngine is slow" rather than a single ordering bug.
- The same rule matters at P4: an **AUv3 extension must never touch `engine.outputNode`.** It has no
  business opening hardware, and this is what it would cost if it did.
- Not established: whether the standalone GUI app pays this too. It has a real output device and a
  window, so probably not — but if launch is ever mysteriously slow, look here first.
- A blocked audio device shows up as *latency*, not as an error. Nothing is logged and the call
  eventually succeeds.

---

> ### ⚠️ Corrected at P3-4 — the 90 seconds was a consent prompt, not a device stall
>
> This ADR asserted that `AVAudioEngine.outputNode` blocks for 90 seconds "in a process that cannot
> get an output device", and left open whether the GUI app paid it too.
>
> **The mechanism was wrong.** The app *did* pay it — 72 seconds before its window appeared — and the
> cause was a **microphone consent dialog** sitting unanswered. Upstream's audio session category is
> `.playAndRecord`, which makes macOS ask for microphone access; the app blocks on the prompt. The
> owner supplied the missing piece: *"that's because I didn't click a button in time."* A TCC record
> for `kTCCServiceMicrophone` confirmed it.
>
> Synth One never records audio input on macOS — `S1NodeRecorder` taps the mixer's **output**, and
> Audiobus and IAA are gone (P3-2) — so the permission was being requested for nothing. The session
> is `.playback` now, the `device.audio-input` entitlement and `NSMicrophoneUsageDescription` are
> gone, and with the permission reset the app launches instantly and asks for nothing.
>
> **Re-measured in `xctest` after the change: `outputNode` costs 0.59 s, not 90.** The stall this ADR
> was built on does not reproduce.
>
> **What survives, and why this ADR is not withdrawn:**
> - *Enable manual rendering before touching the engine when you do not want hardware.* Still right on
>   its own terms — an offline render has no business opening an output device, and it keeps the test
>   suite hermetic and fast.
> - *An AUv3 must never touch `outputNode`.* Unchanged; it renders through its host.
> - *Never block the window on device setup.* Reinforced, not weakened: `Conductor.start(mode:)` now
>   starts the realtime engine off the main thread, so a slow device — or any future prompt — cannot
>   hide the UI again.
>
> The lesson is the ADR-011 one in a new costume: a reproducible measurement is not a diagnosis. Two
> systems were blocked on the same consent dialog and it looked like a CoreAudio pathology.

---

## ADR-016 — Golden renders are float32 WAVs of the real presets, and their sensitivity is measured

**Status:** Accepted · **Date:** 2026-09-08 (P2-4)

**Context.** P2-4 is the regression safety net: render N presets offline, commit the audio, compare
future renders against it. Three questions had to be answered with evidence rather than taste.

**1. Which presets?** Upstream ships 695 across 13 banks, but `Preset.swift` and the banks belong to
Phase 3, so the alternative was inventing ~20 parameter sets in the test. Inventing them tests
patches nobody plays and would have to be thrown away later. Ported the preset model instead
(see `Sources/SynthOneCore/Presets/PORTING.md`) and selected 20 real presets by greedy coverage over
23 sonic features, then spread so every bank contributes. They cover all three filter types, both
LFOs and every routing in use, arp, sequencer, mono, legato, glide, detune, FM, sub, noise,
bitcrush, phaser, delay, reverb, autopan and widen.

**2. What format?** 16-bit, to halve the 10 MB — and it failed immediately. **Four of the twenty
presets render above full scale**, loud patches through the master compressor, and integer PCM
clamps them; the worst mismatch was 1.37, entirely a clipped peak rather than any change in DSP. A
golden must record what the DSP produced, over-full-scale included, because that is the behaviour
being protected. **Float32**, 10 MB, and comparisons become exact on one machine — which leaves the
tolerance doing only the job it was meant for, absorbing arm64/x86_64 differences in a universal
binary.

**3. Does it actually catch anything?** A golden suite that never fails is worse than none, so this
was measured rather than assumed. Changing one internal LFO smoothing constant by **0.24%**
(`kLFOSmoothHalftime`, 0.0053125 → 0.0053) failed **17 of 20** presets. The three that passed are
the patches with no LFO. That is the sensitivity the suite is worth having for, and it is recorded
so a future session can re-run the same experiment after changing the recipe.

**Decision.** 20 real presets · float32 WAV · fixed rendering recipe (44.1 kHz, 512-frame blocks,
0.75 s settle, A3 at t=0, E4 at t=0.4, both released at 1.0, 1.5 s captured) · tolerance 1e-4 max
sample difference and 1e-5 relative RMS · regenerated only through `Scripts/write-goldens.sh`.

**Consequences.**
- **Determinism is a precondition and is asserted**, not hoped for. Two renders of the same preset
  are bit-identical, because each build a fresh `S1DSPKernel` and `sp_create` seeds Soundpipe's RNG
  to zero — so even presets with noise reproduce exactly. A flaky golden suite teaches everyone to
  ignore it.
- Every number in the recipe is load-bearing: change one and all twenty files are invalid. They are
  named constants with reasons in the test, not literals.
- Regenerating is deliberately awkward — one script, and a comment telling you to listen first.
- `xcodebuild` does not pass the shell environment to the test runner. `SYNTHONE_WRITE_GOLDENS=1`
  must be spelled `TEST_RUNNER_SYNTHONE_WRITE_GOLDENS=1`, or it is silently ignored and the test
  reports missing files.
- The goldens are also an *audition set*. `open Tests/Goldens` is how a human checks that an
  intended change sounds right, which is the half of ADR-011 that no assertion covers.

---

## ADR-017 — The UI ships in the framework, and the app reaches it through a façade

**Status:** Accepted · **Date:** 2026-09-08 (P3-1)

**Context.** `docs/00-architecture.md` always said the UI belongs in `SynthOneCore` — it is what
stops the app and the plugin drifting apart, and P4-6 needs the AUv3 to host the same panels.
Actually putting it there raised three questions that only appear once you try.

**1. `UIMainStoryboardFile` cannot work.** It looks in the main bundle, and `Main.storyboard` is a
framework resource. The app instantiates the storyboard itself instead — which is the same thing
the AUv3 will do, so this is the architecture rather than a workaround.

**2. Everything is `internal`, and should stay that way.** Making `Conductor` and `Manager` public
would mean `public` on every method satisfying an `@objc` protocol, and would drag `S1Support` types
into the generated Obj-C header — the failure from ADR-014. So `SynthOneApp` is the whole public
surface: `start()`, `stop()`, `makeRootViewController()`, `open(url:)`, plus two protocols the app
answers (`S1LaunchURLProviding`) and one bundle accessor. Everything else keeps upstream's access
level exactly.

**3. Storyboards record the module their classes came from.** Most entries carry
`customModuleProvider="target"` and are rewritten by `ibtool` to the compiling target's module.
Eighteen do not, and had to be edited from `AudioKitSynthOne` / `AudioKit` / `AudioKitUI` to
`SynthOneCore`. **A class that fails to resolve is not an error** — the nib silently substitutes a
plain `UIView` and every outlet is nil. `UILoadTests` asserts concrete types because of this.

**Decision.** UI in `SynthOneCore`; `SynthOneApp` as the only public entry point; the eighteen
`customModule` attributes corrected in place.

**Consequences.**
- Every `Bundle.main` in ported UI code is a latent runtime crash. Twelve were found by compiling
  and loading; `#imageLiteral` was the nastiest, because it *traps* rather than returning nil and
  took the process down from the Touch Pad panel's spark particle.
- `Bundle.synthOneCore` and `UIImage.synthOne(_:)` exist so the next such call site has an obvious
  right answer.
- P4-6 gets the AUv3 view for free: `SynthOneApp.makeRootViewController()` already loads the
  storyboard from the framework, from whichever process is asking.
- The trade is that the app target is now nearly empty — an `AppDelegate` and an entitlements file.
  That is the correct shape for a product that ships the same UI twice.

---

## ADR-018 — Shared storage: the app is not sandboxed, and the plugin half is still unsolved

**Status:** Accepted · **Date:** 2026-09-08 (P3-3) · **Resolves the question ADR-006 left open**

**Context.** Presets, tuning banks and settings have to live somewhere the standalone app and the
AUv3 can both see. They are different processes with different sandbox containers —
`com.badpackets303.SynthOne` and `com.badpackets303.SynthOne.AUv3` — so anything either writes into
its own Documents folder is invisible to the other.

App Groups are the sanctioned answer and need a Team ID, which needs a paid Developer Program
membership this project does not have (ADR-005, ADR-006).

**What was measured.** The documented fallback is a
`com.apple.security.temporary-exception.files.home-relative-path.read-write` entitlement naming one
folder. It was implemented on both targets, and the app was launched:

```
path=/Users/…/Library/Application Support/SynthOne
create=FAILED NSCocoaErrorDomain 513 … NSPOSIXErrorDomain 1 "Operation not permitted"
exists=false
```

**The entitlement is present in the ad-hoc signature and the sandbox refuses the write anyway.**
`codesign -d --entitlements -` confirms it is there. Temporary exceptions need to be authorised by a
provisioning profile, and ad-hoc signing has none. Removing the sandbox, same code, same path:
`create=ok`.

*(A first run of this experiment appeared to show the same denial for the unsandboxed build. It was
wrong: the previous instance was still running, so `open -a` activated it rather than launching the
new binary. `pkill` first. Noted because it very nearly went into this ADR as a finding.)*

**Decision.**

- **The standalone app is not sandboxed.** It is local-only and unsigned by choice (ADR-005), so
  there is no App Store requirement to sandbox it, and sandboxing costs the shared folder. Presets,
  banks and tunings live in `~/Library/Application Support/SynthOne/`.
- **The AUv3 stays sandboxed.** An audio unit loaded into someone else's DAW is exactly the thing
  that should be, and it does nothing yet.
- **Therefore the plugin cannot read the app's presets, and that is not solved.** Stated plainly
  rather than papered over.

**Consequences.**
- `Disk.realHomeURL` comes from `getpwuid`, not `NSHomeDirectory()` — the latter answers the
  *container* inside a sandbox and cannot name anything outside one. That stays correct whether or
  not the sandbox is on.
- **Migration runs once, from an explicitly named path.** Everything the app wrote while sandboxed
  is moved out of `~/Library/Containers/<bundleID>/Data/Documents`. It cannot ask `FileManager` for
  "the Documents directory", because unsandboxed that is the user's own `~/Documents` — which this
  must never touch. Verified end to end: 15 files moved, existing files not overwritten, non-JSON
  left behind.
- Re-enabling the sandbox is a one-line change in `project.yml`; the entitlements it would need are
  still listed there.
- **P4-1 has a question to answer:** whether an ad-hoc-signed audio-unit extension can be
  unsandboxed at all, and whether hosts will still load it. If it can, both halves work. If it
  cannot, the plugin either ships with factory presets only, or the project buys a Team ID and this
  ADR is superseded by an App Group.


---

> ### Answered at P4-1 — see ADR-020
>
> This ADR's closing question ("whether an ad-hoc-signed audio-unit extension can be unsandboxed at
> all, and whether hosts will still load it") is settled: **it cannot.** With the sandbox off, macOS
> refuses to open the component — `auval` fails at `OpenAComponent: result: 4` and the extension is
> never instantiated. The plugin therefore ships factory presets only. ADR-020 has the measurements.

---

## ADR-019 — A resizable window scales the interface; it does not relayout it

**Status:** Accepted · **Date:** 2026-09-08 (P3-6b) · **Bears on ADR-007**

**Context.** The owner asked for a window that resizes by dragging its bottom-right corner. Catalyst
will happily do that — but what happens to the interface inside is a real choice.

Synth One's twelve storyboards place **every control by hand** at 1024×768. There are no stack
views, no size classes, no adaptive layout of any kind underneath. Letting UIKit relayout at a new
window size does not rearrange anything intelligently; it leaves controls pinned to whichever edge
their constraints happened to reference, opens gaps between panels, and pushes the keyboard off the
bottom. That is the opposite of hard requirement 1, *preserve the user interface*.

**Decision.** `S1ScalingContainer` holds the interface at its exact design geometry and applies a
uniform `CGAffineTransform` to fit the window — like a plugin GUI. Every proportion, gap and knob
size stays as designed; only the overall size changes. Scale is `min(width, height)` so it always
fits and never crops, the result is centred, and the leftover on a non-4:3 window is filled with the
panel background colour so it reads as part of the instrument.

**Consequences.**
- **The window is genuinely resizable**, from half the design size (below which labels stop being
  readable) to three times it, and it opens at 1:1.
- **Hit-testing goes through the transform**, so controls stay live and land where they look. Tested.
- **The order of operations matters and is a real trap**: the transform has to be cleared before
  setting the frame, or UIKit interprets the frame in the *scaled* space and the view creeps on
  every layout pass. A live window drag is a great many layout passes.
  `testRepeatedLayoutDoesNotDrift` exists for exactly this.
- Text is resampled when scaled rather than re-rendered at the new size, so it is slightly soft away
  from 1:1. That is the price of preserving the layout exactly, and it is the same price every
  plugin GUI pays.
- **This makes P3-1b less pressing.** ADR-007's question — iPad-scaled 77% versus
  Optimize-for-Mac 100% — was partly about the interface being stuck at one wrong size. It is not
  stuck any more: it opens at 1:1 and the owner can set whatever size suits their display. The
  decision now only concerns Mac control metrics and the appearance of native controls, not scale.
- P4-6 gets the same behaviour for free: a plugin window in a DAW is resizable too, and the AUv3
  view can wrap the same container.

---

## ADR-020 — An AUv3 extension must be sandboxed, so the plugin ships factory presets only

**Status:** Accepted · **Date:** 2026-09-08 (P4-1) · **Closes the question ADR-018 left open**

**Context.** ADR-018 ended with a question for P4-1: *can an ad-hoc-signed audio-unit extension be
unsandboxed at all?* If it could, the plugin and the app could share one preset folder without a
Team ID. Everything about whether to buy a Developer Program membership hung on it.

**What was measured.** All three routes, on the real extension, with a probe it writes when a host
instantiates it.

**1. Sandboxed, reading the shared folder** — what ADR-018 assumed, now confirmed:

```
home=~/Library/Containers/com.badpackets303.SynthOne.AUv3/Data
sharedExists=true          ← it can stat the folder
canListShared=-1           ← it cannot list it
readSettings=FAILED … you don’t have permission to view it
```

**2. Unsandboxed** — `com.apple.security.app-sandbox: false`, rebuilt, reinstalled:

```
auval -v aumu aks1 BP03
FATAL ERROR: OpenAComponent: result: 4
```

**The system refuses to open the component at all.** The extension is never instantiated — the probe
does not run. macOS requires app extensions to be sandboxed; this is not an ad-hoc-signing
limitation but a platform rule, and no entitlement gets around it.

**3. Sandboxed, reading its own framework bundle** — the fallback:

```
bundleURL=SynthOneCore.framework
banks=true   wavetables=true   storyboards=true
```

**Decision.** The extension stays sandboxed. **The plugin cannot reach the app's preset folder
*implicitly*.**

> ### ⚠️ Corrected the same day — "cannot see the user's presets" was too strong
>
> The owner asked the obvious question: *why can't a user save a preset to their own folder and have
> the plugin read it from there?* They are right, and the first draft of this ADR overstated the
> problem by conflating **implicit** access with **any** access.
>
> A sandbox blocks a process from reaching paths *on its own*. It does not block a path the **user
> explicitly hands it**: `UIDocumentPickerViewController` grants access to whatever the user
> chooses, and a **security-scoped bookmark** makes that grant survive relaunches. This is the
> sanctioned mechanism, not a loophole.
>
> Better still, the grant covers a **directory**: pick `~/Library/Application Support/SynthOne/`
> once and the plugin can read every preset in it from then on — including new ones the app writes
> later. One user action, not one per preset.
>
> `PresetsViewController` already has the import code (`Presets+UIDocumentPickerDelegate.swift`
> reads straight from a picked URL), so this is mostly wiring, not new work.
>
> **What is added now:** `files.user-selected.read-write` and `files.bookmarks.app-scope` on the
> extension. `auval` still passes with them.
>
> **What is not yet established, and must not be assumed** — this session has already produced two
> entitlements that looked right and were ignored:
> 1. whether `UIDocumentPickerViewController` can be presented from inside an AUv3 extension at all;
> 2. whether security-scoped bookmarks resolve under **ad-hoc signing**.
>
> Both need the plugin to have a UI, so they are **P4-6's** to test. Until then the honest statement
> is: *the plugin ships factory presets, and a user-selected route very probably works.*

**Consequences.**
- **This is a smaller loss than it first appears.** All 695 factory presets across 13 banks are
  framework resources and load fine, as are the wavetables and the storyboards — so the plugin gets
  the full instrument and the full UI (P4-6). What does not cross *automatically* is user-saved
  presets, and the correction above describes the route that very likely carries them.
- **Per-session state is unaffected.** P4-4's `fullState` is how a host stores a patch in its
  project file, and that has nothing to do with the filesystem. A user who tweaks a sound inside
  Logic keeps it in that Logic project regardless.
- **The Team ID question is now answerable on its merits.** An App Group is the only thing that
  would let user presets cross *without the user doing anything*; the picker route costs one
  deliberate action instead, and a paid membership buys away that action. That is a product decision, not a
  technical unknown — and it can be taken later without changing any code beyond
  `Disk.sharedSupportURL` and two entitlement files.
- The alternative for a determined user is exporting a preset from the app and importing it in the
  plugin through the document picker, which already exists in `PresetsViewController`. Not tested.
- `Sources/SynthOneAU/SynthOneAU.entitlements` carries the reasoning, and
  `AudioUnitPackagingTests.testExtensionIsSandboxed` fails if anyone flips it.

---

## ADR-021 — The render-thread crash that looked like a slow `auval`

**Status:** Accepted (bug fixed, lesson recorded) · **Date:** 2026-09-08 (P4-2)

**Context.** With the real `S1AudioUnit` vended by the plugin (P4-2), `auval` stopped finishing. It
had passed every render test at every sample rate, printed *"Checking parameter setting"*, and then
produced no further output for **two and a half hours**.

I told the owner it was slow because it now tests 150 parameters where the stub had none. That was
a guess, and it was wrong. They asked why it would take so long, which was the right question.

**Diagnosis.** Three facts, in order:

1. The process was at **0.0% CPU** and its output file had not been written to for 2.5 hours. Not
   slow — **blocked**.
2. `sample` showed the main thread in
   `-[AUAudioUnit_XPC internalRenderBlock] → audioipc::…::signal_wait()`: waiting on an XPC reply
   from the extension process that never came.
3. `~/Library/Logs/DiagnosticReports/SynthOneAU-*.ips` — the **extension had segfaulted**, at
   exactly the second `auval`'s output stopped. `EXC_BAD_ACCESS` in `S1DSPKernel::process` on the
   `AUOOPRenderingServer` thread.

**The bug**, in `DSPKernel::processWithEvents` — Apple sample code as vendored by AudioKit:

```cpp
AUAudioFrameCount const framesThisSegment = AUAudioFrameCount(event->head.eventSampleTime - now);
if (framesThisSegment > 0) { process(framesThisSegment, bufferOffset); … }
```

`eventSampleTime - now` is a **signed** `AUEventSampleTime`. `AUAudioFrameCount` is **unsigned**. A
parameter scheduled at or before `now` — which is exactly what `AUEventSampleTimeImmediate`
produces, and therefore what *every host automation move* produces — makes that difference negative,
and the cast turns it into ~4 billion. `framesThisSegment > 0` is then true, and `process()` writes
four billion frames into a 4,096-frame buffer.

**Why it had never fired.** Synth One never implemented the AU parameter tree —
`///auv3, not yet used` is still in `S1AudioUnit.h`. This code has therefore never run in the
instrument's history, on any platform. P4-2 is the first time a parameter event reached it.

**Decision.** Clamp both ends: an event at or before `now` is due immediately (zero frames), and an
event scheduled beyond this buffer cannot make us render past its end. `auval` now completes in
**2 seconds** with all 150 parameters tested and no extension crash.

**Consequences.**
- **Three lessons, and only one is about the code.**
  1. *A hang is not slowness.* 0% CPU distinguishes them in one command, and it should have been the
     first thing checked rather than the fourth.
  2. *An out-of-process AUv3 turns a crash into a hang.* The host blocks forever on an XPC reply,
     and nothing in its output says "the plugin died". **Always check
     `DiagnosticReports` for the extension**, not just the host.
  3. *Vendored sample code is not tested code.* This is the same shape as ADR-011 and the P3-1
     assertion bug: upstream shipped it, so it looked proven, and it had simply never executed.
- **The plugin still ignores host automation.** `S1DSPKernel::startRamp` is `{}` — an empty
  function. The events now arrive safely and are discarded. Implementing them is **P4-3**, and
  `PluginRenderTests.testParameterEventInThePastDoesNotOverrunTheBuffer` pins the current no-op so
  P4-3 has to change it deliberately rather than discover it.
- `auval` is now a genuine per-phase check for the plugin, as it has been for the shell since P1-1.

---

## ADR-022 — Host automation applies whole, notifies the main thread, and ignores `duration`

**Status:** Accepted · **Date:** 2026-09-08 (P4-3)

**Context.** `S1DSPKernel::startRamp` was an empty function, so the plugin received every host
automation move on the render thread and discarded it (ADR-021). Implementing it is one line —
`setSynthParameter((S1Parameter)address, value)` — but that line inherits two behaviours upstream
never had to think about, because upstream's only caller of `setSynthParameter` was the main thread.

**Decision 1 — `notifyMainThread` stays `true`.** `setSynthParameter` is
`_setSynthParameterHelper(param, value, /*notifyMainThread=*/true, 0)`, and for eight of the 150
parameters that flag posts a message to TAAE's main-thread endpoint from the render thread.

The cheap-looking option is to pass `false`. It is the wrong one. For 142 parameters the flag does
nothing at all, so it costs nothing; for the other eight — `lfo1Rate`, `lfo2Rate`,
`autoPanFrequency`, `delayTime`, `pitchbend`, `arpSeqTempoMultiplier`, and
`tempoSyncToArpRate`/`arpRate`, which re-drive the first four — `_rateHelper` **quantizes** the
value it is handed to the nearest musical division. The value the DSP ends up with is therefore not
the value the host wrote, and this notification is the only channel that reports which one took
effect. Suppressing it does not save work on the parameters that matter; it makes the UI wrong
about them.

The endpoint is a lock-free ring buffer, so the write is safe from the render thread. It is
best-effort: if the buffer is full the message is dropped and that UI update is missed. Under
saturation the cost is a stale knob for one automation frame, not a glitch — and the next event
re-sends the current value anyway.

**Decision 2 — `duration` is ignored.** `AKAudioUnit.setUpParameterRamp` computes a ramp duration
from `AKSettings.rampDuration` and passes it through `scheduleParameterBlock`, so `startRamp`
receives a non-zero `duration` on every automation move. It is dropped.

The kernel already smooths. 46 of the 150 parameters have `usePortamento`, and the render loop runs
`sp_port_compute` on each of them **every sample** against `portamentoHalfTime`
(`S1DSPKernel+process.mm`). Honouring an AU ramp as well would put a second smoother in series with
the first, so automating a filter cutoff would lag twice and by an amount that depends on a setting
(`AKSettings.rampDuration`) no user can see. The other 104 parameters step — which is exactly what
they do today when the standalone's UI sets them, so automation and the UI now behave identically.

**Decision 3 — the address is bounds-checked.** `s1p` and `parameters` are fixed 150-element
arrays and the address arrives from the host, unvalidated by anything between `scheduleParameterBlock`
and the kernel. An address past the end is an out-of-bounds read *and write* on the render thread.
Guarded in `startRamp`, which is where host-supplied data enters the kernel.

**Decision 4 — `arpRate` and `tempoSyncToArpRate` declare their dependents.** Upstream passed
`dependentParameters:nil` for all 150, which was harmless while the tree was never automated.
It is not harmless now: `_setSynthParameterHelper` re-drives `lfo1Rate`, `lfo2Rate`,
`autoPanFrequency` and `delayTime` whenever either of those two changes, so **one host automation
move alters five values in the DSP**. A host that did not know would keep displaying, and on its
next pass write back, four values it did not know were stale.

Declaring the dependency is the AU-idiomatic answer and cannot feed back: the host re-*reads* the
dependents through `implementorValueProvider`, which returns `getSynthParameter` — the quantized
truth — rather than being handed a new value to write. Writing back into `AUParameter.value` from
the DSP would have been the alternative, and it is the one to avoid: every such write re-enters
`implementorValueObserver` and, in a host in write or latch mode, reads as a fresh automation
write by the user.

**Consequences.**
- `auval` still passes, and now takes **~8 seconds** rather than 2. That is real work, not the
  ADR-021 hang: *Checking parameter setting* now applies all 150 parameters and re-renders. Check
  CPU before assuming otherwise.
- `PluginRenderTests.testParameterEventInThePastDoesNotOverrunTheBuffer` now asserts the value
  **was** applied. It remains the ADR-021 buffer-overrun regression test.
- The standalone is unaffected: `AKSynthOne` sets parameters through
  `internalAU.setSynthParameter(_:value:)` on the main thread and never touches the tree, so the
  golden renders are unchanged — verified, all 20 still pass.
- **A test trap worth knowing.** `scheduleParameterBlock` hands its event to the *framework*, and
  it is `AUAudioUnit.renderBlock` that drains the pending list into `internalRenderBlock`'s
  `realtimeEventListHead`. Driving `internalRenderBlock` directly — which the ADR-021 tests must do,
  because forging a timestamp in the past is otherwise impossible — silently delivers no scheduled
  parameters at all, and looks exactly like `startRamp` still being a no-op. It cost a full test
  round trip here.
- Not addressed, and not automation's problem: `_setSynthParameterHelper` feeds
  `updatePortamento(getParameter(portamentoHalfTime))`, and `getParameter` returns the *ramping*
  value rather than the portamento target, so setting `portamentoHalfTime` applies the previous
  value. Upstream behaviour; changing it would move the goldens. Recorded, not fixed.

---

## ADR-023 — P3-1b: Optimize Interface for Mac, and the switch is a device family

**Status:** Accepted · **Date:** 2026-09-08 (P3-1b) · **Supersedes the open question in ADR-007**

**Decision.** The owner chose **Optimize Interface for Mac**. The app and the extension render at
100% in the Mac idiom rather than the iPad layout scaled to 77%.

**How it is actually set — and four things it is not.** This cost more time than the decision did,
so it is written down rather than left to the next person:

- It is **`TARGETED_DEVICE_FAMILY`**, in `project.yml`. Family **6 is Mac**; adding it is what
  Xcode's General tab writes for "Optimize Interface for Mac". `"2,6"` (iPad + Mac).
- The built `Info.plist` is where it becomes visible, as `UIDeviceFamily`. **The app's collapses to
  `[6]` and the extension's stays `[2, 6]`** — different arrays, same meaning. The invariant that
  decides the idiom is the presence of 6, and that is what the test asserts.
- It is **not `UIDesignRequiresCompatibility`**. That key exists, and it is tempting, and it is
  unrelated: it sits beside `SupportsSolarium` in SwiftUI's binary and concerns the macOS 26 design
  system, not Catalyst scaling. Setting it to `false` changed nothing, which is how we found out.
- It is **not a `MACCATALYST_*` build setting**. The only ones the toolchain defines are
  `SUPPORTS_MACCATALYST`, `IS_MACCATALYST` and `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER`.
- It is **not editable in `Sources/*/Info.plist`**. Those files are *generated* by XcodeGen from
  `project.yml`, exactly like the `.xcodeproj`. A hand edit survives until the next `xcodegen
  generate`, which is to say until the next build.

**Verification.** Measured, not inferred. A launched build logs
`UITraitCollection.current.userInterfaceIdiom` as **5 (`.mac`)**; before the change it was
**1 (`.pad`)**. `AudioUnitPackagingTests.testBothBundlesUseTheMacIdiom` pins the built plists so the
setting cannot be dropped silently — a reverted idiom looks like nothing at all in a diff.

**Consequences.**
- A unit test **cannot** assert the running idiom. `SynthOneTests` has no test host, so it runs in
  `xctest`, whose own bundle decides the idiom — the first probe reported `.pad` no matter what the
  app was built with. The pin has to read the built product's plist, and the runtime confirmation
  has to come from a launched app.
- **The plugin's half is unverified.** The extension has the same setting, but it has no UI until
  P4-6, so nothing has drawn with it. P4-6 must confirm the panel is 100% inside a host and that the
  standalone and the plugin are the same size.
- **The visual sign-off against `docs/reference/appstore/` remains the owner's.** A smoke check of
  the launched app shows every panel still drawing and no obvious layout damage, which is what the
  automated side can honestly claim; whether the Mac metrics disturbed a pixel-tuned layout is a
  judgement about appearance, not a measurement.

---

## ADR-024 — Host state: what the parameter tree does not carry, and 695 presets in one menu

**Status:** Accepted · **Date:** 2026-09-08 (P4-4)

**Context.** A host has to save a session and get the same sound back, and offer the instrument's
own presets in its own menu. `AUAudioUnit` gives a default `fullState` that serialises the
`AUParameterTree` and nothing else.

**Decision 1 — `fullState` adds the tuning table, and nothing else.** The default is *almost*
sufficient here, which is worth stating precisely because the obvious reading of the code says
otherwise. All 150 parameters ride along, and that includes the 48 sequencer values
(`sequencerPattern00…15`, `sequencerOctBoost00…15`, `sequencerNoteOn00…15`) — they look like
separate state, and `Preset+Synth.swift` sets them through `setPattern(forIndex:)` rather than by
name, but they are contiguous parameter addresses.

What is genuinely outside the tree is the **tuning table**: 128 arbitrary frequencies the Tunings
panel can load from a Scala file, with no address and nothing to derive them from. Saved as
`NSData` rather than 128 `NSNumber`s — a quarter of the size in every session file that ever saves
this plugin, and bit-exact. Plus the notes-per-octave and a schema version.

Every read on restore is defensive. The dictionary came from a file some *previous build* wrote, and
a session saved before this change has none of these keys; a missing or malformed value is a
default, never a refusal to open.

**Decision 2 — `fullStateForDocument` is not overridden.** Its default forwards to `fullState`, and
this instrument has nothing it would save differently in a document: no file references, no absolute
paths, no machine-specific state. Overriding it to do the same thing twice is a second place to
forget to add a key.

**Decision 3 — all 695 presets, not a curated bank.** 695 is a lot for one flat menu, and the
alternative was to expose only the Starter Bank. Rejected: the banks *are* the instrument, hosts let
you scroll and search a preset list, and a plugin that silently offers 5% of what the app offers is
the more surprising outcome. Names are `Bank: Preset`, so a host's alphabetical list groups by bank
on its own.

**The numbering is a compatibility surface.** A host writes the preset *number* into its session
file, so `S1FactoryPresets.bankOrder` cannot be reordered once anything has been saved — doing so
silently repoints every saved session at a different sound, with no error and no migration.
Appending is safe. `supportsUserPresets` is `YES`, which costs nothing beyond a correct `fullState`
and is what gives a host any way to keep a sound outside the session that made it.

**Decision 4 — `Preset.apply(to:)` targets a protocol, not `AKSynthOne`.** The plugin is handed a
bare `S1AudioUnit` with no node wrapper, and duplicating that hundred-line mapping to serve it would
be two places to get the order wrong — and the order matters (`_rateHelper`). One-line signature
change; `AKSynthOne` conforms unchanged.

**Consequences.**
- **A real bug, found by testing the right thing.** The round-trip test renders the restored unit
  and compares audio sample-for-sample rather than comparing dictionaries — and it failed.
  `allocateRenderResources` calls `S1DSPKernel::init`, which rewrites all 128 tuning entries back to
  12-ET. Upstream snapshotted `parameters` around that call but not the tuning table, and the gap
  was invisible because the standalone's Tunings panel re-applies the tuning from the UI after the
  engine starts. A plugin gets no second chance: the host restores `fullState` and then allocates.
  Now snapshotted the same way parameters are. A dictionary-comparison test would have passed.
- The tests also pin that the comparison *can* fail — a restore that quietly did nothing would pass
  a test that only compared a unit against itself.
- **A second, pre-existing bug surfaced and is not fixed** — the message-queue lifetime crash. See
  STATE.md's Known issues; it is its own task, not P4-4's.
- `S1AudioUnit` is Obj-C++ and the preset codec is Swift, so they meet at an Obj-C protocol
  (`S1FactoryPresetSource`) rather than by one importing the other — importing
  `SynthOneCore-Swift.h` into the audio unit is exactly what ADR-014 rules out. The consequence is
  that the source must be *installed*, and a unit without one reports no factory presets, which is
  legitimate for an AU and therefore silent. The extension's factory is pinned by a test that reads
  its source, which is weaker than exercising it and is labelled as such.

---

## ADR-025 — Host tempo is `arpRate`, and the render thread posts to an immortal relay

**Status:** Accepted · **Date:** 2026-09-09 (P4-5)

### Tempo: the question was already answered upstream

`handleTempoSetting` stored the host tempo and did nothing with it, under two upstream TODOs —
`//TODO:set s1 param arpRate` and `// TODO: reset secPerBeat here?`. Both are answered by upstream's
**own Ableton Link listener**, which is where a tempo came from on iOS:

```swift
ABLLinkManager.shared.add(listener: .tempo({ bpm, quantum in
    self.tempoStepper.value = bpm
    self.conductor.synth.setSynthParameter(.arpRate, bpm)
}))
```

So a host tempo **is** `arpRate`. Link is dropped (ADR-004), which is exactly why the work landed
here. There is no "secPerBeat" to reset: the sequencer's clock is
`mBeatTime += (arpRate / 60) / sampleRate`, measured in beats, so setting `arpRate` is the whole of
it. Setting it also re-drives the four tempo-synced parameters through `_rateHelper` (ADR-022),
which is the point — a tempo change must re-quantize everything synced to it.

### Transport: only the stop edge, and deliberately not beat-locked

On stop: release every sounding voice and rewind the sequencer to step 0. Nothing on start.

**Not done: forcing the sequencer's position from the host's beat position.** It is the obvious
"correct DAW behaviour" and it is wrong here. `S1Sequencer::process` resets `mBeatTime` to 0 whenever
held keys go from none to some, so the arpeggiator starts **when you play** rather than on the bar
line. That is upstream's design and it is what makes a held-chord arpeggiator feel responsive.
Repeatability in an offline bounce survives anyway, because the thing that sets the phase — the
note-on — arrives at the same place every time.

**Two traps in the obvious implementation**, both found by testing rather than reading:

- **`reset()` is not a release.** Its header says "Puts all notes in release mode"; it calls
  `S1NoteState::clear()`, which sets `amp = 0` outright. Every sounding voice would stop mid-cycle
  and click. The transport stop instead sets `stage = stageRelease` and `internalGate = 0` — the two
  lines `turnOffKey` uses — without its held-note bookkeeping, because `heldNoteNumbers` is a
  main-thread `NSMutableArray` and this runs on the render thread. `stopAllNotes()` is unusable here
  for the same reason.
- **`S1Sequencer::reset(bool)` does not rewind.** It clears the pending-note vectors and leaves
  `mBeatTime` and `mStepCounter` untouched — which means `S1DSPKernel::resetSequencer` never rewound
  anything, despite the name. Upstream only ever rewound on the held-keys edge inside `process`.
  Added `resetPosition()`, which is what the name promised.

### The message-queue lifetime crash, fixed

Opened at P4-4 as a known issue and deferred; it took the test runner down a second time at P4-5, so
it is fixed here rather than worked around again.

`AEMessageQueuePerformSelectorOnMainThread` stores its target as a **raw pointer** in a lock-free
ring buffer — retaining on the render thread is not real-time safe — and `AEMainThreadEndpoint`
delivers it later through `dispatch_async`. A unit destroyed in between left the handler calling
`objc_retain` on freed memory. Upstream never met it: one synth, alive for the life of the app.

**Fix.** The render thread addresses an **`S1MessageRelay`**, which holds a *weak* reference to the
audio unit and is **deliberately never deallocated** — each unit's relay is retained in a static
array for the life of the process. A message that arrives after its unit has gone finds `unit == nil`
and does nothing. The cost is a few dozen bytes leaked per audio-unit instance, against a
use-after-free on the render path.

Rejected: retaining the target when enqueuing (not real-time safe, which is why it is a raw pointer
in the first place), and draining in `dealloc` (blocks already handed to the main queue run *after*
dealloc returns, so it closes nothing).

**The regression test does not test the crash, and says so.** The first version generated a backlog,
dropped the unit without draining, and then ran the main queue — and it **passed against the unfixed
code**, because the freed memory had not been reused yet. A use-after-free is not deterministic. The
tests that shipped check the *mechanism* instead: the relay outlives its unit, its reference is weak
so it reads `nil`, every posted selector is a no-op on a gone unit, and messages still arrive while
the unit is alive.

---

## ADR-026 — The Mac idiom never calls `touchesBegan` on a `UIButton`

**Status:** Accepted (bug fixed, lesson recorded) · **Date:** 2026-09-09 (P4-6)

**Context.** The owner reported that the `Hide` button did nothing, and later that `Wheels` did not
either — while knobs, the Octave stepper and the toggles all worked.

**Diagnosis, from the correlation rather than from reading.** Every dead control was a `UIButton`
subclass. Every working one — `Knob`, `Stepper`, `ToggleButton`, `ToggleSwitch`, `KeyboardView` — is
a `UIView` subclass with its own touch handling. That split is the whole answer.

Under **Optimize Interface for Mac** (ADR-023, adopted the previous day) UIKit backs `UIButton` with
an AppKit cell — `UIButtonMacIdiomCell`, `UIButtonMacVisualProvider`, both visible in UIKit's
binary — and the click is handled there. **A `touchesBegan` override on the subclass simply stops
being called.** Nine control classes were handling input that way; six of them were real buttons and
went silently dead the moment the idiom changed.

**Decision.** Every `UIButton` subclass handles presses through a `.touchUpInside` target action,
which both idioms deliver. `SynthButton.pressed()` is the single overridable hook; `MIDISynthButton`
and `PresetUIButton` override it, and `FilterTypeButton` and `HeaderNavButton` have their own.

**Two bugs fixed for the price of one.** Upstream called the callback from **both** `touchesBegan`
and `touchesEnded`, so every tap ran it twice. On the keyboard toggle that meant running the
animation and saving app settings twice per click. Invisible on an iPad; still wrong.

The value now changes on release rather than on press, which is standard for a button and lets a
press be cancelled by dragging off it.

**Consequences.**
- **The affected set was three times what was reported.** The owner saw two dead buttons; a test
  that greps for `UIButton` subclasses overriding `touchesBegan` found `FilterTypeButton`,
  `PresetUIButton` and `HeaderNavButton` as well — the filter-type selector, the preset list buttons
  and the header navigation. None had been tried yet.
- That grep is now a test, so no `UIButton` subclass can go back to `touchesBegan`. Its first
  version matched the word anywhere and flagged three view controllers whose `touchesBegan` is on
  their own view, which is a `UIView` and still works; it matches a class *declaration* now.
- **A host-less test bundle cannot press a button.** `UIControl.sendActions(for:)` dispatches
  through `UIApplication.shared`, which does not exist there, so the action silently never runs —
  the same family as `NSApplication has not been created yet` from ADR-023. The tests assert the
  wiring structurally and the behaviour by calling the action; delivering the event is UIKit's job,
  and the point of the fix is that it now uses an event UIKit delivers in both idioms.
- **The lesson is the same one as the `Octave:` stepper, in reverse.** There, two sessions of code
  reading produced three wrong hypotheses and one owner sentence settled it. Here, one *pattern* in
  the owner's two reports — both buttons, neither a knob — was worth more than any amount of
  staring at `KeyboardShowButton`. The first two sessions on `Hide` had inspected the button, the
  storyboard, the constraint and the layout engine. All of it was working.


---

## ADR-027 — Host tempo is authoritative over `arpRate`, and the change detector was wrong

**Status:** Accepted (bug fixed) · **Date:** 2026-09-09 (P4-6) · **Amends ADR-025**

**Context.** ADR-025 wired the host's tempo to `arpRate`, following upstream's Ableton Link
listener. The implementation was `if (currentTempo != tempo) { … }`, comparing against a `tempo`
member **initialised to 120**.

**The bug the owner caught.** Logic's default project tempo is 120. `120 != 120` is false, so
`arpRate` was never set — the one tempo that had to work was the only one that did not. Every other
project tempo worked, which is why it survived a test suite, an `auval` run and a host session.

Worse, I had read `tempo=100.0` out of a diagnostic log and reported it as *confirmation* that the
binding worked end to end. It was the opposite: 100 was the loaded preset's own `arpRate`, and its
presence was the evidence that the host tempo had never been applied. The owner corrected it with
one sentence — "Logic's project tempo is 120 by default".

**Decision.** Compare against **`arpRate` itself**, not against the last tempo seen:

```cpp
const float target = clampedValue(arpRate, currentTempo);
if (getSynthParameter(arpRate) == target) { return; }
```

This fixes a second bug in the same line. Even once the old check had fired, loading a preset writes
the preset's own `arpRate`, and a host tempo that had not changed since would never correct it —
so a preset could silently leave a plugin's arpeggiator running at the wrong tempo. Comparing
against the value that actually matters makes the host **continuously authoritative** and
self-correcting.

The clamp comes first so a project tempo outside `arpRate`'s range settles at the bound instead of
being re-applied every render block, which would re-drive four dependent parameters and post a
main-thread message thousands of times a second. A test pins that.

**Consequences.**
- `arpRate` is effectively read-only in a plugin: the host owns tempo, and anything that moves it is
  corrected on the next block. That is what "the plugin's tempo should match Logic's" means, and it
  is what Link did on iOS.
- The tests were verified by **reverting the fix and watching them fail** with the owner's exact
  symptom (`100.0` where `120.0` was expected). That step was skipped on the message-queue fix
  earlier the same day, where the "regression test" passed against the unfixed code — see ADR-025.
- **A default value that matches a common real value makes a change detector lie.** `tempo = 120.f`
  looked like a harmless initialiser. Sentinels for "not yet known" should be impossible values.


## ADR-028 — The plugin's waveform: the render thread pushes, the interface pulls

**Status.** Accepted (P4-6). 2026-09-09.

**Context.** The Generators panel has a small animated waveform under the volume knob. It is drawn
by `AKNodeOutputPlot`, which calls `AVAudioNode.installTap` and draws whatever the tap hands back.

That has no meaning in a plugin. The host owns the graph and pulls `internalRenderBlock` directly;
there is no `AVAudioNode` on our side to tap, and an AUv3 must never reach for one (ADR-015). At
P4-6 the plugin's plot was therefore built as `AKNodeOutputPlot(nil)` — a live view over nothing,
so that `GeneratorsPanelController` could keep force-unwrapping it — and it drew a flat line. That
was recorded at the time and it was still the wrong answer: the owner asked for the waveform, and
"a plugin has no node" is an implementation detail, not a reason the user should see less.

The obvious fix is to reuse the tap's shape from inside the render block. It cannot be done. The
tap callback allocates an array and `dispatch_async`es it; both are forbidden on a render thread,
and this project has already paid for one render-thread shortcut (ADR-025, a use-after-free that
took the test runner down twice).

**Decision.** Invert the direction. The audio unit keeps a fixed 1,024-sample ring — `S1Scope`, in
`S1AudioUnit.mm` — that the render thread writes into and the interface reads from on its own
schedule:

- The render thread calls `push` with the buffer it is about to hand the host. No allocation, no
  locks, no unbounded work: a bounded copy into storage the unit already owns.
- The plot runs a 30 Hz `CADisplayLink` and calls `copyScopeSamples:count:`, which fills a
  preallocated buffer.
- The two are separated by a **seqlock**. `seq` is odd while a write is in progress; a reader that
  sees it odd, or sees it change across the copy, retries a few times and then gives up. **The
  writer never waits.** A torn read costs one frame of a decoration; a blocked render thread costs
  an audible dropout.
- Off by default (`scopeEnabled`). Only `Conductor.startHosted` turns it on. While it is off the
  render thread does one relaxed atomic load per cycle.

**Consequences.**
- The standalone is untouched: it still taps the engine's mixer, which is the cheaper path when a
  node exists, and it never enables the scope.
- `AKNodeOutputPlot` now has two modes — `resume()` for a node, `resume(pulling:)` for a source.
  The `CADisplayLink` holds the plot through a weak proxy, because a display link retains its
  target and a view that owned one directly would never deallocate.
- Every field of `S1Scope` is atomic because the reader deliberately races the writer. The samples
  use relaxed ordering — they compile to plain loads and stores — and the acquire/release pair on
  `seq` is what orders the two sides.
- The tests assert that the samples the plot receives **are the tail of the audio the host played**,
  not merely that a copy reported success. Verified by reverting `push` and watching three of the
  five fail, including on the owner's symptom: silence where a note was sounding.
- This is the counter-example to the precedent set an hour earlier, where the plugin *hides* the
  Record control because recording is the host's job. Nothing about a waveform is the host's job.
  The rule that survives both: the plugin drops what the host genuinely owns, and keeps everything
  else, even when keeping it costs more than dropping it.


## ADR-029 — P5-4: Arcade Ruins, and what a rebrand actually has to touch

**Status.** Accepted (P5-4). 2026-09-09. Owner's decision on the name.

**Context.** This is a fork of a project the owner has no connection to, and it was still wearing
that project's name, wordmark and icon. The question put was whether renaming raises legal issues,
and whether the presets can come along.

**The licence answer.** `upstream/LICENSE` is MIT, © 2017 Aurelius Prochazka. That permits the
fork, the rename and distribution. Upstream's README grants it explicitly, including *"Re-skin this
app… and upload to the app store."* The obligation is retaining the copyright notice — now in
[`NOTICE.md`](../NOTICE.md), alongside AudioKit 4.9.2 (MIT), Soundpipe (MIT) and TAAE (zlib, which
*asks* for acknowledgement in product documentation and now gets it).

**Copyright and trademark are separate, and only trademark bites.** MIT grants no trademark rights;
it is silent on them, unlike Apache 2.0 §6. "AudioKit" and "Synth One" are marks. So the code is
free to use, the *marks* are not, and stating factually that this is a port of their work is
nominative use — which is what a fork does. Hence: replace the wordmarks, keep the attribution,
disclaim affiliation.

**The presets come along, and the bank names must not change.** All 695 arrived under the same MIT
licence, contributed by volunteer sound designers, and the designer's name *is* the `bank` field on
every preset. Those names are simultaneously the credit and the load order that fixes preset
numbers in saved host sessions (ADR-024). Two of 695 names reference other instruments descriptively
("DX7 Harmonica", "Moogy Glide Bass"); upstream's own Legal Notices paragraph covers exactly that
and is carried forward.

**Decision.** The product is **Arcade Ruins**. Rebranded at the level of *product identity*, not
internal symbols:

| Changed | Left alone |
|---|---|
| `CFBundleDisplayName`, bundle IDs, `.app` name | Target names, `SynthOneCore` module, `AK`/`S1` prefixes |
| AU name, description, **subtype** | Directory layout, ported file names |
| Header wordmark, both About logos, all 18 app icons | The 12 storyboards' layout |
| About/MailingList copy, outward links, support route | The ~100-name contributor list |

Internal names stay because they are a **provenance signal** (ADR-009): `SynthOneCore` is invisible
to users, and renaming it means touching 153 files' import lines and destroying the readable diff
against `upstream/` that ADR-009 exists to protect. Trademark law concerns source identification to
a consumer, which an internal module name is not.

**The AU subtype was the one thing with a deadline.** `aumu`/`aks1`/`BP03` — `aks1` literally
standing for AudioKit Synth One — is the pair a host stores in its session file. It is now
`aumu`/`ruin`/`BP03`. Changing it after distribution orphans the plugin in every project that ever
loaded it; changing it today cost nothing, because nothing has been distributed. **It is not free
any more.**

**Consequences.**
- **The App Store rule is now the live tension, and it does not bind yet.** Upstream's README warns
  in capitals that Apple's rule 4.1 on copycat apps requires changing the graphics *and UI*, and
  that a developer was banned over this code. That is a review rule, not a licence term, and
  ADR-005 keeps this local-only and ad-hoc signed. Preserving the interface (hard requirement 1)
  and shipping to the Mac App Store are mutually exclusive; that choice is deferred, not made.
- **Localised `InfoPlist.strings` override `Info.plist`.** Six of them hard-coded
  `CFBundleDisplayName = "Synth One"` and would have kept the old name in those languages no matter
  what the plist said.
- **Seven stale `About.strings` were deleted rather than edited.** 18 keys each, 15–18 of them
  product copy about a different product ("the first free iOS synth in history", "leave a review in
  the app store"). Falling back to Base.lproj is accurate English; keeping them was inaccurate
  translation. No other localisation was touched.
- **The branded assets are generated, not drawn** — `Scripts/branding/`. The wordmark's tracking,
  palette and glow, and the whole icon, are code. The originals were PNGs someone drew once and
  nobody could edit. Re-run `python3 Scripts/branding/generate.py` after any change.
- The support button no longer mails AudioKit. It opens this project's issue tracker — a fork must
  not route its users' support mail upstream, and publishing a personal address in an open-source
  app is worse than pointing at the tracker.
- **The old install must be removed by hand.** `/Applications/SynthOne.app` still registers
  `aumu`/`aks1`/`BP03`, so a host will list both plugins until it is deleted.

**Amended the same day: the wordmark is orange to grey, not magenta to cyan.** The first pass took
"synthwave" literally and the owner called the clash immediately — a hot magenta wordmark on a
header whose every accent is orange reads as a different product bolted onto the panel. Both ends
of the replacement are **sampled from the thing itself** rather than chosen: `#E68800` is the
orange that appears twelve times across the panels, and `#DEE3E2` is the brightest ink in the
wordmark being replaced. The midpoint is a warm tan because orange and light grey interpolated
directly pass through a muddy brown whose luminance dips below both ends. The glow was cut to about
two-thirds, which at 14pt logical is the difference between depth and a smudge.

The lesson is narrower than "match the theme": **a rebrand is constrained by the interface it lands
in, and hard requirement 1 makes that interface fixed.** The theme is not a style choice here, it is
an input — which is exactly why the palette lives in `Scripts/branding/wordmark.py` as two sampled
constants instead of inside a PNG.

**Amended again: the wordmark is centred in the title frame, and the "frame" was a bug.** The owner
reported it looking left-aligned and touching the bottom of a rectangle. Two separate things:

1. **It genuinely was off-centre**, and so was Synth One's — 11px from the frame's left against
   79px from its right, 22px from the top against 8px from the bottom. It is now centred in the
   header's `Title Button`, `(7, 3, 200, 30)` in logical points, computed in `generate.py` from that
   frame rather than hard-coded. The *cap box* is centred, not the image `render` returns: that
   carries padding and the glow's bleed, and centring by its bounds puts the letterforms off by
   however wide the glow is.
2. **The rectangle should not have been there at all.** `Title Button` is a transparent hit area
   over the wordmark, and under the Mac behavioural style a bare `.system` `UIButton` is drawn as a
   real macOS push button. Same root cause as ADR-026 — and ADR-026 missed it, because that sweep
   went class by class and this button has no `customClass`.

So the fix is a **hierarchy walk**, `UIView.useDesignedButtonAppearanceThroughout()`, called from
`HeaderViewController.viewDidLoad`. Reverting it fails the new test with **five** offenders, not the
two predicted: `TitleButton`, `RandomButton` (the dice), `PrevButton`, `NextButton` and the host-app
icon button. **A list of names is the wrong shape for this problem** — that is twice now that
enumerating classes has missed live cases. The walk cannot miss one and is idempotent for classes
that already opted out.

The test asserts `preferredBehavioralStyle` rather than appearance, and says why: Mac-style controls
need an `NSApplication`, which a test bundle does not have, so `drawHierarchy` throws
`NSInternalInconsistencyException`. Confirmed by probe before writing the test.

**Amended again, 2026-09-10: the header wordmark is the owner's own artwork.** The owner supplied
`Arcade-Ruins.png`: ARCADE in orange and RUINS in grey, in a squared techno face. They asked for it to
replace the generated Futura wordmark in the header, "shrunk to fit and aligned horizontally and
vertically within its space". They tried it in the standalone and in Logic, and kept it.
- **It is still built by `Scripts/branding/generate.py`**, now from
  `Scripts/branding/source/Arcade-Ruins.png`, so regenerating keeps it.
- **The PNG needed cleaning.** It is transparent, but carried about 25,000 near-invisible pixels
  (alpha 1–15, some pure red) scattered across the canvas. They are dropped before trimming to the
  letters; otherwise the trim keeps the whole canvas, and the noise shrinks into a haze. The letters'
  interiors are alpha ~253 and are used as they are.
- **It fits the Title Button frame, 200 × 30 pt.** Width is the limit, so the result is 200 × 13 pt,
  centred with 8.5 pt above and below.
- **It is resized premultiplied**, so the transparent black around the letters does not darken their
  edges.
- **The About and mailing-list logos followed the same day**, at the owner's request. They are
  `ak1-logo`, and `s1_logo` for the iPhone header, which is never loaded. Each is fitted to its
  existing asset box and centred. The storyboards place these by frame, so their pixel sizes are
  unchanged. `wordmark.py`, the Futura renderer, is no longer used.

---

## ADR-030 — Out of process, the plugin hears its own parameter writes come back

**Status.** Accepted (P4-6 follow-up). 2026-09-10. Owner-reported.

**Symptom.** In Logic, the mod wheel "is jittery and doesn't remain at the position it's dragged
to". Asked what it does on release: it drifts back.

**Evidence, not reasoning.** Logic runs the plugin out of process, and the installed Debug extension
carries `get-task-allow`, so lldb could attach to the running `ArcadeRuinsAU` inside the owner's
Logic session. Auto-continuing breakpoints on the wheel's setters, the `observeHostChanges` closure
and `Manager.dependentParameterDidChange`, reading argument values from debug info, while the owner
dragged for two minutes: **574 host-observer callbacks, every one address 16 (`cutoff`)**, with
nothing in Logic automating anything, and each followed by `setVerticalValue01`. One release,
verbatim from the trace:

```
24.228s  wheel<-DRAG               touchPoint=(x = 33.55, y = 15.71)     → wheel 1.0 → 3 × 120 = 360 Hz
24.242s  wheel RELEASED
24.293s  HOST->UI observer         address=16  value=361.259888
24.302s  wheel<-setVerticalValue01 inputValue01=0.58057784270563706
```

Two other hypotheses were eliminated first, by measurement. The plugin opens every CoreMIDI input
itself, so a CC1 stream was a real candidate — a sniffer on all six sources saw no traffic at all.
And the plugin sends no MIDI (the one send site is iOS-only), so there is no CC1 loop.

The first trace attempt is worth recording as a trap: a regex breakpoint meant for the host
observer, `closure.*in Conductor.startHosted`, also matched the waveform's 30 Hz pull closure
(ADR-028), and its output buried the wheel. Anchor closure regexes to the exact function.

**Two bugs, stacked.**
1. **The originator token does not cross the process boundary.** `setValue(_:originator:)` keeps a
   write from reaching its own observer in-process — `testOurOwnWritesAreNotEchoedBack` passed, and
   always had. Out of process, the host relays each write back into the extension's tree without
   it, tens of milliseconds late and carrying values from earlier in the drag. By the code, every
   control received these as host moves, not just the wheel: `updateSingleUI` with a nil control
   sets `Knob.value`, and a knob's drag is relative to that value.
2. **Upstream's cutoff → wheel placement does not invert the wheel's own write.** The wheel writes
   `3 × scaleRangeLog2(1 − v, 120…7600)`; `Manager.updateUI` drew it at `1 − ln(c/40)/ln(7600/40)`.
   Upstream only reached that line from the cutoff knob. In the plugin, every echo and every
   automation pass reaches it — which is what turned an echo of the wheel's own value into a wheel
   that moves.

**Decision 1 — suppress echoes by time, then reconcile.** `S1HostedSynth` records when the interface
last wrote each address. A host report inside `echoWindow` (0.5 s) of that write is taken to be an
echo. It is not simply dropped: once the address has been quiet for a whole window, the DSP's value
is compared with the last write and reported only if they differ. A pure echo ends with the two
agreeing and reports nothing; automation that landed mid-drag still reaches the panel.

Rejected:
- *Recognise echoes by value.* The host clamps — a 22,800 Hz write came back as 22,050 — and a
  discrete parameter toggled 0→1→0 would swallow a genuine host 0.
- *Ignore host changes while a control is held.* Every control class would have to report touch
  state, which is the enumeration ADR-029 got wrong twice, and it does nothing about echoes that
  arrive after release — which are the drift.
- *Stop writing through the tree.* Undoes P4-6: the host would record nothing.

The 0.5 s is margin, not a measurement. Echoes trailed writes by roughly 15–75 ms in the trace, with
breakpoints slowing the extension down. An echo later than the window reaches the controls, and
Decision 2 is what makes that harmless for the wheel: the value is its own, so it lands where the
wheel already is.

**Decision 2 — the wheel's placement is the exact inverse,** `1 − log2(c/3/120)/log2(7600/120)`,
clamped. A `PORT FIX`: it also changes where upstream drew the wheel after a cutoff-knob move, which
was wrong there as well. Display only — no DSP change, and the goldens are untouched. Two residuals,
both upstream and both small: cutoff clamps at 22,050 Hz, so the bottom 0.8% of travel reads back as
0.008; and `setPercentagesWithTouchPoint` stretches travel by 1.1×, so a ball drawn from a *value*
can sit up to 5% of the wheel's height from where the pointer left it, at the very ends.

**Verification — each fix reverted on its own** (`ModWheelEchoTests.swift`):

| Reverted | echo not reported | automation inside the window reconciled | wheel placement |
|---|---|---|---|
| echo suppression | **fails** — `[(cutoff, 2000.0)]` | **fails** — `[(cutoff, 800.0)]` | passes |
| exact inverse | passes | passes | **fails** at all seven drag points — 1.0 → 0.581, 0.5 → 0.186 |

The 0.581 is the value the Logic trace recorded. Full suite: 217 tests green, goldens included.

**Two tests passed while proving nothing, and the reverts are what caught them:**
- **Parameter-tree observer callbacks are late and coalesced.** Two writes arrived as a single
  notification. The first version of the inside-window test checked after 50 ms, passed with the
  suppression switched off, and was only confirming that nothing had arrived yet. It waits 0.15 s.
- **The echo is not the only road to the old placement.** The end-to-end test failed with only the
  mapping reverted and suppression on, which looked like suppression leaking. A spy on `updateUI`
  said otherwise: with the echo applied it saw **zero** updates, and none after the window. The
  wheel had been moved before any echo, 3 ms into an idle run loop, by
  `AKTouchPadView.resetToPosition`'s animation completion reporting cutoff with no control
  (`TouchPadPanelController.setupCallbacks`) — the touch pad's own reset reaches the same placement
  code. The end-to-end test now lets the interface settle before dragging — and then it passes with
  the mapping reverted and suppression alone in place, and fails with both reverted, at the 0.581
  the trace showed.

**A trap in the procedure itself.** The revert experiments leave `DerivedData` built from the
*reverted* sources. Restoring the files does not restore the build, and `Scripts/validate-au.sh`
installs whatever `DerivedData` holds — so the next install after an experiment ships the bug.
Rebuild, and re-run the discriminating tests against that build, before installing.

**Not addressed.** The plugin opens every CoreMIDI input itself (`receivedMIDISetupChange`) *and*
receives the host's MIDI through the render block. The extension's log lists `SL GRAND`, `M4`, IAC
and `Logic Pro Virtual Out` as opened, so a hardware keyboard played into Logic could reach the
plugin by both routes. Observed, not investigated. *(Measured and fixed the same day: ADR-031.)*

## ADR-031 — The plugin takes MIDI only from its host

**Status.** Accepted (P4-7 follow-up). 2026-09-10. Measured in Logic; the change was proposed to the
owner first and approved.

**Symptom, measured.** The extension's `Manager` registered with `S1MIDI`, which opened every
CoreMIDI source on the system, while the host's MIDI also reached `S1DSPKernel::handleMIDIEvent`
through the render block. lldb was attached to the extension running in the owner's Logic, and one
note was sent to `IAC Driver Bus 1` — a source Logic and the plugin both listen to, which puts it
where a hardware keyboard would be:

```
KERNEL-MIDI  90 3C 40   AUOOPRenderingServer   →  startNote(60, 64)    Logic's routing
COREMIDI     90 3C 40   CoreMIDI thread        →  startNote(48, 127)   main thread, via Manager
```

- **One key, two voices, an octave apart:** Logic's note as sent, and the CoreMIDI copy after the
  plugin's `Octave:` shift (one step down) and its velocity setting (off, so 127). Two threads
  entered `startNote` for the same key.
- **Unselected track.** With another track selected, Arcade Ruins' track disarmed and its window
  closed, the render block received nothing — and CoreMIDI still started a voice the kernel
  rendered (mono voice, amp 0.74). Three events from a real controller arrived during the capture
  and did the same.
- **Controls.** Hardware CC1 moved the wheel and wrote cutoff through the parameter tree; the kernel
  ignored the host's CC1. Pitch bend, CC64, program change and bank select were likewise
  CoreMIDI-only.

**Decision — in the plugin, the host is the only MIDI source.**
1. `Manager.viewDidLoad` touches `S1MIDI` only when `!conductor.isHosted`. `startHosted` sets that
   before the interface loads. The standalone's path is unchanged.
2. **Host MIDI is handled on the render thread by `S1HostMIDI`** (`DSP/Kernel/S1HostMIDI.hpp/.mm`),
   a port, function by function, of `Manager+MIDIListener` → `KeyboardView+Touches` →
   `Manager+Keyboard` → `SDSustainer` into fixed-size state: MIDI channel, velocity sensitivity,
   `Octave:` with a note-off releasing what its note-on started, hold, mono returning to the highest
   held note, white keys only, the sustain pedal and pitch bend — plus upstream's CC123. Notes stay
   sample-accurate, which an offline bounce requires.
3. **Control and program changes are forwarded** through the audio unit's existing `AEMessageQueue`
   to `Manager`'s own `AKMIDIListener` methods: mod wheel, MIDI learn, bank select, program change,
   and the pedal's hold on on-screen keys. The set of held keys goes the same way, and
   `KeyboardView.hostOnKeys` draws it.
4. **The interface pushes its MIDI settings** to the render thread with `syncHostMIDISettings()`,
   called at each place one changes: the `Octave:` stepper (which the Z/X keys also run), Hold, MIDI
   channel, velocity sensitivity, white keys only, and loading settings.
5. **On-screen and typed keys, `stopAllNotes`, `reset` and `resetDSP` are queued to the render
   thread** (`performBlockOnAudioThread`, polled at the top of the render block). `startNote` and
   `stopNote` mutate an `NSMutableArray` that upstream documents as not for the render thread; once
   host notes are played there, a key from the main thread would race them.
6. `SynthOneApp.makePluginAudioUnit` builds the unit for the extension and for the tests alike, and
   turns routing on before a host ever sees the unit.

**Where the implementation departs from the proposal.** The proposal named a new lock-free ring in
the `S1Scope` shape. The TAAE message queue the kernel already posts through is exactly that, in both
directions, so no new ring was written. Queueing on-screen keys was marked optional; it was taken,
because it is the only way to keep the kernel's note bookkeeping on one thread.

**Rejected.** Playing host notes from the main thread through `Manager` unchanged — it loses sample
accuracy and breaks offline bounce. Keeping CoreMIDI for controls only — the pedal, wheel and program
change would still bypass Logic's routing and reach every instance. Only closing CoreMIDI — that
fixes the doubling and silently drops pedal, wheel, bend, `Octave:`, MIDI learn and program change
from a controller, against requirement 2.

**Parity is the contract.** Two implementations of one behaviour drift unless something compares
them. `HostMIDIParityTests` drives the same MIDI through a real `Manager`, whose sustainer wraps a
recorder, and through the plugin's own unit (`scheduleMIDIEventBlock` → `renderBlock` → a trace the
router keeps). It runs scripted scenarios, eight seeded runs of 150 random events over a nine-note
range with every setting changing underneath, and all 128 entries of the white-keys map, and it
requires identical note calls. Upstream quirks are ported on purpose and pinned: mono re-strikes the
highest held note with the *note-off's* velocity, and a second non-zero sustain value lifts the
pedal. Two are deliberately outside the comparison: `KeyboardView.allNotesOff` releases in `Set`
order, so runs of stops compare as sets; and setting hold or mono to the value it already has also
releases every key, which no control does.

**Accepted differences from the standalone.**
- Host notes and on-screen keys do not interact exactly as in the standalone, where they share
  `onKeys` and one sustainer. Here the host's keys are the router's, and on-screen keys keep
  `Manager`'s sustainer. Both receive the same pedal messages.
- An on-screen key sounds at the start of the host's next render cycle, within one buffer, and not
  at all while the host is not rendering.
- `startNote` still allocates an `NSValue` and mutates an `NSMutableArray` on the render thread, as
  upstream's `handleMIDIEvent` always did. Out of scope.
- **Velocity sensitivity is off by default**, as in the standalone, so host notes play at 127 until
  it is switched on. The plugin cannot persist that setting yet (ADR-020), so it resets whenever the
  plugin loads. Raised with the owner rather than decided here. *(Superseded the same day by
  ADR-032: the plugin always plays its host's velocity.)*

**Verification.** 25 new tests in `HostMIDITests.swift`. Four pieces were reverted at once, and each
failed the test aimed at it:

| Reverted | Failed |
|---|---|
| The `isHosted` guard around `S1MIDI` | `testThePluginOpensNoMIDIInputsOfItsOwn` |
| The octave stepper's `syncHostMIDISettings()` | `testEverySettingReachesTheRenderThread` — "0 is not equal to -12" |
| `S1HostedSynth.play` queued to the render thread | `testKeysFromTheInterfacePlayOnTheRenderThread` |
| The sustain quirk "corrected" in the router alone | both parity tests, all eight seeds |

`testAHostModWheelMovesTheWheel` also failed with the reverts in place: the wheel read 0.0316, about
4/127. That is consistent with a connected controller's CC1 arriving through the re-opened inputs,
and not confirmed.

Full suite, run on the restored sources: 242 tests. One failure — `AudioUnitPresetTests` read the
extension's source for the setup calls this change moved into `SynthOneApp.makePluginAudioUnit`. It
now exercises that factory and passes. `auval` passes, its MIDI test included.

**Checked live in Logic** with the installed build, using the same lldb driver and IAC stimulus as the
original measurement; the owner selected the tracks.
- **Before any note:** the extension logged no CoreMIDI activity although its interface had loaded,
  and the "AudioKit Synth One" endpoints are gone from the system MIDI list.
- **Arcade Ruins' track selected:** one note-on became one `startNote(60, 127)` on
  `AUOOPRenderingServer`, rendered (mono voice; the arpeggiator played 67 and 72). The note-off became
  one `stopNote(60)`. The CoreMIDI and main-thread note breakpoints recorded zero hits.
- **Another track selected:** nine breakpoints resolved, and none fired.

**A trap found on the way.** The parity test's recorder had a method called `take()`, and the
property holding it was implicitly unwrapped. Swift type-checks an IUO as `Optional` first, and
`Optional` has had `take()` since Swift 5.9 — it returns the value and sets the property to nil. The
recorder emptied itself on first use and the test crashed one call later. A `didSet` logging a stack
found the writer in one run, after the obvious suspect — memory corruption from the new C++ — had
been the leading guess. CLAUDE.md has it.

**Found, not addressed here.**
- The standalone's virtual endpoints are still named "AudioKit Synth One", unique ID 95433.
- The extension crashed twice in Logic at 11:52 on 2026-09-10, before any of this was installed:
  `UIPickerView` throws under the Mac idiom, and the preset editor's bank picker is one. Spun off as
  its own task.
- A second plugin instance in the same extension process drives the first instance's `Conductor`
  (`Conductor.startHosted() called again` in the log). P4-7's multi-instance column.

## ADR-032 — Velocity sensitivity is always on, in both products

**Status.** Accepted. 2026-09-10. The owner's decision — first for the plugin, then, when asked, for the
standalone as well.

**Context.** ADR-031 made host notes follow the interface's velocity-sensitivity setting, exactly as
the standalone's MIDI does. That setting is off by default, so every note plays at 127. The extension
also cannot save its settings (ADR-020; its log says `saveAppSettings() error saving`), so any change
would reset whenever the plugin loads. Asked whether the plugin should default it on, carry it in
`fullState`, or leave it, the owner answered: *"Velocity sensitivity should always be on."*

**Decision, as first taken — for the plugin, which is what the question was about.**
- `S1HostMIDI` does not port `if !appSettings.velocitySensitive { newVelocity = 127 }`. The render
  thread plays the velocity the host sends, and the field is gone from `S1HostMIDISettings`: a
  setting nothing may change should not exist to be changed.
- **The plugin's MIDI settings show Velocity Sensitive on, dimmed, and inert**
  (`MIDISettingsViewController.velocityIsFixedOn`, set in `Manager`'s `SegueToMIDI` preparation
  when hosted). A switch that did nothing would misreport the plugin.
- ~~**The standalone is unchanged.**~~ That was the first answer's scope, and it was flagged to the
  owner: "Should the standalone also be always on, with its switch locked the same way?" — "Yes".

**Extended to the standalone.**
- `Manager+MIDIListener` no longer does `if !appSettings.velocitySensitive { newVelocity = 127 }`
  (`PORT FIX`). Every MIDI note plays at the velocity it arrives with.
- The switch in MIDI settings is on, dimmed and inert in both products, so the plugin-only
  `velocityIsFixedOn` flag is gone again. `AppSettings.velocitySensitive` is still read from and
  written to `settings.json`, and nothing consults it. Removing a stored key would be a migration for
  no benefit.
- This does take away a working control, which requirement 2 would normally rule out. The owner's
  explicit decision is what overrides it.

**What a DAW user notices.** Regions play with the dynamics they were recorded with. Before ADR-031
they did not either, in practice: the plugin's own CoreMIDI copy played every key again at 127.

**Parity.** `HostMIDIParityTests` leaves the old setting *off* on the standalone's side, so a
standalone that still flattened velocity to 127 fails it.

**Verification.** Three new tests:
- `testTheHostsVelocityIsAlwaysPlayed` — the router, at velocities 1, 64 and 127.
- `testTheInterfacesVelocitySettingDoesNotReachHostNotes` — the interface's setting off, and a host
  note still plays at 30.
- `testThePluginsVelocityToggleIsLockedOn`, with the standalone's toggle test beside it — now
  `testTheStandalonesVelocityToggleIsLockedOnToo`.

Router expectations throughout now assert the velocity sent rather than 127. Two pieces were reverted
at once:
- The router forcing 127 again failed the velocity tests (`[on(60, 127)]` where 1, 64 and 30 were
  sent), all three parity tests, and every router test that asserts a velocity.
- The popover left unlocked failed `testThePluginsVelocityToggleIsLockedOn` — "a switch that does
  nothing".

Restored, rebuilt, full suite: 245 tests green. Installed with Logic quit; `auval` passes, and the
installed framework matches the tested build.

**Verification of the extension to the standalone.** One more test,
`testTheStandaloneAlwaysPlaysTheVelocityItReceives`, and the parity harness now leaves the old setting
off. Both standalone pieces were reverted at once: the flattening restored in `Manager+MIDIListener`,
and the toggle following `velocitySensitive` again. That failed 5 of 29 tests: both toggle tests
(value 0 where 1 was expected, and still interactive), the standalone velocity test, and both parity
tests.

A first attempt at that check ran **0 tests** and reported success. Its `-only-testing` flags were
gathered in an unquoted zsh variable, which zsh does not split into separate arguments; CLAUDE.md
has it.

Restored, rebuilt, full suite: 246 tests green. Installed with neither Logic nor the app running;
`auval` passes, and the installed framework matches that build.

## ADR-033 — The preset editor's bank picker is a table, because `UIPickerView` throws under the Mac idiom

**Status.** Accepted (bug fixed). 2026-09-10. Found in the extension's crash reports.

**Symptom.** The plugin crashed in Logic three times on 2026-09-10: `ArcadeRuinsAU-2026-09-10-115235.ips`,
`-115253.ips`, and `-145355.ips`. The last was on the build installed at 14:46. Each was `EXC_BREAKPOINT`
from an uncaught Objective-C exception on the main thread, thrown in `-[UIPickerView _didMoveFromWindow:toWindow:]`
while a presentation transition added a view to the window. The presented controller was the
preset editor, where a preset is renamed, given a category, and saved into a bank.

**Reproduced in the standalone, along the path a click takes.** lldb drove the DerivedData build, not
`/Applications`, while Logic was running and untouched:
1. Dismiss the pop-up the app shows at launch.
2. Call `HeaderViewController.displayLabelTapped`, the display label's tap target.
3. Fire `editPressed:` on a live `PresetCell`.

It stopped in `objc_exception_throw` with this reason:

> UIPickerView is not supported when running Catalyst apps in the Mac idiom. See UIBehavioralStyle
> for possible alternatives.

The backtrace matches the plugin's frame for frame.

**Why nothing caught it.** The test bundle runs in the `.pad` idiom (ADR-023), where a picker is
legal. `UILoadTests` never loaded this editor, and the editor is only reached through a click.

**The sweep ran in the running app and walked the storyboards.** The compiled storyboards record 55
scenes across 12 files, in their `UIViewControllerIdentifiersToNibNames`. The Mac-idiom standalone
instantiated 53 of them, added each view hidden to the key window, and laid it out. The two `Manager`
scenes were skipped, because the live root is a `Manager` and is already in the window. **Exactly one
scene raised an exception: `Presets/PresetEditorViewController`.**
- **UIKit's own record of restricted classes** is the set carrying a
  `UICatalystMacIdiomUnsupported_Internal` category in UIKitCore on this macOS. It lists `UIButton`,
  `UIPickerView`, `UIRefreshControl`, `UISlider`, `UIStepper` and `UISwitch`.
- **`UIDatePicker` is not on that record, and no storyboard uses one.**
- **The other four restricted controls appear in no scene.** The walk logged every scene's view
  classes. `Stepper`, `ToggleSwitch` and `LFOWavePicker` here are `UIView` subclasses, and
  `VerticalSlider` is a `UIControl`.
- **Plain `UIButton`s are everywhere and do not throw.** ADR-026 and ADR-029 cover how they draw.
- **Some views are built in code and sit outside the walk:** alerts, share sheets, document
  pickers, a search controller, a navigation controller, table views and image views. None is a
  restricted class. The search bar was walked, because it lives inside the search scene. None of
  these was presented live.

**Decision — a table in the picker's frame.**
- **`Presets.storyboard`.** The `<pickerView>` became a `<tableView>` that keeps the element id, the
  frame (22, 143, 217 × 80), the autoresizing, the clear background, the tint, and the data source and
  delegate connections. It has no separators, and its accessibility identifier is `BankTableView`.
- **`PresetEditorViewController`.** The outlet is `bankTableView`. The picker's data source and
  delegate are gone.
  - Each row is drawn with the picker label's font, colour and centring.
  - Three rows fill the frame.
  - A row of inset above and below lets the chosen bank sit in the middle row, where the picker
    showed its selection.
  - Selecting a row sets `bankSelected`, exactly as `didSelectRow` did.
  - `pickerBankNames`, `bankSelected` and the save path are unchanged.
  - `PORT FIX` comments mark each site.

**Rejected.**
- ***A `UIButton` with a `UIMenu`.*** It would show one bank where the picker showed a column. Its menu
  would open from an AUv3 view inside a host, which cannot be checked without Logic. And `UIButton` is
  on UIKit's restricted record too.
- ***Removing the picker from the hierarchy in `viewDidLoad`.*** The storyboard would no longer
  describe the screen, and the function would be lost.
- ***The private `_setAllowsUnsupportedMacIdiomBehavior:` opt-out.*** It is private API, and UIKit
  refuses this control for a reason.

**What changes for a user.** The bank list is in the same place under the same label, with the same
banks in the same order, and it opens on the preset's own bank. Choosing a bank takes a click on a row
rather than a spin. The chosen row is highlighted, as rows are in the category list beside it, rather
than resting between two rules. Whether that highlight looks right is part of the owner's visual
sign-off.

**Verification.** `MacIdiomControlTests.swift` adds three tests.
- `testNoStoryboardSceneHoldsAControlTheMacIdiomRefuses` repeats the sweep in the test bundle. It
  loads every scene each compiled storyboard records, plus `Manager` as the app builds it. It walks
  every view for UIKit's restricted classes, `UIButton` aside.
- `testTheSweepRecognisesARestrictedControl` is the positive control. A matcher that never matched
  would pass the sweep too.
- `testThePresetEditorStillChoosesTheDestinationBank` covers what the picker was for:
  - every bank is listed in order, and the editor opens on the preset's own bank;
  - choosing a row changes `bankSelected` and leaves the category alone;
  - Save hands the chosen bank to the delegate.

  It finds the list through the view hierarchy rather than an outlet, so it compiles against the old
  picker as well. It also sets the banks itself: `Manager` loads them from `banks.json` in the user's
  Documents, which the test bundle does not see, and the first version failed on an empty list.

**The fix was reverted to watch the tests fail.** HEAD's storyboard and Swift file went back in, and
the diff of those two files against HEAD was confirmed empty. Result: **3 executed, 2 failed.**
- The sweep reported `["Presets/PresetEditorViewController: UIPickerView"]`.
- The editor test reported "the preset editor has no bank list".
- The positive control passed.

Both files were then restored and byte-compared against saved copies. The full suite on the restored
sources, which also rebuilt `DerivedData` from them: **249 tests, 0 failures.**

**Checked in the running standalone, on that build.** The same lldb click path was used.
- **The editor opens.** It presented with no exception, and its view is in the window.
- **The bank list is correct.** It is a `UITableView` in the window with 12 rows, in the Presets
  panel's order.
- **The selection sits where the picker's did.** The current preset's bank, BankA, is selected. Rows
  are 26.67 pt, the inset is one row top and bottom, and the offset is −26.5, so the chosen bank is in
  the middle row. BankA is the first bank, so the row above it is empty.
- **The sweep is clean.** Repeated on the fixed build, it walked 53 scenes with no exceptions, and the
  editor's scene now holds a table where the picker was.
- **The owner has a picture.** A layer render of the window with the editor open was made for the
  visual sign-off.
- **Not verified here:** the plugin inside Logic. Logic was running, and the fix is not installed.

**Found, not addressed.** With macOS in Dark appearance, the editor's name field shows white text on
its near-white background. The storyboard sets the field's background and no text colour, and nothing
in the project pins an appearance. The field predates this change, and nobody could have seen the
problem while the editor crashed. Offered as a separate task.

**Installed** 2026-09-10 18:49, with Logic quit. Before installing, the build was redone and 11
preset-editor and UI-load tests passed. `auval` passes, and the installed framework's md5 matches the
tested build.

## ADR-034 — The editors' name fields are pinned to Light, because their background is

**Status.** Accepted (bug fixed). 2026-09-10. Found while verifying ADR-033.

**Symptom.** With macOS in Dark appearance, the preset editor's name field showed the preset name
as white text on a near-white field. The bank editor's rename field did the same. Nobody could see
it before ADR-033, because the preset editor crashed as it opened.

**Cause.** `Presets.storyboard` gives both fields (`E89-9F-gAT` and `7JR-Af-r8F`) a fixed background,
sRGB 0.9725 (`#F8F8F8`), and no text colour. A `UITextField` with no text colour draws in
`labelColor`, which is dynamic: under the Mac idiom it is black at 85% in Light and white at 85% in
Dark. Nothing in the project pins an appearance. The storyboards are upstream's in this respect: a
dump of every storyboard text input's colours is identical for `upstream/` and `Sources/`.

**What upstream intended.** Upstream never decided it.
- Its CI built with Xcode 11.2 (`.travis.yml`, `osx_image: xcode11.2`), against the iOS 13 SDK, so
  an iPad in Dark mode showed the same white-on-white field.
- Nothing in upstream sets `UIUserInterfaceStyle` or `overrideUserInterfaceStyle`. Its only reference
  to Dark mode is the on-screen keyboard's own `darkMode` setting.
- Interface Builder draws storyboards in Light, so the look the storyboard was designed with is
  black text on the near-white field.

**Measured in the running app.** An Objective-C walker was injected into the DerivedData
standalone with `DYLD_INSERT_LIBRARIES`, launched with `open -g` so that it would not take focus.
The Debug build has no hardened runtime (`flags=0x2(adhoc)`), so the library loads, and none of
ADR-033's lldb expression traps apply. The walker is kept as `Scripts/debug/appearance_walker.m`.
- It drove the real click paths: the display label, a preset cell's Edit, a bank's Edit, and the
  search button's segue. No launch pop-up was showing.
- It then loaded all 53 non-`Manager` storyboard scenes into the window, as ADR-033's sweep did.
- For every `UITextField` and `UITextView` it recorded the resolved text colour and the background
  composited from the view and its superviews.
- It also measured the glyphs actually drawn: each input was rendered with its text and again
  without it, and the contrast was taken over the pixels that changed.

It ran in the system appearance, which was Dark (window style 2, idiom 5), and again with the key
window overridden to Light. The system setting was not changed. Logic was running and was not
touched. The owner's preset and bank files were checksummed before and after and did not change;
the two files the app rewrites at launch were restored byte-identical.

| In Dark | Text | Background | Contrast |
|---|---|---|---|
| Preset editor's name, opened from a preset cell's Edit | white, 85% | `#F8F8F8` | **1.05** — no pixel differs from the empty field |
| Bank editor's name, opened from a bank's Edit | white, 85% | `#F8F8F8` | **1.05** — no pixel differs |
| Either name while being edited | | | visible only inside the selection highlight |
| Search field, typed text | `#787878` | `#080808` | 4.5 |
| Presets panel's description | `#C7C7C7` | `#3B3A3B` | 6.7 |
| Every other text view: About, the Tunings pop-up | white or `#EEEEEE` | dark | 10.6–21 |

**In Light** both name fields measure 14.3, and every other input keeps its Dark value, with two
exceptions:
- **The search field's typed text drops to about 3.0.** This is how UIKit draws a `.black` search
  bar in Light. It is still legible and was left alone.
- **The mailing-list email fields drew black on the dark panel.** The mailing list cannot be
  opened in this port. All three entry points require a MailChimp key, and `Private.swift` holds
  upstream's placeholder. Whether the field's system fill was missing on screen or only from an
  off-screen render was not settled.

**Three things that are not inputs also do not suit Light.** In the Light renders, the editor's
category rows turn white, the chosen bank's highlight turns pale with pale text, and the
`SynthButton` titles draw dark on dark buttons. All three look as designed in Dark. They are not part
of this fix, and they are recorded in STATE.md.

**Decision — pin each field to Light.** `PresetEditorViewController.viewDidLoad` and
`BankEditorViewController.viewDidLoad` set `nameTextField.overrideUserInterfaceStyle = .light`, with
`PORT FIX (ADR-034)` at both sites. Each field then resolves every dynamic colour it draws with as it
does in Light, which is what its fixed background was designed for. The storyboard is unchanged.

**Rejected.**
- ***An explicit text colour in the storyboard.*** It fixes the text and leaves the field's other
  dynamic colours in Dark. It also means choosing a value: `labelColor` is black at 85% under the
  Mac idiom, and opaque black on an iPad.
- ***`UIUserInterfaceStyle = Light` for the app and the plugin.*** The Light renders show it would
  break the category rows, the bank highlight and the button titles, which are right in Dark.
- ***`UIUserInterfaceStyle = Dark`.*** It pins these two fields to the broken case.
- ***A dark background for the fields.*** It changes the designed look.

**Verification.** `TextInputAppearanceTests.swift` adds three tests.
- `testEveryStoryboardTextInputIsLegibleInDarkAndLight` loads every scene in each appearance and
  checks every text field and text view against WCAG AA, 4.5:1. It requires both name fields to have
  been reached in both appearances. It skips inputs with nothing opaque behind them, and bordered
  fields whose fill UIKit draws: the four mailing-list email fields.
- `testTheCheckFlagsALightFieldWithSystemTextInDark` is the positive control.
- `testTheEditorNameFieldsLookTheSameInDarkAsInLight` requires each name field to draw the same
  text colour over the same background in both appearances.

**A test that failed identically with and without the fix, caught before it was believed.** The
first version gave 3 executed, 5 failures both ways. The window-less test bundle applies an
appearance at the next trait update. The app gets one from layout; the test never triggered one. So
the override set in `viewDidLoad` was never seen, and the positive control's field read Light under
a Dark controller. The test now lays out and calls `updateTraitsIfNeeded()` after loading. Then:
- **With the fix: 3 executed, 0 failures.**
- **With both Swift files reverted to HEAD (diff confirmed empty): 3 executed, 3 failures.** The
  sweep reported exactly the two name fields, in Dark, at 1.05. The look test failed for both
  editors. The positive control passed.
- The files were restored and byte-compared against saved copies.

**The full suite on the fixed sources: 252 tests, 0 failures** (249 before).

**Checked in the running standalone, on the fixed build**, with the same walker, click paths and
sweep.
- **In Dark, both name fields now resolve Light.** Each draws black at 85% on `#F8F8F8`, at 14.3.
  That holds when opened from a preset cell's Edit and from a bank's Edit, while being edited, and
  in the sweep's scenes.
- **The rest of the editor is unchanged.** The category rows, the bank list and the buttons render
  as before.
- **No visible input measures below 4.5 in Dark.** The search field is 4.54.
- **In Light, the only inputs below 4.5 are the ones that were there before the fix.** One is the
  search field. The other is the mailing list's welcome text: nothing behind it is opaque, so the
  walker composites it over the system background, and it cannot be opened in this port.
- **Not verified here:** the plugin inside Logic. Logic was running, and the fix is not installed.

---

## ADR-035 — The keybed: the interface is 100 points taller, and hidden keys fill it

**Status.** Accepted. 2026-09-10. The owner's request, and the owner's choice from mockups (P3-6c).

**Context.** The owner found the on-screen keyboard "outrageously huge" on a big display. Measured
against the storyboard:
- **Shown**, the keyboard container's top is at y = 337, so it covers the whole 299-point lower panel.
  At the default 2 octaves its white keys are 58.6 × 385 points. At full screen on a 27-inch Studio
  Display (scale ≈ 1.83, ≈ 109 points per inch) that is about 25 × 165 mm. A grand piano's white key
  is roughly 23.5 × 150 mm.
- **Hidden**, the container's top moves to y = 636 and nothing else changes. The container was a fixed
  431 points tall, so the 387-point keyboard ran 299 points past the bottom of the window. Only its top
  88 points showed, all of them inside the black-key zone, since black keys are 55% of the length. The
  pitch pad's resting point sat 94 points below the edge.
- This is upstream's iPad design, not a porting defect.

**Options, mocked up at the storyboard's geometry.** A: redraw the whole keyboard into the 88-point
strip. B: grow the interface downward so hidden keys have room. C: a shorter Show. The owner chose
B. They then asked to see more of the white keys below the black ones, compared +80, +100, +120 and
+160, and chose **+100, 4 octaves, hidden by default, with shaded keys**.

**Decision.**
- **`S1ScalingContainer.designSize` is 1024 × 868**: upstream's 768 plus `keybedHeight` (100). The
  window bounds in `SceneDelegate` and the plugin's `preferredContentSize` are derived from it.
- **The keyboard container runs to the bottom edge.** In `Main.storyboard`'s iPad scene its fixed
  height `IyF-k0-ybl` is replaced by a bottom constraint to the root view, `kbD-Bd-8Hx`. The keyboard
  view, the wheel panel and both pads resize with it. The Pitch and Mod labels keep their distance
  from its bottom. The keyboard view redraws when resized.
- **The toggle is unchanged**: 337 shown, 636 hidden, as upstream. Hidden, the keys run from 680 to
  868: 186 points drawn, 29.9 wide at 4 octaves, so 1 : 6.2 against a piano's 1 : 6.4, with 83 points
  of white below the black keys. Shown, they run from 381 to 868.
- **`AppSettings` defaults to hidden and 4 octaves.** A new `keybedVersion` field marks settings
  saved under this layout. Settings without it, including the owner's, take the new defaults once;
  a choice saved after that is kept.
- **The Keys popover offers 1 to 5 octaves** (it offered 1 to 3). A default of 4 would otherwise index a
  segment that didn't exist.
- **`KeyboardView+Draw12ET.swift` shades the keys** over upstream's flat fills:
  - each white key darkens toward the back, from 27% black to nothing;
  - each octave's black keys cast one soft shadow (offset 2, 5; blur 7; 65%). They are drawn as a single
    transparency layer, so the two or three overlapping slots that make up a key cast one shadow, not
    several;
  - each black key gets a lighter band before its tip.

  Geometry, colours and hit-testing don't change, and the microtonal keyboard isn't shaded.

**Consequences.**
- **This departs from hard requirement 1, at the owner's request.** The panels, the toolbar and the
  Show/Hide positions are upstream's. The keyboard's size, its default state and its shading are not.
- **The whole interface draws smaller when height sets the scale.** That's 768 / 868, about 12%, at
  full screen on most Macs.
- **Shown, the keys are long and narrow**: 487 points at 4 octaves is about 1 : 16. Show keeps
  upstream's position so it still covers exactly the lower panel. If that looks wrong, the options are
  fewer octaves while shown, a shorter Show (mockup C), or retiring Show. Not decided.
- **The plugin's window changes shape** in hosts that remembered its old size.
- The iPhone scene in `Main.storyboard` is untouched; the Mac never loads it.

**Rejected.**
- ***A: redraw the keys into the 88-point strip.*** The window stays the same, but the keys are under
  1 : 4 even at 5 octaves.
- ***+80, +120 or +160.*** Shown to the owner side by side; +100 is the closest to a piano's
  proportions.
- ***Relayout the panels to free space.*** ADR-019: the storyboards have no adaptive layout.

**Verification.**
`KeybedTests.swift` adds ten tests. The geometry tests use the real `Manager` at the design size:
hidden keys, shown keys, and the wheel labels. Four more cover the settings defaults, the one-time
switch, a choice kept after it, and the popover's segments. Two pixel tests check the shading, in a
real UIKit drawing context so the shadow offset points the way it does in the app.
- **The first shown-state test failed while the layout was right.** In a view with no window,
  changing a constraint's constant does not schedule a layout pass, so `layoutIfNeeded()` alone left
  the keyboard at 636. A diagnostic run showed that 337 puts the container at 337–868 with 487-point
  keys. The test helper now calls `setNeedsLayout()` first.
- **Revert check.** With `Main.storyboard`, `KeyboardView+Draw12ET.swift` and `AppSettings.swift` reset
  to HEAD: 10 executed, 8 failed, each for the expected reason. Hidden keys ended at 1067 and shown
  keys at 768, the wheel labels sat at 1060, the defaults were 1.0 and 2, the popover threw an index
  out of range on 3 segments, and the shaded pixels read 255. The two that passed don't depend on
  those files: the design size lives in `S1ScalingContainer`, and the kept-choice test guards the
  switch. The files were restored byte-identical, and all 10 pass.
- **Full suite: 262 tests, 0 failures** (252 before). It was run twice, the second time after the
  storyboard's own octave count went from 2 to 4.
- **The storyboard's octave count is 4 as well.** `setDefaultsFromAppSettings` applies the saved
  setting in `viewDidAppear`, so a new install drew the storyboard's 2 octaves until then, and a
  window-less render never got past it.
- **`Renders/ui/00-main.png`** is 1024 × 868: hidden keys from 680 to 868, C2 to C6, shaded, and the
  lower panel uncovered.
- **The DerivedData standalone launched** and completed its launch path. Its `settings.json` came back
  hidden, 4 octaves, `launches` 1, and no crash report was written. **Its window was not seen**: this
  session could not capture another app's window. **Not installed**, because Logic was running, and
  the plugin has not been tried.
- **Found on the way: the test suite writes the standalone's real `settings.json`.** `Disk` resolves
  the real `~/Library/Application Support/SynthOne/`, the test bundle is not sandboxed, and a
  `PointerInputTests` test fires the keyboard toggle, whose callback saves. It saves a fresh
  `AppSettings`, because loading only happens in `viewDidAppear`. So the owner's file already held
  test data (`firstRun` true, `launches` 0), and the runs here stamped `keybedVersion` into it. The
  one-time switch is covered by tests; it was not observed on the owner's real settings. Isolating
  the test bundle's storage was offered as a separate task.

## ADR-036 — The test bundle reads and writes a temporary folder, never the owner's

**Status.** Accepted. 2026-09-10. Found at ADR-035; fixed at the owner's request.

**Context.**
- `Disk` resolves `.documents` against the real home directory (P3-3, ADR-018), and the test bundle is
  not sandboxed. Any test that reached a save wrote the owner's `~/Library/Application Support/SynthOne/`.
- Loading happens in `Manager.viewDidAppear`, which no test calls, so what got saved was a fresh
  `AppSettings`. After a full run on 2026-09-10 the owner's `settings.json` had the run's mtime,
  `firstRun` true, `launches` 0, default preset indexes and reset MIDI-learn CCs. It also carried ADR-035's
  `keybedVersion`, so that one-time switch no longer reflects anything the owner saved.
- Known writers: `LayoutIdiomTests` fires the keyboard toggle, whose callback calls `saveAppSettings()`.
  `Tunings.loadTunings` saves `tunings_v1.json` on a background queue.
- **`.caches` escaped too.** In an unsandboxed process it is `~/Library/Caches` itself, and
  `~/Library/Caches/currentPreset.json` had the same 21:01:42 mtime as the owner's `settings.json`.
- `DiskTests` and `HostMIDIInterfaceTests` already redirected `Disk.sharedSupportURL` in their own
  `setUp`. Nothing covered any other class.

**Decision.**
- **The test bundle's principal class redirects `Disk`.** That is
  `Tests/SynthOneTests/Support/TestStorageIsolation.swift`, named by `INFOPLIST_KEY_NSPrincipalClass` in
  `project.yml`. XCTest creates it when the bundle loads, before any test class runs. It points
  `Disk.sharedSupportURL` and `Disk.cachesURL` into `SynthOneTests-<UUID>/` under the temporary
  directory, and removes that folder when the bundle finishes.
- **`Disk.cachesURL` is new.** It is a `var` defaulting to `defaultCachesURL`, which is what `.caches`
  returned before, so it has the same shape as `sharedSupportURL`.
- **The app's and the plugin's paths do not change.** Nothing outside the test bundle assigns either var.
- The per-class redirects in `DiskTests` and `HostMIDIInterfaceTests` stay. They now restore to the
  temporary folder rather than the real one.

**Rejected.**
- ***Detect XCTest inside `Disk`*** (`XCTestConfigurationFilePath` in the environment). It puts a
  test-only branch into the shipped app and plugin, keyed on a variable any launch could carry.
- ***A shared `setUp` that test classes call.*** It covers only the classes that remember to. The class
  that wrote the owner's file had no reason to think it saved anything.

**Not covered.**
- **`~/Music/Arcade Ruins`.** `testRecordingsGoToAFindableFolder` asserts that the real default
  exists, so a run creates it, empty. That is the product's own path under test, and it is left.
- `migrateFromContainerIfNeeded()`, called by `SynthOneApp.start`, still looks in the legacy container
  for the test runner's bundle ID. Anything it moved would now land in the temporary folder.

**Verification.**
- **`StorageIsolationTests`, four tests.** `Disk` resolves both temporary folders, neither inside the
  defaults. The keyboard toggle's save, the tunings save and a `.caches` save each land in the
  temporary folder. Each save test also compares the size and mtime of the real files before and
  after, reading only. The tests compare against `Disk.defaultSharedSupportURL` and
  `Disk.defaultCachesURL`, not a home path, so a revert check can point those at a scratch folder.
- **Alone:** 4 executed, 0 failures. The md5 and mtime of the owner's `settings.json`,
  `tunings_v1.json` and `~/Library/Caches/currentPreset.json` were unchanged.
- **The revert check was not run.** The plan was to point `Disk`'s defaults at a scratch folder, so
  nothing real could be written, and then remove the redirect. The session's permission classifier
  refused the edit that removed the redirect, and it was not worked around. The one experiment edit that
  had applied was reversed, and both files were byte-compared against their backups before anything
  ran. **So it is not yet shown that these four tests fail without the fix.**
- **Full suite: 266 tests, 0 failures** (262 before, plus these four), at 21:10. Before and after
  it, the md5 and mtime of the owner's three files were identical, and so was a digest of the size
  and mtime of every file in the support folder. The run's temporary folder was gone afterwards.
- **The owner's `settings.json` was not restored**, since nobody knows what it held before the tests
  first overwrote it. As found at 21:10 it has `firstRun` false, `launches` 2, `keybedVersion` 1,
  `showKeyboard` 0, and every MIDI-learn CC at 255, the unset default. So app launches have resaved
  it since the last test run, but ADR-035's one-time switch has already been spent on it, and any
  learned CCs are gone.

---

## ADR-037 — Show and Hide resize the window; the keyboard never covers the panels

**Status.** Accepted. 2026-09-10. The owner's request after trying ADR-035 in Logic (P3-6c).
**Supersedes** ADR-035's Show, which kept upstream's position.

**Context.** ADR-035 left the toggle alone: shown at y = 337, hidden at 636. In a 1024×868 interface
with the container running to the bottom edge, Show raised a keyboard over the whole lower panel with
487-point keys, about 1 : 16 at 4 octaves. ADR-035 flagged this as undecided. The owner tried it in
Logic and called it "absolutely massive". They said what Hide showed, the keybed, is what Show should
show, and Hide should be much shorter.

**Decision, from options put to the owner.**
- **Show:** the interface is 1024×868, and the keys fill the keybed under the panels, 680 to 868.
- **Hide:** the interface is upstream's 1024×768, with whole 88-point keys, 680 to 768.
- **The window follows.** The options were a window that shrinks, or a fixed 868 window with 100 empty
  points below short keys. The owner chose the shrinking window.
- **It opens hidden.** The last choice is remembered, through `AppSettings.showKeyboard` as before.

**How.**
- **`S1ScalingContainer` has two design sizes**, `compactDesignSize` and `fullDesignSize`. Its
  instance `designSize` follows `isKeyboardShown`. `setKeyboardShown(_:)` changes it, sets
  `preferredContentSize`, and calls `onPreferredSizeChange` with the new size at the current scale,
  so a window at 2× grows by 200 points, not 100.
- **The scale is held for 0.5 s**, pinned to the top, while the host resizes. Without the hold, the
  interface would zoom out to fit a window that hadn't grown yet, then zoom back. After the hold it
  fits whatever size it has. A host that ignores the request gets a letterboxed interface, not a
  cropped one.
- **The standalone's `SceneDelegate`** resizes the window with `requestGeometryUpdate(.Mac)` on
  Catalyst 16 and later, and by setting the frame before that. It keeps the origin, which the SDK
  documents as the top left of the main display. So the top edge stays put and the window changes at
  the bottom. The window's size bounds run from half the compact size to three times the full size.
  It opens at the compact size.
- **The plugin's view controller** starts at the compact `preferredContentSize` and passes each change
  on to the host.
- **In `Manager`**, the toggle keeps the constraint at 636 and calls the container. The paths that
  assumed a shown keyboard covers the lower panel are skipped, through
  `Manager.keyboardCoversLowerPanel`, which is `false`:
  - VoiceOver hiding the lower panel;
  - panel navigation ignoring it;
  - the presets panel hiding and restoring the keyboard.

  `Sources/SynthOneCore/PORTING-UI.md` lists the sites.

**Consequences.**
- **Show and Hide change the window's height.** In a host this depends on the host honouring
  `preferredContentSize` after the view has opened. **Not yet confirmed in Logic.** If Logic ignores it,
  the interface letterboxes inside the old size.
- **Show no longer covers anything**, so the presets panel, navigation and VoiceOver behave the same in
  both states.
- A saved "shown" opens compact and grows once the setting is applied, 0.55 s after launch, which is
  upstream's delay.
- **Two gaps the first tests missed, now covered.** With the keyboard shown, upstream's navigation
  could move the panel shown below out of the lower container. And a test that lays out at a fixed
  size keeps using `S1ScalingContainer.designSize`, which now means the full size.

**Rejected.**
- ***A fixed 868 window with short keys and 100 empty points below.*** It behaves the same in every
  host, but the owner chose the shrinking window.
- ***Keep upstream's Show position.*** It is what the owner reported.
- ***Scale the interface up to fill the space Hide frees.*** It zooms on every toggle.

**Verification.**
`KeybedTests` has 11 tests (10 before) and `ScalingContainerTests` has 16 (12 before).
- **The owner's report as a test.** `testShowAndHideResizeTheWindowRatherThanMovingTheKeyboard` presses
  Show and Hide through `Manager`'s own callback. It requires the constraint to stay at 636, the
  container to request 1024×868 and then 1024×768, and the keys to come out 188 and 88 points once the
  view has the new size.
- **Navigation.** With the keyboard shown, FX on top and the sequencer below, FX's right button must
  not offer the sequencer.
- **The container.** Show requests the new size at the current scale: 2048×1736 at 2×. The scale and
  top edge hold until the window grows. A host that never resizes gets a letterboxed fit after the
  hold. The held placement is pinned to the top of the safe area.
- **Revert check.** With `Manager+callbacks.swift`, `PanelController.swift` and
  `Manager+EmbeddedViewsDelegate.swift` reset to HEAD, and the hold disabled in `S1ScalingContainer`
  (the scale assignment changed to `nil`): 27 executed, 4 tests failed.
  - The resize test failed: constraint 337, no size requested, keys 387.
  - The navigation test failed: FX offered the sequencer.
  - With the hold disabled, both hold tests failed: the interface zoomed to 1.77 before the window grew.

  The files were restored byte-identical.
- **Full suite: 271 tests, 0 failures** (266 after ADR-036).
- **The running standalone**, launched from DerivedData with "shown" saved. Its window frame was
  sampled every 50 ms from the window list, in screen points with the origin top left. It opened at
  (352, 104) 1024 × 800, which is 768 plus the 32-point allowance. 0.6 s later it was (352, 104)
  1024 × 900: the top edge stayed put and the window grew 100 points at the bottom. No crash report.
  The owner's `settings.json` was copied first and put back byte-identical.
- **Not observed:**
  - Hide shrinking the standalone window, which needs a click;
  - the plugin in Logic, which is the open question;
  - opening the presets with the keyboard shown, which no test covers.

---

## ADR-038 — An unreadable file does not exist; never install a plugin signed for testing

**Status.** Accepted (bug fixed). 2026-09-10. Found from the owner's report in Logic.

**Symptom.** In Logic, the plugin's presets panel was empty, the header read "0: Init", and ▶
crashed the plugin (`ArcadeRuinsAU-2026-09-10-212840.ips`). The crash is at
`PresetsViewController.nextPreset()` line 324, `presetBank[0]`, an index out of range. Its binary
UUIDs match the build installed at 21:25.

**Cause, measured.**
- **The plugin loaded no banks.** It writes `currentPreset.json` in its container whenever the current
  preset changes, including at launch. In the 21:25 build it never did, in Logic or in the scratch
  host (`Scripts/debug/auhost.swift`). `didSelectPreset` returns early only when there are no banks.
- **It cannot read the shared folder, but can see that the files exist.** lldb attached to the
  installed plugin in the scratch host, with Objective-C expressions in its sandbox, returned:
  - `fileExistsAtPath` for the folder and for `banks.json`: YES;
  - `isReadableFileAtPath` for `banks.json`: NO;
  - `NSData` length for `banks.json` and `BankA.json`: 0;
  - listing the folder: `nil`.

  This is exactly ADR-020's measurement. `Disk.exists` sent `Manager` down the load path, the read
  threw, and `loadBankSettings` caught it and left `Conductor.banks` empty. So `loadBanks` loaded
  nothing, the list was empty, and ▶ indexed an empty bank. Upstream never guards that index.
- **Why the plugin could read the folder earlier today.** STATE recorded the plugin as
  "`absolute-path.read-only` `/`", and the owner had starred presets in its list. That entitlement
  was never in `SynthOneAU.entitlements` or its history. A sweep of every plugin build on disk found
  it only in a build made by `xcodebuild test`, together with `testmanagerd` mach-lookups. Xcode adds
  those for the test runner. Earlier installs shipped a `./DerivedData` product that a test run had
  just signed, and a following `xcodebuild build` with nothing to compile did not re-sign it. At
  ADR-037 the tests moved to a scratch folder so as not to collide with another session, so the
  21:25 install was the first plain build, with the plugin's real sandbox.

**Decision.**
- **`Disk.exists` is "exists and readable"** (`isReadableFile`). Every caller asks whether to load or
  fall back: settings, banks, each bank's presets, tunings. So the plugin now loads the factory banks
  from its framework bundle, as ADR-020 intended. Its saves to the shared folder still fail silently,
  so the owner's files are not overwritten. The standalone can read everything, so nothing changes
  for it.
- **`nextPreset` and `previousPreset` return when the bank is empty**, and `previousPreset` no
  longer indexes past the end of the bank. `PORT FIX` at both.
- **`Scripts/validate-au.sh` refuses to install a plugin whose signature carries `testmanagerd`.**

**Consequences.**
- **The plugin shows the factory banks, not the owner's own presets or favourites.** To show those, it
  needs read access to the shared folder. There are two ways: an explicit read-only
  temporary-exception entitlement (ADR-018 found the read-write kind denied under ad-hoc signing;
  read-only is not measured), or ADR-020's user-picked folder bookmark. **That is the owner's call.**
- Every earlier observation of the plugin reading the shared folder was made on a test-signed build.

**Verification.**
`PluginPresetFallbackTests.swift` adds three tests. Each takes read permission away from files in
a folder of its own, to stand in for the sandbox.
- `testAFileThatCannotBeReadDoesNotCountAsExisting`.
- `testUnreadableSharedPresetsFallBackToTheFactoryBanks` runs `Manager`'s bank load and the presets
  panel's `loadBanks` against an unreadable `banks.json` and `BankA.json`. It requires all 12 banks,
  and BankA's presets equal to what the bundle ships (41).
- `testTheArrowsDoNothingWhenTheBankIsEmpty`.

Results:
- **Revert A**, `Disk.swift` at HEAD: the unreadable-file test failed. The fallback test failed with
  0 banks (not 12) and 0 BankA presets (not 41), which is the plugin's empty list. Run twice, the
  second time after the assertion below was corrected.
- **Revert B**, the preset navigation at HEAD, running the arrow test alone: it crashed with
  `Fatal error: Index out of range`, as the plugin did in Logic. Both files were restored
  byte-identical.
- **A wrong first assertion, caught.** The fallback test first required more than 100 BankA presets,
  a number taken from the owner's BankA, which holds 135 including the bonus presets. The bundle ships
  41. It now compares against the bundle.
- **Full suite: 274 tests, 0 failures** (271 before).
- **The app was rebuilt in `./DerivedData` as a plain build.** Its plugin carries no `testmanagerd`
  lookups and no `absolute-path` exception.
- **Not yet verified:** the installed plugin with the fix, in the scratch host and in Logic.
- **Installed 2026-09-11 08:30 with no host running, and checked outside Logic.** `validate-au.sh`
  passed its new signature check and `auval`. The installed `SynthOneCore`, the plugin binary and
  the compiled `Main.storyboard` match the plain build, and the installed plugin carries no
  `testmanagerd`. Loaded in `Scripts/debug/auhost.swift`, it rewrote its container's
  `currentPreset.json` two seconds after launch, with BankA position 0, "Synthwave 1974". So banks
  and presets loaded, which the 21:25 build never did. No crash report. The list and ▶/◀ in Logic are
  the owner's to check.

---

## ADR-039 — One view: the compact keyboard strip, and no Show/Hide

**Status.** Accepted. 2026-09-11. The owner's decision after trying ADR-037. **Supersedes ADR-037**,
which is reverted, and ADR-035's Show.

**Context.** ADR-037 made Show a 1024×868 interface with 188-point keys, and Hide upstream's 1024×768
with 88-point keys, and resized the window between them. The owner preferred the hidden view: Show
"only elongates the virtual keyboard a bit, and doesn't add much value". They asked for the hidden
view as the standard and for the toggle to go.

**Decision.**
- **One design size, upstream's 1024×768.** ADR-035's storyboard still runs the keyboard container to
  the bottom edge, so the keys are whole and 88 points tall, with 4 octaves and shading.
- **ADR-037 is reverted, not left in as dead code.** These go back to their state before ADR-035,
  commit b7a9313:
  - `S1ScalingContainer`, `SceneDelegate`, `SynthOneAudioUnitViewController` and `SynthOneApp`;
  - the four `Manager` and panel files ADR-037 changed;
  - their tests.

  Only ADR-035 and ADR-037 had touched them since. The window no longer resizes, and the plugin's
  `preferredContentSize` is fixed. With the keyboard always hidden, upstream's hidden-keyboard paths
  are correct as they are, so ADR-037's `keyboardCoversLowerPanel` checks go too.
- **The Show/Hide button is hidden** in `Manager.viewDidLoad`. Its callback stays, and runs at launch
  with 0, as upstream's does.
- **`AppSettings` ignores a saved `showKeyboard`**, so a "shown" saved by upstream or by ADR-037's
  build cannot raise the keyboard over the lower panel.
- **Kept from ADR-035:** the bottom constraint, 4 octaves, the popover's 1 to 5, `keybedVersion`'s
  one-time octave switch, and the shading.

**Consequences.**
- **The right end of the toolbar is empty** where the button was (x 934–1009). Whether to re-space
  Transpose and Octave is the owner's call.
- **ADR-037's navigation fix is no longer needed.** The top panel's buttons offered the panel below
  them only while the keyboard was shown, which can no longer happen.
- **`S1ScalingContainer.designSize` is 1024×768 again.** Tests that lay out at a fixed size use it.

**Verification.**
`KeybedTests` has 10 tests, one view throughout. The keys run from 680 to 768 with the lower
panel uncovered and both wheels above the edge. The toolbar has no Show/Hide. A saved "shown",
from upstream or under the keybed, is ignored. The 4-octave default and its one-time switch are
kept, the Keys popover offers 5 octaves, and the shading is drawn at the real 88-point height.
`ScalingContainerTests`, `UILoadTests` and `PointerInputTests` are back to their b7a9313 versions.
The ADR-037 tests went with the code they covered.
- **Revert check.** With `Manager.swift` at b7a9313 (no hide line) and `AppSettings.swift` at HEAD
  (reading `showKeyboard` again): 10 executed, 2 failed, exactly the two that cover them. A saved
  "shown" loaded as 1.0, and the Show/Hide button was still on the toolbar. Both files were restored
  byte-identical.
- **Full suite: 269 tests, 0 failures.** That is 274 before, less the five ADR-037 tests.
- **The app was rebuilt in `./DerivedData` as a plain build**, with no `testmanagerd` in the plugin.
- **Not yet:** installed, or seen by the owner.

---

## ADR-040 — About loses its tagline and video link; More goes, and factory BankA includes the bonus presets

**Status.** Accepted. 2026-09-11. The owner's request.

**Context.**
- **The About screen** carried upstream's tagline, "World's First Free & Open-Source Pro iOS Synth"
  (label `s4D-if-VhP`), and a "How Synth One was made" button (`aDf-IB-L3u`, outlet `videoButton`)
  that opened a YouTube video. Neither fits a Mac port. The owner asked for both to go.
- **The owner asked what More does now that the presets are loaded, and to remove it if nothing.**
  Upstream's More unlocks 94 bonus presets after a mailing-list sign-up. This port's MailChimp key
  is `***REMOVED***`, so `morePressed` always takes the fallback path. That path shows "Bonus presets
  have been added to BankA", marks the list signed, and runs `addBonusPresets`. `addBonusPresets`
  appends `Bonus.json` to BankA **without checking for duplicates**, and the button stays enabled.
  - **In the standalone** the owner's BankA already holds 93 of the 94. Another click would add them
    again.
  - **In the plugin**, which cannot save (ADR-020, ADR-038), a click adds them for the session only.
  - It was the only route by which a fresh install or the plugin's preset list got the bonus
    presets. The host's factory-preset menu already offers `Bonus`.

**Decision.**
- **About.** The tagline and the video button are deleted from `About.storyboard`, along with the
  outlet and its callback in `AboutViewController`. The credits box moves up into their space: it now
  runs from y 52 to 502, where it ran from 140 to 502.
- **More is hidden** in `HeaderViewController.viewDidLoad`, the same way the dev button already is.
- **Factory BankA includes the bonus presets.** In `loadBanks`, when BankA is built from the factory
  files (a fresh install, or the plugin, which cannot read the shared folder), `Bonus.json` is loaded
  into it, as `addBonusPresets` did. A saved BankA, like the owner's, is loaded as it is, so nothing
  is duplicated.

**Consequences.**
- **Nobody loses the bonus presets,** and the duplication risk is gone.
- **The header has an empty slot between Save and Panic.**
- **The mailing-list scenes stay in the storyboards,** unreachable, as they already were.
- **"Learn how this app was made"**, the grey caption under the Website button, is not a link, and
  was left.

**Verification.**
`AboutAndHeaderTests.swift` adds two tests.
- The header's More is hidden, and the rest of the header is not.
- The About screen has no tagline and no video link, keeps its other links, and has a credits box
  that starts no lower than y 60 and still ends at 502. It also writes `Renders/ui/07-about.png`.

`PluginPresetFallbackTests` now requires factory BankA to be `BankA.json` plus `Bonus.json`: 135
presets.
- **Revert check.** With `About.storyboard`, `AboutViewController.swift`, `HeaderViewContoller.swift`
  and the preset loader at HEAD, 5 executed and exactly 3 failed:
  - the About test (tagline present, link present, credits at y 140);
  - the header test (More present);
  - the fallback test (41 presets, not 135).

  The files were restored byte-identical.
- **What the first full run caught.** Removing the Swift `videoButton` outlet left the iPhone About
  scene's connection dangling. Both storyboard sweeps, `MacIdiomControlTests` and
  `TextInputAppearanceTests`, threw `NSUnknownKeyException` for `videoButton`. The new About test had
  passed, because it loads only the iPad scene. The iPhone scene's tagline, its button ("Synth One in
  action") and the outlet were then removed. That run is the without-fix evidence: the sweeps pass now.
- **Full suite: 271 tests, 0 failures** (269 plus the two new tests).
- **Renders.** `07-about.png` shows the credits directly under the logo. `00-main.png` shows the header
  without More.
- **The app was rebuilt in `./DerivedData` as a plain build**, with no `testmanagerd`.
- **Installed 2026-09-11 08:53 with no host running, together with ADR-039.**
  - `validate-au.sh` passed its signature check and `auval`.
  - The installed `SynthOneCore` and plugin binary match the plain build by md5, and the compiled
    About, Header and Main storyboards are identical.
  - The installed plugin carries no `testmanagerd`.
  - In `Scripts/debug/auhost.swift` it rewrote `currentPreset.json` at launch (BankA position 0), so
    presets loaded.
  - No crash report.

---

## ADR-041 — Signed with the owner's team: the app and the plugin share presets through an App Group

**Status.** Accepted, in progress. 2026-09-11. The owner joined the Apple Developer Program to get
preset saving in the plugin. **Supersedes** ADR-005's ad-hoc signing for the two products, ADR-006,
ADR-018's shared folder, and ADR-020's factory-only plugin.

**Context.** The sandboxed plugin could see the standalone's folder,
`~/Library/Application Support/SynthOne`, but could not read or write it (ADR-020, ADR-038). So it
offered only factory presets, and its star, rename, duplicate, reorder and Save all failed silently.
An App Group is the sanctioned way for two processes to share files, and it needs a Team ID
(ADR-006). The owner's team is **8RSH7U3222**, an individual team, with an Apple Development
certificate valid until 2027-09-11.

**The owner's decisions.**
- The first signed build may register the two app IDs, the App Group and this Mac in the owner's
  developer account.
- **Share presets, banks, favourites and tunings only.** Each product keeps its own settings.

**Decision.**
- **Signing.** The app and the plugin use a new `TeamSigned` template: automatic signing, team
  8RSH7U3222, "Apple Development". Build them with `-allowProvisioningUpdates
  -allowProvisioningDeviceRegistration`. The framework and the test bundle stay ad-hoc: the app
  re-signs the framework when it embeds it, and the tests need no identity.
- **The App Group** `group.com.badpackets303.ArcadeRuins` is in both products' entitlements. The app
  stays unsandboxed; the plugin stays sandboxed.
- **Storage** (`Disk`):
  - `.documents`, which holds banks, presets (with their favourite flags) and tunings, resolves to
    `Library/Application Support/SynthOne` inside the group's container. A process without the group
    falls back to the old folder.
  - A new `.settings` holds `settings.json`, in each product's own Application Support folder. For the
    unsandboxed app that is the old folder, so the owner's settings stay where they are. For the plugin
    it is its sandbox container.
  - The three `settings.json` call sites in `Manager` use `.settings`. `PORT (ADR-041)`.
- **The owner's files come across once.** `SynthOneApp.start`, in the standalone only (the plugin
  cannot read the old folder), runs `copyLegacySharedFilesIntoGroupIfNeeded`. It copies every `.json`
  except `settings.json` from the old folder into the group, then leaves a marker.
  - It copies and never moves, so the old folder is a backup.
  - On its one run it replaces files already in the group, because they can only have come from a
    plugin that started with the factory banks.
  - After the marker, nothing in the group is replaced.
  - If a copy fails, it leaves no marker and tries again at the next launch.
- **`Scripts/validate-au.sh` refuses to install** an app or plugin not signed by team 8RSH7U3222 with
  the group.
- **Tests run unsigned:** pass `CODE_SIGNING_ALLOWED=NO`. The first attempt,
  `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`, did not build: with the App Group
  in the entitlements, Xcode demands a provisioning profile for manual signing, and
  `CODE_SIGN_IDENTITY[sdk=macosx*]` cannot be set from the command line. On Apple Silicon the
  linker's own signature is enough for the test bundle to load. `PlatformTests` checks both
  entitlements files name the group `Disk` uses.

**Consequences.**
- **The plugin can save presets, favourites, renames, reorders, new banks and tunings,** and they
  appear in the standalone, and the reverse. Neither refreshes a list the other already has open: the
  last save wins, and the other sees it after reopening.
- **The plugin's settings are its own,** and persist for the first time.
- **Share still crashes in the plugin.** That is a UIKit share-sheet bug, not storage (STATE, still
  open).
- **Every signed build depends on this Mac's certificate and on Apple's WWDR G3 intermediate,** which
  the owner installed separately.

**Verification.**
**The signed build.**
- **The first try failed** with "Build input file cannot be found" for a provisioning profile that
  was still downloading. The second, with the same flags, succeeded.
- **Both products** carry TeamIdentifier 8RSH7U3222, `group.com.badpackets303.ArcadeRuins` and an
  embedded profile, and no `testmanagerd`.
- **The profile is Xcode's wildcard "Mac Catalyst Team Provisioning Profile: \*"** (`8RSH7U3222.*`, this
  Mac provisioned, expires 2027-09-11). It does **not** list the App Group. Xcode registered no
  explicit app IDs.

**The standalone, measured.** The signed DerivedData app was launched with the owner's folder backed
up first (15 files).
- It created `~/Library/Group Containers/group.com.badpackets303.ArcadeRuins/`, copied all 14
  `.json` files except `settings.json` byte-identical (BankA 135 presets), and left the marker.
- No TCC or container-manager messages mentioned it, and there was no crash report.

So an unsandboxed process in this team reaches the group without the group in its profile.
**Whether the sandboxed plugin does is the remaining measurement**, and it needs an install, because
a host loads the plugin from `/Applications`.
**Tests** (`CODE_SIGNING_ALLOWED=NO`).
- `PlatformTests` adds four:
  - the shared folder is never one process's container;
  - settings are kept apart from it;
  - both entitlements files name the group `Disk` uses;
  - the old folder is copied into the group once, and nothing is copied when the shared folder is the
    old one.
- `StorageIsolationTests` requires the keyboard toggle's settings save to land in the settings folder,
  not the shared one, and its snapshot of real files covers the shared, old and settings folders.
- **Revert A:** the two settings call sites at HEAD, and the marker guard deleted from
  `copyLegacySharedFilesIntoGroupIfNeeded`. Exactly two tests failed:
  - the settings save landed in the shared folder;
  - a second copy ran, replacing a later save.
- **Revert B:** `project.yml` at HEAD, regenerated. The entitlements test failed for both files. All
  files were restored byte-identical.
- **Full suite: 275 tests, 0 failures** (271 plus four).
**The first install did not load. Two things were wrong, and only one of them was the hang.** The
signed build installed 2026-09-11 11:01 carried `group.com.badpackets303.ArcadeRuins` under Xcode's
wildcard team profile, which does not list the group.
- `auval` found the component ("\* \* PASS"), then failed the cold open with `OpenAComponent:
  result: -10863`.
- In the scratch host the plugin process started and stayed alive, but it loaded no presets, wrote no
  settings and touched nothing in the group. There was no crash report.
- **A `sample` of the plugin** showed its main thread at 0% CPU, still inside dyld's
  `libSystem_initializer`: `_libsecinit_initializer` → `_libsecinit_appsandbox` → `_xpc_pipe_routine` →
  `mach_msg2_trap`. It was blocked on `secinitd` before any of our code ran. The unsandboxed app never
  goes through that path.
- **An lldb expression inside it had failed earlier** with `EXC_BAD_ACCESS`, which was the same stuck
  process rather than a separate bug.

**Problem 1, the group name (real, but not the hang).** `containermanagerd` rejected `group.…` for both
products, 10:59 and 11:01: "Group containers identifiers should be prefixed by requestor's team ID to
allow access on this platform." Fix: the group is `8RSH7U3222.com.badpackets303.ArcadeRuins`, the
macOS form, which needs no profile listing it. The signed standalone's request for it was
**APPROVED** at 11:16:36. That is a new container, so the one-time copy ran again: the marker and 13
of 14 files byte-identical. The 14th, `tunings_v1.json`, parses equal: the app re-serialises it at
launch. The standalone is not sandboxed, so the rejection had not stopped its earlier copy into
`group.…`. That container holds only a copy of the owner's files, and was left in place.

**Problem 2, the hang: a consent prompt for the plugin's own container.** The rebuilt plugin hung
exactly as before. A `sample` of `secinitd` (the per-user one) showed a thread on the serial queue
`com.badpackets303.ArcadeRuins.AUv3` parked in `-[AppSandboxRequest displaySharingConsentPrompt:]` →
`CFUserNotificationReceiveResponse`. Its log at 11:01:23:

> binary identity <<8RSH7U3222/com.badpackets303.ArcadeRuins.AUv3; signer:development>> not in ACL for
> container ~/Library/Containers/com.badpackets303.ArcadeRuins.AUv3/Data
> <[{"signingIdentifier":"com.badpackets303.ArcadeRuins.AUv3","validationCategory":"none"}]>; prompting

The container was created by the ad-hoc builds. Its metadata still lists that owner, so macOS asks the
user whether the differently-signed plugin may use it. The dialog appeared on a display nobody was
looking at and was never answered. Every later launch, including the Team-ID build's six `auval`
attempts and the probe, waited behind it on that queue. This is a one-time transition from ad-hoc to
team signing: once answered, the team identity is in the container's ACL.

- The earlier "nothing in the TCC or container logs" was wrong. `log` in the Bash tool's zsh is a
  shell builtin, not `/usr/bin/log`, and the first predicate matched nothing. Use `/usr/bin/log`.
- **`validate-au.sh` reported success after six failed `auval` attempts.** `status=$?` after a plain
  `if … fi` reads the `if`'s own status, which is 0. Fixed by taking the status in the `else` branch.

**Verified in Logic, 2026-09-11 11:33.** The owner clicked Allow; `secinitd` logged "user consented to
launching <<8RSH7U3222/com.badpackets303.ArcadeRuins.AUv3; signer:development>>", and the container's
Owners now list the team identity beside the ad-hoc one. The plugin then loaded in the owner's Logic
(no crash report), wrote its own `settings.json` and `currentPreset.json` in its container, and at
11:34:13 saved `BankA.json` into the group: parsed against the untouched original, exactly one change,
"Synthwave 1974" `isFavorite` false → true, with the same 135 presets in the same order. Only read-only
checks ran while Logic was open. Unsigned full suite after the rename: 275 tests, 0 failures.

---

## ADR-042 — No pop-ups at launch; the window opens at the design size

**Date:** 2026-09-11 · **Status:** Accepted (owner's choice)

**Context.** The owner opened the standalone after ADR-041 and sent a screenshot. Two problems:

- **A clipped card.** "SYNTH ONE + SHARE ONE!" was cut off below its text, and none of its buttons were
  visible. It is upstream's "Sharing is Caring" scene, `SharingIsCaring` in `MailingList.storyboard`,
  with Share, Watch Intro Video (AudioKit's YouTube video) and Start Playing. `Manager.viewDidAppear`
  shows it on every 7th launch; the owner's `settings.json` had just reached 7. `SegueToSharing` has no
  presentation style, so on the Mac it opened as a sheet shorter than the 1024×768 scene, which pushed
  the 560×364 card down and cut it off. The other pop-ups use `overCurrentContext`.
- **Empty space around the interface.** The window was 1024×900, ADR-037's "shown" size, and macOS
  kept reopening it at that size. In the owner's screenshot the interface sat at the top with about 100
  points empty below, with the clipped sheet on screen. Measured with lldb on the same code without the
  card, the window, its root view and the scaling container were all 1024×900, and the interface was
  centred at y = 82, leaving a 50-point band above it and another below.

The same launch-count block held more prompts aimed at upstream's App Store app: a "please give a Great
rating" alert on the 5th launch, an App Store review request every 50th, and a push request on the 9th
and every 75th. Push was already compiled out on Catalyst. The plugin runs the same `Manager` and counts
its own launches (3 at the time), so it would have shown the rating alert at 5 and the card at 7, and
Share crashes in the plugin.

**Decision.**

1. **Every launch-count prompt goes**, in both products. The owner chose this over fixing the card or
   keeping upstream's behaviour. The call sites are removed from `Manager.viewDidAppear` with a
   `PORT (ADR-042)` comment. `reviewPopUp`, `pushPopUp`, the segues, the scene and `launches` stay.
2. **The window cannot reopen larger than the design.** `SceneDelegate.configure` sets the scene's
   maximum size to 1024×800, the design plus the title-bar allowance. One second after the window is up,
   `willConnectTo` raises it to three times the design. A reopened window is held to the design size,
   and the owner can still enlarge it afterwards. Upstream's comment already says the app opens at 1:1,
   so a saved size is not honoured.

**What did not work.** Each was measured on the DerivedData standalone with 1024×900 saved:

- **`requestGeometryUpdate(.Mac)` on the first `sceneDidBecomeActive`.** The window stayed 1024×900.
  Diagnostic `NSLog`s around the call never appeared in `log show`, even after lldb called
  `sceneDidBecomeActive:` by hand. So those logs proved nothing either way.
- **Rewriting `NSWindow Frame MainSceneWindow` to 1024×800 before launch.** The window still opened at
  900, and the app saved 900 back.
- **The saved scene session** (`KnownSceneSessions/data.data`) holds no frame. Where macOS keeps the
  size was not found. The cap does not depend on it.

**Rejected.**

- **Fixing the card's presentation** with `overCurrentContext`. That would repair the display, but the
  owner did not want the prompt.
- **Honouring the saved size and centring the interface in it.** That is what the build already did,
  and the bands were the complaint.

**Verification.** `LaunchPromptTests` runs `Manager.viewDidAppear` with a saved launch count. Because the
test bundle has no window, it replaces `performSegue` and `present` to record what would have appeared,
and swaps in a review spy. With the fix, 4 tests pass. With `Manager.swift` at HEAD, exactly 3 fail: the
5th launch showed the "Thank you" alert, the 7th performed `SegueToSharing`, and the 50th asked for a
review. The fourth test, the recorder's premise, passed both times. The file was restored byte-identical. Full suite: 279 tests, 0 failures.

The window has no unit test, because the test bundle cannot make a window. Measured with lldb on the
DerivedData standalone:

- **Before the cap:** six launches of uncapped builds, background and foreground, all opened at
  1024×900 with the interface at y = 82.
- **With the cap:** the window opened at 1024×800 with the interface at y = 32, exactly 1:1 under the
  window buttons. By 10 seconds the maximum size was back to 3072×2336. The app saved
  `344 226 1024 800`, the same top edge as `344 126 1024 900`.
- **The revert check could not recreate the fault.** After the first capped launch, the build without
  the cap (`SceneDelegate` at HEAD) also reopened at 800. That held whether the window had been set to 900
  with `NSWindow setFrameFromString:` or with `requestGeometryUpdate` called through lldb (which did
  resize it), and whether or not 900 was saved in the defaults. With the cap restored it reopened at 800
  again.

So the cap is the only change observed to turn the 900 reopening into 800, but whatever held that size is
gone and could not be rebuilt. It stays as a guard. It costs nothing the app did before: the uncapped
build already reopened at 1:1 after a resize.

---

## ADR-043 — The standalone restarts its engine when the audio hardware changes

**Date:** 2026-09-11 · **Status:** Accepted

**Context.** After ADR-042 was installed, the owner reported that the plugin worked and the standalone
made no sound. The standalone's own log (pid 80966) held the whole sequence:

- **14:40:23.** `Conductor.start(mode:)` logged "engine started (realtime)". Output was running, routed to
  head-tracked headphones.
- **14:40:33.** coreaudiod re-ranked the default devices after a Bluetooth headset reported "out of ear".
  The default input changed, then the default output; it is now "USB Audio Device".
- **14:40:33.503.** AVAudioEngine logged "iounit configuration changed > stopping the engine" and posted
  its configuration-change notification.
- **Nothing restarted it.** Output went to Stopped at 14:40:35 and stayed there until the owner quit at
  14:42:24.

Nothing in the port listened for `AVAudioEngineConfigurationChange`. The only route-change handling in
the repository is in upstream's unported Link code. The plugin was unaffected, because its host owns
the audio device.

**A red herring.** In the same second, tccd logged that the standalone was refused the microphone without
a prompt: under the hardened runtime, `kTCCServiceMicrophone` needs
`com.apple.security.device.audio-input`, which the app deliberately lacks (P3-4). Team-signed builds carry
the hardened-runtime flag, although the target's `ENABLE_HARDENED_RUNTIME` reads NO; where the flag comes
from was not traced. The request came from CoreAudio rebuilding its input-output aggregate during the
device change. The input stream was set to unused, the session is `.playback`, and output stopped
because of the configuration change, not the refusal.

**Decision.** `S1AudioEngine` observes `AVAudioEngineConfigurationChange` for its own engine only.
`start()` sets `shouldBeRunning`, and `pause()`, `stop()` and offline rendering clear it. When the engine
stops itself while `shouldBeRunning` is still set, it starts again on a background queue, up to five
tries half a second apart. Nodes stay connected through a configuration change and the output unit
converts to the new device's format, so the graph is not rebuilt, which also leaves the recorder's and
the plot's taps alone.

**Rejected.** Reconnecting the mixer to the output on every change. Apple requires it only when a
connection's format must change; ours are made with a nil format, and disconnecting the mixer's output
risks the recorder's tap. Revisit if a device with a different channel count comes up silent.

**Verification.** Four tests in `S1AudioEngineTests` replace the restart with a counter and post the
notification. A real restart would open a hardware device, which blocks an xctest process for 90 seconds
(ADR-015). The four tests check that a change restarts an engine that should be running, and that it
does not restart a paused engine, respond to another engine's change, or restart an offline render.

- **With the fix:** 12 of 12 engine tests pass.
- **With the observer doing nothing:** exactly 1 fails, the restart test ("0 is not equal to 1").
- **With `pause()` leaving the flag set:** exactly 1 fails, the paused-engine test.
- The file was restored byte-identical. Full suite: 283 tests, 0 failures.

That `start()` sets the flag is outside the tests' reach, so it was checked on the running DerivedData
standalone, with lldb and the engine's address from its log:

1. After launch the engine was running.
2. **Control:** stopped with no notification, it was still stopped 3 seconds later.
3. Stopped and sent `AVAudioEngineConfigurationChangeNotification`, it was running again 3 seconds later.
   The app logged "restarted after the audio hardware changed (attempt 1)" 90 ms after the notification.

**Confirmed by the owner** on the installed app, 2026-09-11: audio works, including after switching
outputs.

---

## ADR-044 — Share in the plugin exports through a Save dialog

**Date:** 2026-09-11 · **Status:** Accepted (owner's choice)

**Context.** Share crashed the plugin in both places it appears, a preset's Share button and a bank's.
Three crash reports (2026-09-10 17:32 and 17:33, 2026-09-11 14:57) share one stack:
`UIActivityViewController _beginBridgedPresentation` → `UINSShareSheetController
presentWithConfiguration:uiWindow:rect:` → `_sceneViewRectFromUIWindowRect`, which fails an
`NSAssertionHandler` check.

- **Why:** UIKit's Mac bridge places the share sheet relative to the presenting view's window, and a
  plugin's view lives in the host's window rather than one of its own.
- **Why it can't be caught:** the exception is thrown from UIKit's post-commit block, after `present`
  has returned.
- **The standalone** presents the same sheet without error.

The owner was offered hiding Share in the plugin, as Record already is (P4-6), or replacing it with
Export. They chose Export.

**Decision.** Both buttons go through `PresetsViewController.share(_:)` in `Presets+Share.swift`, which
writes the same temporary file upstream does and presents `makeShareController(for:hosted:)`:

- **In the plugin** (`conductor.isHosted`): `UIDocumentPickerViewController(forExporting:asCopy:)`, a Save
  dialog that copies the file wherever the user chooses. The plugin's sandbox already has
  `files.user-selected.read-write`, which a Save dialog needs.
- **In the standalone:** upstream's share sheet, unchanged.

**Unknown until tried in Logic.** Whether a document picker can be presented from the plugin at all. It
is bridged to a Mac panel too, and may meet the same window problem. No crash report involves one, but
nothing shows the plugin's Import button, which uses the same kind of picker, was ever pressed.

**Verification.** `PluginShareTests` checks the choice both buttons go through: the plugin gets a
document picker and never the share sheet, and the standalone keeps the share sheet with
copy-to-pasteboard excluded.

- **With the fix:** 2 of 2 pass.
- **With the plugin branch disabled:** exactly the plugin test fails, on both of its assertions.
- The file was restored byte-identical. Full suite: 285 tests, 0 failures.
- **A first run failed my own assertion** that the picker shows file extensions: the setter did not
  read back in the test bundle. The setting and the assertion were removed rather than kept unverified.
- **Not reachable from the tests:** that the two buttons pass `conductor.isHosted`, which only a real
  host sets, and whether the Save dialog appears in Logic. The owner has to try both.
- **Installed** 2026-09-11 15:23. The installed framework references `initForExportingURLs:asCopy:` and
  the `makeShareController` symbol. Two more share-sheet crash reports, at 15:19:33 and 15:22:10, were
  written by the previous build, before the install.
- **Confirmed by the owner in Logic, 2026-09-11:** Share works in the plugin. The Save dialog does
  present from the extension, so the unknown above is settled.

## ADR-045 — The desktop layout re-homes the classic controls; the classic layout stays a launch option

**Date:** 2026-09-12 · **Status:** Accepted (owner's choice) · **Phase 6, P6-0 and P6-1**

**Context.** The interface was upstream's 1024×768 iPad layout, scaled to the window (ADR-019): two
panel slots cycled by arrow rails, a fixed keyboard strip, popovers for the rest. The owner asked what a
desktop-native interface would look like, chose a single-screen layout from a design canvas
(<https://claude.ai/code/artifact/4623edc1-39b7-4667-a58d-eb810d176f41>, page 1), refined it four times
in one afternoon (tabs tried and rejected; texture added; effects given a full row; the virtual
keyboard dropped so the sequencer's faders could be tall), and asked for it to be built **as a new
version that keeps the old one recoverable.**

This relaxes hard requirement 1 ("preserve the user interface") for the first time, at the owner's
explicit request. Requirement 2, preserve functionality, still binds in full. Upstream's README
warning about App Store rule 4.1 also stops applying to a redesigned interface.

**Decision.**

1. **The old interface is kept two ways.** Git tag `v0.1.0-classic-ui` marks the last classic commit,
   and `S1Layout` keeps the classic layout in the build behind a user default
   (`defaults write com.badpackets303.ArcadeRuins S1ClassicLayout -bool YES`, or View ▸ Classic
   Layout, applied at the next launch). Version 0.2.0 (build 2) on branch `desktop-ui`.
2. **The desktop layout re-homes the classic controls rather than replacing them.** `Manager` and the
   twelve storyboards load exactly as before, so every knob, switch, picker, slider and pad exists, is
   bound to its parameter by the same `Conductor.bind`, answers MIDI learn and VoiceOver, and drives
   the same 150 parameters. `S1DesktopLayout` then builds the Mac window over `Manager`'s view — a
   toolbar under the traffic lights, a preset sidebar, four rows of titled sections, a play bar and a
   status bar — hides the classic hierarchy, and **moves the control views** into the sections. Nothing
   is rebound. The alternative, new views bound afresh to 150 parameters, was rejected: it duplicates
   every range, taper, callback and `updateUI` special case in the panel controllers, and every one is
   a chance to drift from the sound.
3. **Two dresses on one control.** `Knob.drawsDesktopStyle` and `ToggleButton.drawsAsSwitch` switch
   the drawing to `S1DesktopStyle` — a value arc round a brushed cap, a pill switch — while the classic
   PaintCode kits still draw in the classic layout. `Knob.valueDidChange` feeds a readout under every
   knob (`S1ControlCell`), so a value the user sees is always the value that sounds.
4. **What stays whole.** The preset browser and the Tunings panel are shown as sheets
   (`S1PanelSheet`), which adopt the panel as their child while up so its own popovers present
   correctly. The sidebar proper is P6-6. The classic keyboard, wheels and their settings stay loaded
   and hidden: `Manager`'s callbacks and the computer keyboard still route through them.
5. **Window.** No scaling container. `SceneDelegate` opens the desktop layout at 1440×900 (pinned for
   the first second, as ADR-042 does, because macOS restores the classic 1024×800 frame otherwise) and
   frees it above 1280×820. The plugin's `preferredContentSize` follows the layout.

**Consequences.**
- The storyboards are still the source of the controls; layout code moves them. A future session that
  deletes a storyboard control deletes it from both layouts.
- `Manager.appendMIDIControls` asks the layout where a panel's controls went; the classic path is
  unchanged.
- `VerticalSlider` re-measures its bar in `layoutSubviews`; it measured once, in `awakeFromNib`, because
  the storyboard fixed it at 160 points.
- Unsatisfiable-constraint noise: the hidden classic hierarchy's autoresizing constraints still exist.
  The root view's own 1024×768 constraints are deactivated; the rest breaks harmlessly and logs.
- The test bundle registers the classic default, so the 285 existing tests keep the scaling container
  they were written against; `DesktopLayoutTests` builds the desktop layout explicitly.

**Amended 2026-09-12 (owner).** Master (Volume, Anti-alias, Widen, Arp/Seq) sits at the end of the effects row, not in row one, so the Mix section has room for its seven knobs. Row one is OSC 1 · OSC 2 · Mix · Filter · Voice.

**Verification.** `DesktopLayoutTests`: every bound control is inside the desktop root (or is one of
the six classic controls deliberately kept back), the fifteen sections lay out at the design size, a
knob's readout follows its value, MIDI learn finds the moved knobs, and the sliders follow their new
height. The running app was rendered with `Scripts/debug/desktop_render.py` at 1440×900 on
2026-09-12 with the preset "Synthwave 1974" loaded; the render is the acceptance picture for P6-1.

## ADR-046 — Skins: a palette and decoration over the desktop layout, never a layout of their own

**Date:** 2026-09-13 · **Status:** Accepted (owner's choice) · **Phase 7, P7-0 to P7-3**

**Context.** With 0.2.0 ready, the owner showed a synthwave "Arcade Ruins" mock-up of the desktop
layout — neon orange and cyan on near-black, glowing knob arcs, grunge over the panels, a sunset over
a perspective grid in the header, an arcade cabinet down the sidebar, the preset list on a CRT — and
asked for it as a skin. Decided: finish P6-8 first, then build the skin **fully procedural**, with
no supplied artwork.

**Decision.**

1. **A skin is a palette plus decoration, and nothing else.** `S1Skin` (`Sources/SynthOneCore/Desktop/S1Skin.swift`)
   carries an `S1Palette` of every colour the layout and `S1DesktopStyle` use, a `glow` factor that
   scales every accent glow, and five hooks the layout consults while it builds: a texture for the
   sections, a glow colour for their border, a frame accent for the sidebar's lists and the XY pads,
   and factories for a wordmark, toolbar art and sidebar art. **Metrics, sections, rows, bindings and
   hit zones are not the skin's to touch.** `SkinTests.testBothSkinsLayOutEverySectionInTheSamePlace`
   holds every section to the same frame under both skins, so the layout tests that run under Studio
   cover Arcade's geometry.
2. **The theme keeps its names.** `S1DesktopTheme.orange`, `.text`, `.sectionBorder` … became computed
   properties reading `S1Skins.current.palette`; its 130 call sites did not change. `S1DesktopStyle`'s
   32 inline colours became palette entries named for their role (`wellTop`, `litBorder`,
   `faderCapTop` …), and Studio's entries are the exact values it shipped with: a Studio render after
   P7 differs from the 0.2.0 screenshot only in run state (the delay-time readout follows tempo, the
   sequencer's step moves).
3. **Arcade is drawn, not painted.** `S1ArcadeArt` draws the sun, mountains, grid, starfield, grunge
   and scanlines with Core Graphics from seeded pseudo-random sequences, so a render is the same twice
   and crisp at any scale. The header art is 48 points tall like the toolbar; the sun sits in the gap
   between the wordmark and the preset display, the one stretch with nothing over it at the design
   width. The mock-up's "Open Presets…" CRT panel is not adopted: the sidebar keeps its lists, each
   framed as a screen (`S1CRTFrame`: glowing border, scanline overlay, no inset).
4. **Chosen like the layout.** `S1SkinChoice` is a user default (`S1Skin`: `studio` | `arcade`), read
   once at launch; View ▸ Skin ▸ Studio | Arcade writes it and says the change applies next time.
   `-S1Skin arcade` as a launch argument works too (`desktop_render.py`'s `RENDER_ARGS`), so a skin can
   be rendered without touching the owner's defaults. The plugin has its own container and default.
   Studio is the default: the owner asked for an *option*.
5. **Version 0.3.0** (build 3), on `desktop-ui` after 0.2.0's release prep.

**Consequences.**
- A new colour in the layout is a new palette entry with a value for each skin; the compiler enforces
  it (the palette is a memberwise struct).
- `S1Skins.current` is read when views are built. A skin cannot change while the window is up; the
  choice applies at the next launch, like the layout.
- The classic layout has no skins: its colours are the storyboards'.
- `drawHierarchy(in:afterScreenUpdates:)` needs the app's window server and throws in the test host;
  `layer.render(in:)` draws the same `draw(_:)`, which is what the art tests use.

**Verification.** `SkinTests` (6): the default and its round trip; Studio's palette is the shipped one
and hangs no art; Arcade hangs its art, glows every section orange, frames the two lists and the two
pads, reads its values in cyan; both skins lay every section out in the same place; the art draws.
`DesktopLayoutTests` 22/22 and `DesktopPluginTests` 4/4 unchanged. Rendered on 2026-09-13 at 1440×900
and at 1180×900 with the sidebar hidden (`docs/screenshots/arcade-skin.png`).

## ADR-047 — The preset browser drops down from the toolbar; the sidebar is gone

**Date:** 2026-09-13 · **Status:** Accepted (owner's choice) · **Phase 8, P8-0** · Amends ADR-045 (P6-6) and ADR-046

**Context.** The owner changed their mind about the preset sidebar after living with it: "Let's have
it as a drop-down when a user clicks on the preset name at the top of the window. Get rid of the side
panel. That will give us more wiggle room to readjust some of the panel sections that still need
work."

**Decision.**

1. **The browser column is unchanged; where it lives changed.** The same re-homed classic tables,
   cells, buttons and notes field (P6-6) now sit in `S1DesktopLayout.presetPanel`, a 380×720 card
   that hangs 4 points below the toolbar, centred under the preset name, over the rows. A short
   window shortens it (the height constraint yields to the play bar). It is a subview of the
   layout's root, not a presented controller, so the browser's own presentations — the editors,
   Search, the share sheet — still present from `PresetsViewController` exactly as before, and the
   plugin gets the same panel with no window of its own to worry about (ADR-044).
2. **Three ways in, three ways out.** The preset name in the toolbar carries a chevron and a clear
   button over the whole field (`presetFieldButton`, accessibility label "Presets"); View ▸ Preset
   Browser is ⌥⌘P. A click anywhere else — a clear backdrop over the window catches it — Escape, or
   the same shortcut puts it away; so does any card presentation (`dressPresented` closes it first),
   since the Search and editor cards would otherwise sit under it. The toolbar's Presets button is
   gone: the name is the button.
3. **The rows have the whole width, and use it.** Row one's fixed sections grew (OSC 1 184, OSC 2
   204 with wider selectors, Filter 236 with a 60-point cutoff, Voice 156; 44-point knobs
   throughout, Mix keeps about 560 points); the LFO section is wider (×1.12) with 70-point mod
   chips and 30-point rate/amount knobs, which stops its readouts overlapping; the XY pads are 400
   wide. Rows one and two are 158 and 220 tall to fit, so the fourth row has 247 at 900 tall —
   about 84 points of fader travel, down from 100. The minimum window stays 1440×900: the width is
   now the rows', not a sidebar's, and there is no narrower mode.
4. **Skins follow.** `S1Skin.makePanelArt()` (was `makeSidebarArt`) draws behind the card; the CRT
   frames stay on the two lists and the two pads. The palette's `panelBackground` is the card.
5. **The Find menu is removed.** Search Presets has been ⌘F since P6-6 and the system Find item
   logged a shortcut conflict at every launch; a synth has nothing to find.

**Consequences.**
- `SynthOneApp.desktopSidebarDidChange` and `desktopMinimumWindowSize(sidebarVisible:)` are gone,
  and with them `SceneDelegate`'s observer; the window's minimum is one number again.
- `Manager.desktopTogglePresets(_:)` / `desktopClosePresets(_:)` replace `desktopToggleSidebar(_:)`.
- The render driver presses by accessibility label as well as title (`RENDER_PRESS=Presets` opens
  the browser).
- The README's sidebar and sidebar-hidden screenshots are replaced by one of the drop-down open.

**Verification.** `DesktopLayoutTests`: the browser's views are in the panel, the panel is 380×720
and hidden until asked, opens under the name 4 points below the toolbar inside the window and over
the rows, closes on the backdrop, Escape, ⌥⌘P and the menu selectors; the editor is as wide as the
root. `SkinTests` follow the rename. Rendered both skins closed and open on 2026-09-13.

## ADR-048 — Neon Ruins: a skin with one accent per section, and the drawing choices a skin can make

**Date:** 2026-09-14 · **Status:** Accepted (owner's choice) · **Phase 7, P7-4** · Extends ADR-046

**Context.** With the Arcade skin in, the owner said the interface still looked "very generic … no
character" and showed a second synthwave reference (ChatGPT's one-shot). Designed on a canvas
first, over the P8-1 geometry, through four rounds of the owner's direction: "still lifeless and
muted" (hotter glows, near-black panels, the real brand graphic); "the rust is too warm and seems
more like a glow reflection rather than texture" (neutral worn metal); "the orange is making the UI
too monotonous and overpowering — mix it up with other neon colors for different panels" (one neon
per section); then "build this as the third skin … make the Mix panel match the green of the Delay
panel." ADR-046's skin had one accent for the whole layout and drew every control in it.

**Decision.**

1. **A section can have its own accent.** `S1Skin.sectionAccent(for:)` answers a colour by the
   layout's section key ("Mix", "Filter Envelope", "Pads" …) or nil. `S1SectionView.accent` colours
   the border, the glow, the title's glow and the header's rule. **Every drawn control takes an
   `accent`** (`S1DesktopStyle.draw…(…, accent:)`), found through `UIView.s1Accent`: the nearest
   `S1SectionView`'s accent, else the palette's. Studio and Arcade name no section accents, so
   every control under them draws exactly as before; the eleven ported `draw(_:)` sites changed by
   one argument.
2. **The drawing choices a skin makes are a struct, `S1SkinDress`**, with defaults that are the
   Studio and Arcade behaviour: border width, glow radius and opacity, a second bloom, the knob's
   ring width and halo, a lit fader track, whether lit cells derive from the accent
   (`litFromAccent`: mixes of the accent with white and black replace `litTop`/`plateTop`/
   `chipActiveTop`/`faderCapTop`/`accentBorder` …), and the wordmark's frame. Metrics stay the
   layout's; the wordmark frame is the one number a skin may ask for, and Neon Ruins asks for
   220×24 because the owner's artwork is about 14:1 once its noise is trimmed (150×46, the canvas's
   guess, would show 10-point letters).
3. **Neon Ruins' accents** are a spectrum across each row — OSC 1/2 orange, Mix mint, Filter pink,
   Voice violet; Filter Envelope pink, Amplitude Envelope gold, LFO & Mod Targets violet; Reverb
   cyan, Delay mint, Phaser violet, Bitcrusher pink, Master orange; Sequencer orange, Pads cyan.
   Pairings follow function (the filter and its envelope, the two modulation sections); Mix is
   mint like Delay at the owner's request. Readouts stay cyan and off states are cyan-outlined
   everywhere, which is what keeps fifteen panels in six colours reading as one instrument.
4. **Its art is drawn like Arcade's** (`S1NeonRuinsArt`): a neutral grime tile (cracks with a pale
   edge, brushed scratches, sparse specks, grain — the first canvas pass's orange rust read as
   reflected light); a sunset header with the sun in the gap after the wordmark, a palm in the gap
   before the buttons, dimmed only under controls; a starfield and lit floor behind the preset
   browser; and a new hook, `makeBackdropArt()`, for nebulae and a magenta floor behind the whole
   window — the play bar and status bar are translucent under this skin, so the floor shows through
   them and in the gaps between rows. The wordmark is the owner's artwork in a new asset
   (`s1_wordmark_neon`, generated by `Scripts/branding/generate.py`) with an orange glow.
5. **Chosen like the others**: `S1Skin` = `neonRuins`, View ▸ Skin ▸ Neon Ruins, `-S1Skin
   neonRuins`. Studio stays the default. Still 0.3.0, which has not shipped.

**Consequences.**
- Two palette entries were added for it: `chipText` (an inactive target's label — cyan here,
  the label colour in the others) and `knobPointer` (white here; nil means the accent).
- `S1SegmentedControl` and the step-number box (`SliderTransposeButton`) take their lit colours
  from the accent too; both are dressed before they are placed, so they re-apply on
  `didMoveToWindow`.
- The canvas's marquee ("PLAY · CREATE · DESTROY · REPEAT") in the preset browser is not built:
  it would be a new view in the browser's column, a layout change.
- The joystick moved from `S1ArcadePanelArt.draw` into `S1ArcadeArt.drawJoystick`, unchanged, so
  both browsers draw it.

**Verification.** `SkinTests`: every section under Neon Ruins has its accent, its glow is that
accent, Mix and Delay are mint, Filter and its envelope pink; a Mix knob's `s1Accent` is mint, a
Voice switch's violet, the toolbar's the palette's orange; Studio and Arcade name no accent and
keep the default dress; every skin lays every section out where Studio does; the three art views
render; the wordmark is the asset. Rendered all three skins on 2026-09-14 (see STATE.md).

## ADR-049 — The skin is chosen in Settings, in both products

**Date:** 2026-09-14 · **Status:** Accepted (owner's choice) · **Phase 7, P7-5** · Extends ADR-046

**Context.** The owner, after the Neon Ruins skin was installed: "Can we allow skin selection
through the Settings menu within the app? Going through Terminal is not a feasible option."
Since P7 the skin has been View ▸ Skin in the standalone and a `defaults write` everywhere else.
**The plugin has no menu bar of its own**, so in Logic the terminal was the only way — and the
plugin reads its own container's default, so it was a different command from the app's.

**Decision.**

1. **The picker goes in the Settings popover** (`S1SkinPicker`), the one screen both products
   open from their own toolbar. The desktop layout adds it in `dressPresented` when the
   `SegueToMIDI` popover is prepared, into the empty right column under the buffer-size note —
   so no ported file changes, the scene keeps its 600×382, and the classic layout never sees it.
   View ▸ Skin stays in the standalone; both write the same default.
2. **It still applies at the next launch**, as the menu does, and says so under the picker — the
   wording differs by product ("the next time Arcade Ruins opens" / "the next time the host loads
   Arcade Ruins"), because a plugin's interface belongs to the host. Applying a skin live would
   mean tearing down a layout that has moved the storyboard's controls into its sections and
   rebuilding it, which is not worth the risk for a preference; ADR-046 chose next-launch for the
   same reason.

**Consequences.**
- The plugin can be re-skinned from inside a host for the first time.
- `S1SkinChoice.choose` is now called from `SynthOneCore` as well as the app target; it already
  wrote `UserDefaults.standard`, which in the extension is the extension's container.

**Verification.** `SkinTests`: the picker is installed for `SegueToMIDI`, opens on the chosen skin,
writes the default when selected, is not stacked when the popover is dressed twice, and sits
inside the scene's 600×382 in the right column. `DesktopPluginTests`: the hosted layout gets the
same picker with the host wording. Rendered the popover under Neon Ruins on 2026-09-14
(`RENDER_SEGUE=SynthOneCore.Manager:SegueToMIDI RENDER_PRESENTED=1`).

**Superseded in part by ADR-050 the same day**: the picker installs from the Settings controller,
not from the desktop layout, so the classic layout carries it too.

## ADR-050 — The layout is chosen in Settings too, and the test bundle stops writing the owner's

**Date:** 2026-09-14 · **Status:** Accepted (owner's choice) · **Phase 7, P7-6** · Extends ADR-045,
ADR-049; amends ADR-036

**Context.** The owner, looking at the classic interface: "I would still like to access the original
iPad-based interface by changing the setting. Can we include that in the release?" The switch existed
only as View ▸ Classic Layout in the standalone. **The plugin has no menu bar**, so a host could not
reach the classic interface at all — and once in the classic layout, ADR-049's skin picker was not
there either, because the desktop layout installed it. Classic was a one-way trip in a host.

**Decision.**

1. **Layout joins Skin in Settings** (`S1AppearanceSettings`: Desktop | Classic, Studio | Arcade |
   Neon Ruins, a one-line note). Both are supported in the release.
2. **The pickers install from `MIDISettingsViewController.viewDidLoad`**, one line in a ported file
   with a PORT comment, instead of ADR-049's hook in the desktop layout's `dressPresented`. That is
   what makes them appear under the **classic** layout, in both products, so the trip back always
   exists. View ▸ Classic Layout and View ▸ Skin stay, and write the same defaults.
3. **The skin picker dims under Classic**, and its title reads `SKIN · DESKTOP ONLY` — skins dress
   the desktop layout only (ADR-046). The caveat rides in the title so the note stays one line: the
   block sits in a fixed gap under the scene's buffer-size paragraph, and a second line runs into it.
4. **The layout and skin defaults move behind `S1Preferences.store`** (`.standard` in both
   products), which the test bundle points at a scratch suite. `xcodebuild test` runs the tests
   *inside the app*, so `UserDefaults.standard` there is the owner's real domain: the tests written
   for P7-5 chose a layout and a skin, which wrote the owner's settings, and tidied up afterwards,
   which deleted them. ADR-036 isolated `Disk` for exactly this reason and did not cover preferences.

**Consequences.**
- A host can now switch Arcade Ruins between the desktop and classic interfaces, and back.
- `TestStorageIsolation` registers the classic default on the scratch store, not on `.standard`.
- `S1DesktopLayout.dressPresented` loses its settings branch and `skinPicker` property.




## ADR-053 — Notarisation was never broken: the verdicts arrived, late

**Date:** 2026-09-14 · **Status:** Accepted (a correction) · **Phase 5, P5-2** · Corrects the
record around ADR-041

**Context.** On 2026-09-11 and 12, three notarisation submissions sat *In Progress* with no verdict
— the 0.1.0-era app twice and, as a control, a 12 KB `hello` binary signed the same way. The
control's purpose was to separate our packaging from Apple's service, and it hung too, so the
conclusion recorded in STATE.md was that notarisation "hangs on Apple's side", to be taken to
developer support, and that the build should not be re-debugged.

**What actually happened.** All three came back **Accepted**. `xcrun notarytool log` on the first
app submission reads "Ready for distribution", with ticket contents for the app, the framework and
both architectures. The service was slow — hours, not the minutes the `--wait` flag implies — and
the submissions were abandoned before the verdicts landed.

**Decision.** Treat notarisation as working. The release path (`Scripts/release.sh`) is unchanged;
what changes is the expectation: **`notarytool submit --wait` can take hours, and abandoning it
loses nothing** — the submission continues server-side and `notarytool history` and `log` retrieve
the verdict afterwards, by id. Nothing about the packaging needs revisiting.

**Consequences.**
- The "notarisation is blocked, ask Apple" line in STATE.md and the project memory is wrong and is
  removed. No developer-support ticket is needed.
- A release run that appears to hang should be checked with `notarytool history` before anything is
  changed or resubmitted.
- **`Scripts/release.sh` no longer uses `--wait`** (amended the same day, after the 0.3.0 attempt).
  One status poll timed out at the network layer (`NSURLErrorDomain -1001`) after an hour of
  `In Progress`, and `--wait` treats that as fatal: the run ended with the submission still queued
  and nothing stapled. The script now submits with `--no-wait`, writes the id to
  `DerivedDataRelease/release/submission-id`, and polls `notarytool info` for up to four hours,
  forgiving a failed poll. `RESUME_ID=<id> Scripts/release.sh` finishes a submission later without
  rebuilding or re-uploading — the export on disk is what the ticket is for, so rebuilding it would
  change the hashes.

**Verification.** `xcrun notarytool history --keychain-profile ArcadeRuins` on 2026-09-14: three
submissions, all Accepted. `xcrun notarytool log a44b54bd-0c20-415a-bd5e-fbdf77314468` returns
status Accepted, statusSummary "Ready for distribution".

## ADR-052 — Classic is the default layout, and the app has an icon (an Icon Composer bundle)

**Date:** 2026-09-14 · **Status:** Accepted (owner's choice) · **Phase 7, P7-8** · Amends ADR-045,
ADR-029

**Context.** The owner: "Can we make the default layout the classic one. And then let's assign this
icon to it for MacOS", with a synthwave keyboard icon. Two decisions in one.

**Decision.**

1. **A fresh install opens the classic layout.** `S1ClassicLayout` still means "classic", but
   *absent* now means classic too, so `S1Layout.current` asks `object(forKey:)` rather than
   `bool(forKey:)` — only the former tells an unanswered question from an explicit `NO`. A machine
   that has already chosen keeps its choice, in either direction; Settings ▸ Layout (ADR-050) is
   how it is changed.
2. **The app's icon is the owner's artwork, as an `.icon` bundle** (`Sources/SynthOne/ArcadeRuins.icon`),
   with `ASSETCATALOG_COMPILER_APPICON_NAME: ArcadeRuins`. The app shipped with **no icon of any
   kind** before this: nothing named one in its plist, and ADR-029's generated icon went into
   SynthOneCore's iOS set, which a Catalyst app never reads.
3. **Icon Composer, not an icon set — measured, not assumed.** The first pass was a mac-idiom
   `.appiconset`, which built and installed cleanly. Asking macOS what it actually draws
   (`NSWorkspace.icon(forFile:)` on the installed app) showed the owner's rounded square
   composited *inside* the system's shape on a light plate: a rounded square nested in another.
   macOS 26 shapes every app icon, so the artwork must be the thing being shaped, not a picture
   placed in it. With an `.icon` bundle whose one layer is the artwork's body full-bleed, it fills
   the icon. `actool` still emits a legacy `ArcadeRuins.icns` beside it for older systems.
4. **The glass lighting is turned off.** macOS 26 lights an icon's layers like glass, and the
   owner saw what that does to dark artwork: "the icon appears to fade to white in the lower half".
   Measured on the installed app, the keyboard's dark bezel climbed from 27 to 106 down the image.
   `specular: false` and `translucency: {enabled: false}` on the group stop it; the icon keeps its
   shadow and the system's shape. The sheen is right for the layered, light artwork Icon Composer
   is built around and wrong for a finished illustration.
5. **The art is generated, the manifest is written.** `Scripts/branding/generate.py` crops the
   owner's `source/Arcade-Ruins-Icon.png` to its body and writes the bundle's `art.png`; the
   glow outside the body goes, because that is where the system's own shadow now is.
   `icon.json` is checked in by hand. SynthOneCore's unused iOS set is regenerated from the same
   artwork rather than left showing the old code-drawn sunset, so nothing stale ships.

**Consequences.**
- CLAUDE.md's "the icon is code, not a hand-drawn PNG" (ADR-029) no longer holds: like the
  wordmark, the icon is the owner's artwork now. `Scripts/branding/appicon.py` draws nothing that
  ships.
- The AUv3 extension has no icon of its own; hosts that show one fall back to the app's.
- **A release build should be clean.** An incremental build left the previous pass's
  `AppIcon.icns` in the bundle next to `ArcadeRuins.icns`; harmless, since the plist names the
  latter, but it is the kind of thing that ships by accident.

**Verification.** `AudioUnitPackagingTests.testTheAppCarriesItsIcon` pins both plist keys and the
compiled `.icns` in the built app, and `testTheIconBundleAsksForNoGlassLighting` pins the two
settings that keep the artwork flat. `SkinTests.testTheDefaultLayoutIsClassicAndAnExplicitNoChoosesDesktop`
holds the new default and that an explicit `NO` still chooses desktop. 54 tests green. The icon was
checked as macOS resolves it, at 512, 128, 32 and 16 points, not as the source PNG.

## ADR-051 — The Arcade skin is dropped; its drawing kit stays

**Date:** 2026-09-14 · **Status:** Accepted (owner's choice) · **Phase 7, P7-7** · Supersedes
ADR-046's second skin

**Context.** The owner, after Neon Ruins: "Remove the 'Arcade' skin as an option." Arcade (ADR-046)
was the first pass at the synthwave look, and Neon Ruins (ADR-048) is the same idea done properly —
one accent per section, near-black panels, the owner's own wordmark. Two skins of the same genre,
one of them superseded, is a worse menu than one. **Nothing has been released with it**: 0.3.0 is
still in preparation.

**Decision.**

1. **`S1SkinChoice` is `studio | neonRuins`.** `S1ArcadeSkin`, `S1ArcadeHeaderArt`,
   `S1ArcadePanelArt`, the drawn `S1NeonWordmark` and the grunge tile are deleted. The View menu and
   the Settings picker are built from `allCases`, so both follow.
2. **The drawing kit stays, renamed.** `S1ArcadeArt` → `S1SynthwaveArt`: the seeded generator, the
   sun, the mountain ranges, the perspective grid, the starfield, the joystick, the scanlines and
   `S1CRTFrame`. Neon Ruins draws with all of it; it was never Arcade's alone in anything but name.
3. **A stored `S1Skin = arcade` opens Studio**, which is what `S1SkinChoice.chosen` already did with
   any unknown value. No migration, and a test holds that.

**Consequences.**
- The 0.3.0 release notes describe one new skin, not two; `docs/screenshots/arcade-skin.png` is gone
  and the README shows Neon Ruins.
- The code is in the history if the owner ever wants it back: `git show bf8a08a` (Phase 7's commit).

**Verification.** `SkinTests`: the choices are exactly Studio and Neon Ruins, a stored "arcade"
falls back to Studio, Studio still names no section accent and keeps the default dress, both skins
lay every section out in the same place, and the shared kit still draws. 45 tests green; rendered
Neon Ruins and Studio after the removal.

**Verification.** `SkinTests`: the pickers are in the Settings scene with no desktop layout in
sight, open on the layout and skin in use, write both defaults, install once, and sit inside the
scene's 600×382 right column; under Classic the skin picker is disabled and titled
`SKIN · DESKTOP ONLY`, and choosing Desktop lights it again without a relaunch.
`DesktopPluginTests`: the hosted popover carries both, with the host wording, and can choose
Classic. Rendered the popover in both layouts on 2026-09-14. The owner's real defaults were
unchanged by a 58-test run (checked before and after).
