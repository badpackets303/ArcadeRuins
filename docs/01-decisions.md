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

## ADR-054 — The cross-platform plugin is built on JUCE 9, under the free Starter licence

**Date:** 2026-09-16 · **Status:** Accepted (owner's choice) · **Cross-platform plan, X0-1** ·
Plan: <https://claude.ai/artifact/9zr5fP3KeuYMt5kvcmcaDH>

**Context.** The owner asked what a cross-platform VST of Arcade Ruins would take. The survey
(2026-09-15): Soundpipe (7,978 lines of C) and the kernel (≈5,000 lines, Objective-C++ in form)
carry over; ≈3,500 lines of Swift engine logic (tunings, presets, wavetables) must be rewritten in
C++; ≈37,000 lines of UIKit across 11 storyboards must be redrawn. The plan has five phases,
X0–X4, and its first decision is the framework: JUCE (VST3/AU/AAX/standalone from one tree, with a
UI toolkit; AGPLv3 or a commercial EULA), CLAP + clap-wrapper (MIT, no UI toolkit) or iPlug2
(permissive, smaller community). The owner: "I would like to move forward with JUCE", and on the
licence: "I just want simple open source and have no plans to sell this."

**Licence terms as read on 2026-09-16.** JUCE 9.0.2 (released 2026-09-07) is dual-licensed under
the AGPLv3 and the JUCE 9 EULA (dated 2026-06-17). The EULA's tiers: **Starter**, free and
perpetual, all features, revenue up to $20,000 a year; **Indie**, $40 per user per month or $800
once, up to $300,000; **Pro**, $175 per user per month (12-month minimum) or $3,500 once, no limit;
**Educational**, free. Revenue for an individual licensee is everything the product brings in over
the previous 12 months, donations and sponsorship included. The JUCE 9 EULA has no splash-screen
clause (JUCE 8's Personal tier required one) — worth confirming on the JUCE forum before X2 ships,
but the text does not ask for it.

**Decision.** JUCE 9, pinned by tag, under the **Starter** licence.
- Starter over AGPLv3 because it changes nothing about the project's licence story: Arcade Ruins
  stays MIT, `NOTICE.md` gains one entry, and the shipped binaries carry no copyleft. Under
  AGPLv3 every distributed binary becomes an AGPL work whose exact source must be published (the
  public mirror already does that) and every fork inherits AGPL on the combination — more to
  explain, for no gain to a project with no revenue.
- Starter over Indie because there is nothing to sell. If revenue ever appears, Indie's $800
  perpetual licence is the upgrade, and nothing in the code changes.
- CLAP is not ruled out as an extra *format*: `clap-juce-extensions` can add it to the JUCE build.
  That is an X2-1 question, not a framework question.

**Consequences.**
- The plan's task IDs use the prefix `X` (X0–X4) and are permanent, like `P0-1 … P8-n`.
- The Mac app and AUv3 are untouched by this decision. Whether they stay beside the JUCE build
  (which can ship AU too) is X0-2, still the owner's.
- `NOTICE.md` gets a JUCE entry when JUCE source enters the repository (X2-1), naming the EULA
  and the Starter tier; nothing to add before then.
- Section 10.2 of the EULA lets Raw Material Software name licensees in its marketing; the owner
  can opt out by writing to them.

**Verification.** Terms read from <https://juce.com/legal/juce-9-licence/>,
<https://juce.com/get-juce/>, the repository's `LICENSE.md` and its releases page on 2026-09-16.
Re-read them at X2-1 before the first CI build; licences change between major versions.

## ADR-055 — The Catalyst app and AUv3 stay through X2; their fate is decided at the X3 gate

**Date:** 2026-09-16 · **Status:** Accepted (owner's choice; the final question deferred by design) ·
**Cross-platform plan, X0-2** · Follows ADR-054

**Context.** The JUCE build (ADR-054) can ship an AU as well as a VST3, so once it exists the Mac
has two candidate AUs: the Catalyst AUv3 that hosts sessions already know as `aumu`/`ruin`/`BP03`
(permanent since ADR-029), and JUCE's. The plan asked whether to keep both products or retire the
Catalyst pair. The owner: "Keep the Catalyst products through X2 and decide later."

**Decision.**
1. **The Catalyst app and AUv3 are kept, built, tested and released as now through X1 and X2.**
   X1 puts them on the portable C++ engine, so they are how the engine proves itself (goldens exact)
   before any JUCE code runs; they are not a legacy branch during those phases but the reference.
2. **Whether they ship at X4 is decided at the X3 gate**, when the owner has used the JUCE
   interface in Logic and a Windows host. Until then the plan carries both outcomes.
3. **The JUCE build ships no AU publicly before that decision.** X2's public release (0.4.0, the
   generic-interface build) is VST3 and the standalone on all three OSes; the AU format is built and
   validated in CI but not released. An AU's `manufacturer`+`subtype` is permanent the day a host
   saves a session with it (ADR-029), and whichever way X0-2 falls, one of two things is true: the
   JUCE AU inherits `ruin` after the Catalyst AUv3 is retired, or it gets its own subtype for good
   because both stay. Shipping it earlier under either choice would pre-empt the decision.

**Consequences.**
- X0-4 (plugin identity) fixes the VST3 class ID, the JUCE plugin and manufacturer codes and the
  parameter-ID rule now, and leaves the JUCE AU subtype as "`ruin` if the Catalyst AUv3 retires,
  otherwise a new code" — to be filled in at the X3 gate.
- The App Group `8RSH7U3222.com.badpackets303.ArcadeRuins` remains the Catalyst products' preset
  store. X2-9 gives the JUCE build its own per-OS folder; whether the two share on the Mac is
  settled with X0-2, not before.
- Every DSP change during X1–X2 lands once, in the C++ engine, and both product families pick it
  up — the point of the X1 gate.

**Verification.** None to run; recorded in STATE.md "Decisions settled", PORT_PLAN.md §6 and the
plan page.

## ADR-056 — What the JUCE build does not carry in 1.0

**Date:** 2026-09-16 · **Status:** Accepted (owner's choice on the layout; the rest my call) ·
**Cross-platform plan, X0-5** · Follows ADR-054, ADR-055

**Context.** The JUCE interface (X3) is drawn from scratch; nothing from the 11 storyboards
crosses as code. Four things in the Mac products either double that work or belong to the host.

**Decision.** For the JUCE build's 1.0:
1. **Desktop layout only.** The classic iPad-style layout is not rebuilt. It *could* be — it is a
   second complete interface, not a technical impossibility — but X3 is already the largest phase.
   The owner: "I'm fine with that for now." The classic layout stays in the Catalyst products
   (ADR-052 makes it their default) and can be added to the JUCE build later as its own phase.
2. **Preset files: export and import stay.** X3-4 already imports banks the Mac app exported;
   exporting a preset or bank to a file is the same code the other way. Apple's share sheet has no
   equivalent and is not wanted.
3. **MIDI learn is left out of 1.0.** Hosts map hardware controllers to plugin parameters
   themselves, and every parameter is automatable (X2-2), so the plugin needs none. The standalone
   is the only place it would be missed; deferred, not dropped.
4. **The Dev panel is dropped.** It was upstream's internal tuning surface.

**Consequences.**
- X3-1's layout specification measures the desktop layout at 0.3.0 and nothing else.
- Every X3 acceptance criterion that says "as the Mac app does" means the desktop layout.
- `S1Parameter.h` keeps every parameter; nothing here removes one, so presets stay interchangeable
  between the Catalyst products and the JUCE build.

**Verification.** None to run; recorded in STATE.md "Decisions settled", PORT_PLAN.md §6 and the
plan page.

## ADR-057 — Repository shape for the cross-platform build: one repository, an engine directory, JUCE fetched by tag

**Date:** 2026-09-16 · **Status:** Proposed — stands unless the owner objects · **Cross-platform
plan, X0-3** · Follows ADR-054–056

**Context.** Two product families will build from one engine: the Catalyst app and AUv3 through
XcodeGen, and the JUCE VST3/AU/standalone through CMake. The engine's sources today are spread
across `Sources/Soundpipe` (pure C), `Sources/SynthOneCore/DSP/{Kernel, Note State, Sequencer,
Rate}` and `S1Parameter.h` (Objective-C++ until X1), with Apple adapters in `AudioUnitBase` and
`DSP/Audio Unit`. The public mirror is produced by `Scripts/publish-public.sh` with `git archive`,
which carries no submodules. `upstream/` (23 MB) is excluded from the mirror and must stay
read-only. The options were one repository or a separate engine repository consumed as a submodule.

**Decision.** One repository, `SynthOneMac`, mirrored as before.

1. **`Sources/S1Engine/`** — the portable engine: a CMake static library `s1engine`, C++17, no
   Apple headers. X1 moves the kernel, note state, sequencer, rate and `S1Parameter.h` there with
   `git mv` as each file is converted, so history follows the code. It compiles
   `Sources/Soundpipe` in place; Soundpipe does not move. `S1` prefix because the directory is ours
   (ADR-009); the files inside keep their ported names.
2. **`Sources/SynthOneCore/AudioUnitBase` and `DSP/Audio Unit` stay** — they are the Apple
   adapter. After X1-8 `S1AudioUnit` is a thin wrapper over `s1engine`; TAAE stays with it for the
   UI-side messaging the Catalyst products still use.
3. **`Sources/S1Plugin/`** — the JUCE product: `CMakeLists.txt`, the processor, the editor (X3),
   resources. A root `CMakeLists.txt` adds `S1Engine`, `S1Plugin` and the C++ golden harness.
4. **JUCE is fetched, not vendored:** CMake `FetchContent` pinned to the release tag (9.0.2 today),
   hash-checked. No submodule, so `git archive` and the mirror are unaffected and the repository does
   not grow by JUCE's size. `.references/`-style caching (`Scripts/fetch-references.sh`) is the
   precedent.
5. **XcodeGen stays the source of truth for the Xcode targets.** `project.yml` gains the new
   header search path; it does not drive CMake and CMake does not drive it. The Xcode framework
   compiles the engine's sources directly (as it compiles Soundpipe's today) rather than linking
   the CMake library, so `Scripts/build.sh` needs no CMake.
6. **Tests:** the Xcode suite stays where it is; the C++ golden harness (X1-7) lives in
   `Tests/Engine/` and reads the same `Tests/Goldens/*.wav`. CI (X2-1) runs both.

**Why not a separate repository.** One engine, one golden set, one `upstream/` pin, one publish
script, and a DSP fix that lands in one commit for both product families — the point of the X1
gate (ADR-055). A submodule would also need the mirror script rewritten.

**Consequences.**
- CLAUDE.md's layout table gains `Sources/S1Engine/` and `Sources/S1Plugin/` when X1-1 creates them.
- `NOTICE.md` gains JUCE (ADR-054) at X2-1 and, if X2-1 adds CLAP, `clap-juce-extensions`.
- Nothing moves before X1-1. This ADR settles where things go, not when.

## ADR-058 — The JUCE build's identity: `BP03` / `Ruin`, parameter ID = enum name, AU subtype deferred

**Date:** 2026-09-16 · **Status:** Proposed — stands unless the owner objects · **Cross-platform
plan, X0-4** · Follows ADR-029, ADR-055

**Context.** A host stores a plugin's identity in every session that uses it, so the codes are
permanent from the first public release (ADR-029 learned this with `aks1` → `ruin`, free only
because nothing had shipped). JUCE derives every format's identity from two four-character codes:
`PLUGIN_MANUFACTURER_CODE` and `PLUGIN_CODE`. The VST3 class ID is a hash of both; the AU
`manufacturer`/`subtype` pair *is* both. JUCE documents GarageBand's requirement that the plugin
code start with an upper-case letter followed by lower-case ones, and that the manufacturer code
contain an upper-case letter. Parameter IDs are equally permanent: a host's automation lanes and
session state refer to them.

**Decision.**

| | Value | Why |
|---|---|---|
| Manufacturer code | **`BP03`** | The manufacturer the Catalyst AUv3 already ships under (ADR-005, ADR-029); one manufacturer, however many plugins. |
| Plugin code | **`Ruin`** | Upper-case first letter for GarageBand; `ruin` is taken by the Catalyst AUv3 and, in JUCE, one code serves every format. |
| VST3 class ID | derived by JUCE from `BP03`+`Ruin` | Recorded in the X0-4 table once the first build prints it; never changed after 0.4.0. |
| Bundle IDs | `com.badpackets303.ArcadeRuins.vst3` · `.component` · `.app` **not shared** with the Catalyst app: the JUCE standalone is `com.badpackets303.ArcadeRuinsStandalone` | The Catalyst app owns `com.badpackets303.ArcadeRuins`; two apps with one bundle ID confuse Launch Services. |
| Product name in hosts | **Arcade Ruins** | Same instrument. VST3 and AU lists are separate, so 0.4.0 shows no duplicate. |
| Parameter ID | **the `S1Parameter` enum case name**, e.g. `cutoff`, `index1`, `sequencerNoteOn00`; JUCE version hint 1 | Generated from `S1Parameter.h`, never typed; a renamed case fails a test, which is the point. 150 of them. |
| AU subtype for the JUCE AU | **left blank until the X3 gate** | ADR-055. |

**On the deferred AU subtype, what the codes above imply.** Because JUCE uses one plugin code
for every format, the JUCE AU — if it ships — will be `aumu`/`Ruin`/`BP03`: a different plugin
from the Catalyst AUv3 (`ruin`) in every host's eyes. The "inherit `ruin`" branch of ADR-055 is
therefore only open if `PLUGIN_CODE` were `ruin`, which would put the same code on the VST3 (its
class ID would change if switched later, breaking 0.4.0 sessions) and would fail GarageBand's
rule. It is also worth less than it looks: a session saved with the AUv3 stores `S1AudioUnit`'s
`fullState` blob, which the JUCE AU would have to read to restore it. So the X3-gate decision is
really: ship the JUCE AU as a second AU beside the Catalyst one (and retire the Catalyst pair or
not), never as a drop-in replacement for it. Recorded so the gate is not surprised.

**Standalone on macOS.** 0.4.0's macOS package is the VST3 alone; the JUCE standalone ships on
Windows and Linux, where there is no Catalyst app. A macOS JUCE standalone waits on the same
X3-gate decision as the AU.

**Verification.** X0-4's acceptance test: parameter count 150, every ID equal to its enum name,
codes equal to this table. The VST3 class ID is appended to the table by X2-1's first CI build.

---

## ADR-059 — A skin may bring a painted window, and then it places the sections (Cabinet)

**Date:** 2026-09-17 · **Status:** accepted · **Amends:** ADR-046 ("a skin never moves anything")

**Context.** The owner supplied a finished painting of the whole window — `ar-template.png`,
1585×992: an arcade cabinet down the left, a header with the wordmark, a preset display and five
toolbar buttons, and a neon frame with a title for each of the fifteen sections — and asked for a
skin "similar to Neon Ruins" with "the knobs and controls placed over it". The painting's frames
are not where the layout's rows put the sections: the cabinet takes a sixth of the width, the
envelope row is 163 points tall against 220, and Bitcrusher and Master sit lower than their row.
ADR-046 ruled that a skin is palette and decoration, never layout.

**Decision.** A skin may carry an `S1SkinTemplate`: the image, its size, and the rectangle of each
section and toolbar control in the image's own pixels. `S1DesktopLayout` builds exactly as for any
skin — every control moved, bound, remembered for MIDI learn — and then `applyTemplate` lifts the
sections out of their rows and pins each to its rectangle as fractions of the window, hides the
toolbar and the rows, and takes the toolbar's controls to the painted header. **What a section
holds and how it is bound stays the layout's; only where it sits is the skin's.** The other skins
are untouched, and `testEverySkinLaysOutEverySectionInTheSamePlace` still holds for them.

- **The painting is cleaned, not used raw.** The mock had controls painted in (the preset name,
  toggles, the mod-target chips, the pads, the play bar, the Record label). `generate.py`'s
  `clean_template` clones clean texture over them, so nothing painted can disagree with a live
  control. Frames, titles, header art and the Save / Panic / Settings / Presets buttons stay.
  The asset is written at 2× (3170×1984 JPEG, 1.2 MB).
- **Sections are bare** (`dress.bareSections`): no fill, border, glow, texture or visible title;
  the header strip is 30 points to match the painting. The title label stays for VoiceOver.
- **Painted buttons are proxied.** The storyboard's Save, Panic and Settings sit under their
  painted plates at alpha 0 — a popover anchors to its button — and a clear `S1ActionButton` on top
  passes the click on. They cannot simply be made transparent: `SynthButton.isSelected` repaints
  its background grey. Presets is a new way into the browser; the wordmark is About. Record's plate
  is painted empty: the standalone puts its live button and time label there, the plugin an About
  label.
- **The scope runs in the cabinet's screen.** The status bar shares the bottom strip with the
  play bar; the preset card hangs from the display rather than the (hidden) toolbar.
- **Three sections draw a size down** (`isCompact`): OSC 1/2 (36-point knobs, 30-point pickers),
  the envelopes (38-point knobs, a 36-point plot), the LFO block (28-point knobs, name over picker,
  54-point chips) and Voice (switches under the knob). Everything else fits as built.
- **The painting stretches with the window.** The design window is its shape to a part in a
  thousand. An aspect-fitted canvas was tried first and the solver shrank the canvas instead of the
  sections' contents; and `pin` scales from the canvas's trailing and bottom *positions*, which
  equal its size only while it starts at the root's origin.

**Consequences.** A template skin is tied to the section list: a new section needs a frame in the
painting (the test asserts the two key sets are equal). The window above 1440×900 stretches the
art rather than adding room for art. Neon Ruins' palette and accents are reused, not copied.

---

## ADR-060 — Cabinet replaces Neon Ruins

**Date:** 2026-09-17 · **Status:** accepted · **Amends:** ADR-048, ADR-059

**Context.** Hours after 0.4.0 shipped three skins, the owner, having used Cabinet in Logic:
"let's get rid of the neon arcade skin and replace it with the cabinet skin." Cabinet was built on
Neon Ruins — it borrowed its palette, its per-section accents and its dress through a private
instance — so the two were one look with two windows.

**Decision.** `S1SkinChoice` is `studio | cabinet`. `S1NeonRuinsSkin` became `S1CabinetSkin`: the
six neons, the accents map (ADR-048) and the palette are Cabinet's own now. What only Neon Ruins
drew is deleted — the header sunset, the backdrop, the grime texture, the palm, the lit wordmark
and its generated asset `s1_wordmark_neon` — and `S1NeonRuinsArt.swift` is `S1CabinetArt.swift`,
holding the preset card's art. **A stored `neonRuins` opens Cabinet**, not Studio: 0.3.0 and 0.4.0
offered it, so someone has chosen it, and its successor is the honest answer (`arcade`, never
released, still falls to Studio). Tag `v0.4.0` has everything removed.

**Consequences.** One synthwave skin to keep. The "every skin lays out every section in the same
place" test now has no skin to compare with Studio; it stays for the next one.

---

## ADR-061, ADR-062 — Cabinet extras

**Date:** 2026-09-17 · **Status:** accepted

Two decisions about the Cabinet skin that are kept out of the published tree at the owner's word
(2026-09-17). They are in `docs/private/cabinet-extras.md` in the working repository, which
`Scripts/publish-public.sh` leaves out. Neither touches the DSP, a parameter, a preset or a binding.

---

## ADR-063 — In the plugin, a read sees the interface's own write while it is on its way

**Date:** 2026-09-17 · **Status:** accepted · **Builds on:** ADR-022, ADR-030, ADR-031

**Context.** `HostMIDIInterfaceTests.testAHostModWheelMovesTheWheel` had been failing on `main`
since some point after 0.1.0 (the full suite went unrun through Phases 6–8): a host's CC 1 = 127
left the wheel at 0.0316, not 1. The owner's physical wheel worked in Logic, so it was put down
to the test. It was half that.

**What happens.** The wheel's callback writes the cutoff (360 Hz at the top, under the cutoff
routing). In the plugin a write goes through the parameter tree (so the host can record it) and,
once render resources are allocated, reaches the kernel **at the next render**. Until then the
kernel holds the old value — here the init preset's 20 kHz. Upstream's interface reads the kernel
straight back in several places, as it could when it wrote the kernel directly: the wheel tells the
Cutoff knob `getSynthParameter(.cutoff)`; the XY pads, settling into place 0.2 s after the panel
loads, ask where the cutoff is and report it with no control. A 20 kHz report with no control puts
the wheel at 20 kHz's position — 0.0316 (ADR-030's inverse) — and the knob at 20 kHz. **Nothing
then corrects them**: `reconcileWhenQuiet` reports only a kernel value that differs from what was
written, and by then the kernel holds 360 exactly.

In the test the main thread is also the render thread, so the CC and the pads' completion ran in
one run-loop turn with no render between: certain failure. In a host the render thread runs every
few milliseconds, so the window is a block wide and the wheel is almost always right — which is
what the owner saw. But the race is real, and the wheel's own read-back is inside it every time:
**the Cutoff knob trailed the mod wheel by one step**, and kept the last step's error.

**Decision.** `S1HostedSynth.getSynthParameter` answers with the interface's own write while that
write is still on its way: inside the echo window, and only while the kernel still holds exactly
what it held when the write was made (`before`, recorded with the write). The moment the kernel
holds anything else — our value landed, or a host's — the kernel answers. That is not a cache,
which `testParametersRoundTripThroughTheDSP` rightly forbids and which the first cut of this fix
(return the written value for the whole window) was; that test caught it.

The test now renders while it waits, because a host never stops, and also asserts the kernel's
cutoff and the Cutoff knob. **Revert-and-fail:** with the rendering wait alone it still failed,
identically; it passes only with the read fix. Full suite 333/333, the first all-green run since
before Phase 6.

**Not established:** which commit turned the test red. It needs the pads' completion and the CC
in one turn, so anything that moved panel loading relative to the test's send could have.

---

## ADR-064 — Cabinet is the default skin

**Date:** 2026-09-17 · **Status:** accepted · **Amends:** ADR-046

The owner: "the Cabinet skin should now be the default." `S1SkinChoice.default` is `.cabinet`;
an absent or unknown `S1Skin` opens it, and an explicit `studio` — anyone who chose it through
0.5.0 — stays Studio. The skin still dresses only the desktop layout, and **the default layout is
still classic** (ADR-052), so a fresh install sees Cabinet the first time Desktop is chosen. The
test suite **sets** Studio in its scratch preferences, because the desktop tests were written under
it — set, not registered as the classic layout is: a registered default is process-wide and would
answer for the empty suite on which `SkinTests` checks the real default.


## ADR-065 — The cross-platform plan is rebased on 0.5.0, and X1-1 lands the portable build

**Date:** 2026-09-17 · **Status:** Accepted · **Cross-platform plan, X1-1** · Amends the plan
behind ADR-054–058; follows ADR-059, ADR-060, ADR-064

**Context.** The plan was written against 0.3.0 on 2026-09-16. A day later the product is 0.5.0:
the Cabinet skin (ADR-059) replaced Neon Ruins (ADR-060) and is the default (ADR-064), and 0.4.0
and 0.5.0 are released. The owner: "I have uploaded a newer version of the code… Proceed with
that. Same strategy."

**What changed for the plan, measured.** `git diff ac79ef3..4dd7e79` touches nothing in
`Sources/Soundpipe`, `Sources/SynthOneCore/AudioUnitBase`, `Sources/S1Support` or `Tests/Goldens`,
and in `Sources/SynthOneCore/DSP` only `S1SynthControlling.swift` (ADR-063, the plugin's
read-after-write — an AUv3 concern with no JUCE counterpart). So X1 and X2 stand as written. What
moves is X3's reference and one version number:

1. **X3 is drawn from 0.5.0: the desktop layout under the Cabinet skin, with Studio as the
   second skin.** Neon Ruins no longer exists. Cabinet is not only a palette: it carries an
   `S1SkinTemplate` — the owner's painting (`ar-template`, 1585×992, shipped at 2×) and a rectangle
   per section and toolbar control — and places the sections over it (ADR-059). For the JUCE
   interface that is *easier* than the row layout, not harder: X3-1's layout specification for
   Cabinet is that rectangle table, already data, and the painting is an image asset. X3-6 becomes
   "Studio and Cabinet, Cabinet the default". The Cabinet extras (ADR-061, ADR-062) are scoped
   when X3 starts, from `docs/private/cabinet-extras.md`.
2. **X2's public release is not "0.4.0".** That number shipped. It takes the next free minor
   version when it is ready.

**X1-1 as built.** A root `CMakeLists.txt`; `Sources/S1Engine/` with two targets — `soundpipe`,
which compiles the twenty modules of `Sources/Soundpipe` in place with the same `NO_LIBSNDFILE=1`
the Xcode target uses, and `s1engine` (C++17, warnings as errors, `-ffp-contract=off` /
`/fp:precise`, never fast-math); `Tests/Engine/` with behaviour tests and the Apple-header guard;
`.github/workflows/engine.yml` building and testing on macOS, Linux and Windows. XcodeGen and
`Scripts/build.sh` are untouched: no Xcode target's sources include the new directories.

The behaviour tests measure rather than link (CLAUDE.md): `sp_osc` at 440 Hz plays 439.5–440.5 Hz
and peaks at its amplitude; `sp_moogladder` at a 500 Hz cutoff passes 100 Hz (−2.9 dB) and stops
8 kHz (−97 dB); `sp_revsc` stays finite and its tail decays; and **`sp_rand` from seed 0 yields
12345, 1406932606, 654583775, 1449466924 and `sp_noise`'s first sample is bit-exact** — the claim
that noise renders identically on every OS, now a test on every OS.

**Verification.** Locally (Apple clang 21, arm64): 2/2 CTest tests, 12/12 checks. Revert check: a
header containing `#include <AudioToolbox/AudioToolbox.h>` dropped into `Sources/S1Engine/src`
fails `NoAppleHeaders`; removed, it passes. GCC and MSVC: the `engine` workflow. Its first run
passed on macOS and Linux and **failed on Windows** — `revsc.c(75): error C2036: 'void *': unknown
size`, arithmetic on `void *` being a GNU extension. Fixed as a `PORT FIX` (`char *`; the same
address under GCC and Clang) and recorded in `Sources/Soundpipe/VENDORING.md`. Second run
(35284384744): green on all three, the bit-exact `sp_noise` check included under MSVC.
`GoldenRenderTests` 4/4 in the Xcode build after the change, so the reverb renders as before. Found on the way: CMake cannot link against the Command Line Tools SDK
on this machine (`tapi error: malformed file`, `arm64e.x1-macos`); `SDKROOT` must point at Xcode's
SDK. Recorded in `Sources/S1Engine/PORTING.md` and CLAUDE.md.

## ADR-066 — The kernel's held keys and outbound messages are plain C++ (X1-2)

**Date:** 2026-09-17 · **Status:** Accepted · **Cross-platform plan, X1-2** · Follows ADR-065

**Context.** The kernel is C++ in form but reached for Objective-C in two places: the held keys
(`NSMutableArray<NSValue *>` mirrored into TAAE's `AEArray` for the render thread) and its seven
messages to the interface (`AEMessageQueuePerformSelectorOnMainThread` to `audioUnit.messageRelay`,
the P4-5 fix). Neither exists off Apple platforms; both had to go before the kernel can move to
`Sources/S1Engine` (ADR-057).

**Decision.**
1. **`S1HeldNotes`**: a fixed array of 128 `NoteNumber`, most recent first — the order the
   `NSMutableArray` kept (insert at index 0; a re-press is removed and re-inserted at the front) —
   with a working copy for the one writer and a published copy readers take a `snapshot()` of
   through a seqlock, the pattern ADR-028's waveform ring uses. Same threading as upstream: the
   writer is the main thread in the standalone and the render thread in the plugin; readers are
   either. **No allocation on any path.** Upstream allocated an `NSValue` and rebuilt the
   `AEArray` (a `malloc` per note in its mapping block) on whichever thread called `startNote` —
   in the plugin, the render thread, every note.
2. **`S1KernelListener`**: a pure-virtual interface with the seven messages (tempo, dependent
   parameter, beat counter, playing notes, held notes, host control, host keys). The kernel holds a
   pointer and null-checks it. `S1AudioUnit.mm` implements it as `S1AudioUnitKernelListener`,
   making exactly the queue-to-relay calls the kernel made, so the products behave as before.
   The JUCE build implements it its own way (X2).
3. `__weak S1AudioUnit *audioUnit` leaves the kernel; the listener was its only use.
4. `S1Sequencer::process` takes a `const S1HeldNoteList &`. One snapshot per render cycle, where
   `AEArray` fetched a token per macro — the count and the enumeration now describe the same
   moment, which they did not before.

**Not changed.** The kernel still says `AUParameterAddress`, includes `S1AudioUnit.h` for the
message structs, and is compiled as `.mm`; `S1HostMIDI.hpp` still includes `AudioToolbox`. X1-3.
`S1HeldNotes` and `S1KernelListener` include `S1AudioUnit.h` for the same reason and so cannot join
the CMake tree yet; their own behaviour test arrives with X1-3, in `Tests/Engine`.

**Verification.** Xcode: 74 tests over `GoldenRenderTests`, `HostMIDITests`, `HostedSynthTests`,
`S1AudioUnitRenderTests`, `PluginRenderTests`, `PluginTransportTests`, `PluginStateTests`,
`AudioUnitBaseTests`, `ModWheelEchoTests`, `S1MIDITests` — 0 failures. **`GoldenRenderTests` now
prints how many goldens reproduced bit-exactly: 20 of 20.** The random-MIDI parity test
(`testRandomMIDIMatchesTheStandalone`) is the note-order check: plugin and standalone agree note
for note with the new list. Signed build installed, `auval` passed (`AU VALIDATION SUCCEEDED`).
A real-time-safety pass with `-fsanitize=realtime` waits for X1-7's harness under Clang in CI.

## ADR-067 — The kernel is plain C++ in `Sources/S1Engine`, compiled by Xcode and by CMake (X1-3)

**Date:** 2026-09-17 · **Status:** Accepted · **Cross-platform plan, X1-3** · Follows ADR-057,
ADR-065, ADR-066

**Context.** After X1-2 the kernel had no Objective-C left in its logic but still wore Apple's
clothes: `AUParameterAddress`/`AUValue`/`AUAudioFrameCount` in its interface, `AUMIDIEvent` in
`handleMIDIEvent` and `S1HostMIDI`, `AudioUnitParameterUnit` in the 150-row parameter table,
AudioKit's `AKSoundpipeKernel`/`DSPKernel`/`AKOutputBuffered` as bases, the message structs in
`S1AudioUnit.h`, `AK_ENUM` from `AKInterop.h`, and `.mm` extensions. None of that compiles under
GCC or MSVC.

**Decision.**
1. **The kernel moves to `Sources/S1Engine`** — `Kernel/`, `Note State/`, `Sequencer/`, `Rate/`
   and `S1Parameter.h` — with `git mv`, so history follows the files, and as `.cpp`. **Both
   builds compile the same files**: `project.yml` adds the directory to `SynthOneCore` and the
   engine's search paths; `CMakeLists.txt` lists the sources. Neither build system drives the other.
2. **`S1EngineTypes.h`** is the engine's vocabulary: `S1ParameterAddress`, `S1ParameterValue`,
   `S1FrameCount` (the AudioToolbox widths), `S1MIDIEvent` (length and three bytes),
   `S1ParameterUnit` (AudioToolbox's values), `S1Event`, and the message structs from
   `S1AudioUnit.h`, unchanged. Plain C; public in the framework; includes `S1Parameter.h` by bare
   name because the two are siblings in both trees (ADR-012's flattened `Headers/`).
3. **`S1Parameter.h` is self-contained.** `S1_PARAMETER_ENUM` is `enum_extensibility(open)` under
   Clang — the open enum Swift has always imported — and an int-backed enum elsewhere. `AKInterop.h`
   is imported by the umbrella on its own now.
4. **`S1KernelBase.hpp`** keeps what the kernel used of AudioKit's bases (`sp_data`, channels,
   sample rate, `init`, the three helpers) plus `S1OutputBuffered`: two float pointers the host
   adapter sets. The helpers are guarded by name against AudioKit's copies, which stay for the
   test-tone kernel.
5. **`S1KernelAUAdapter`** (`S1AudioUnit.mm`) is a `DSPKernel` + `AKOutputBuffered` over the engine
   kernel: Apple's event splitter, unchanged, forwarding to `process`/`startRamp`/`handleMIDIEvent`.
   **The AU's render path is what it was**, which the 20 exact goldens confirm.
6. **`S1DSPKernel::processWithEvents(frames, S1Event[], count)`** is the same split over `S1Event`
   for hosts that speak it (JUCE, X2-3): render to the next offset, apply everything at it, carry
   on; an event past the end applies after the last frame. The plan's "both hosts cut the buffer in
   the same places" criterion has its engine half; X2-3 measures the equivalence.

**Compilers as reviewers.** Clang passed everything; the first GCC and MSVC runs did not, and each
failure was a real portability fact hidden by libc++: `nil`, `BOOL`, `UInt32`, transitive
`<memory>`/`<functional>`/`<cmath>`/`<algorithm>`/`<cfloat>`, a missing include guard, `M_PI` on
MSVC. Each fix is a marked `PORT` line and is tabled in `Sources/S1Engine/PORTING.md`. Three CI
rounds; the third is green on all three OSes.

**Consequences.**
- `Tests/Engine` gains `HeldNotesTests` (order, re-press, ceiling, no torn snapshot under a
  concurrent reader) and `KernelEventTests` (the splitter; a note from a MIDI event at sample 128
  of 256 — silent before, sounding after). The kernel cannot render without its 52 wavetables, so
  the test fills them with sines; `NoAppleHeaders` now strips comments before matching.
- `Sources/SynthOneCore/DSP/` keeps `Audio Unit/` (the Apple adapter), the Swift model and TAAE;
  its PORTING.md points here.
- What is still Apple-only and belongs to X1-4 … X1-6: tunings (Swift), the preset model (Swift),
  the wavetable loader (Swift). `S1HostMIDI` is in the engine already.

**Verification.** Xcode: 94 tests over the DSP, host-MIDI, hosted-synth, plugin render/transport/
state/scope/preset, Soundpipe and core suites, 0 failures; `GoldenRenderTests`: **20 of 20 bit-
exact**. CMake: 4 tests, 25 checks, green on macOS/Clang, Linux/GCC and Windows/MSVC (run
35292166584, third of three). Signed build installed, `auval` passed.

## ADR-068 — The tuning table, the Scala parser and the factory tunings in the engine (X1-4)

**Date:** 2026-09-17 · **Status:** Accepted · **Cross-platform plan, X1-4** · Follows ADR-067

**Context.** The instrument plays through a 128-entry tuning table the Swift `Tunings` model
computes — `AKTuningTable` (S1Support/Microtonality) turns a master set of octave-reduced ratios
into frequencies around middle C — and pushes into the kernel one note at a time. Presets carry a
`tuningMasterSet`; the Tunings panel offers 194 factory tunings, most as literal master sets and
the rest built at launch by Wilson's MOS, CPS, harmonic-series and North Indian builders
(≈1,100 lines of Swift across `AKTuningTable+*` and `Tunings+Math`); users import `.scl` files.
None of it exists in C++.

**Decision.**
1. **`S1TuningTable`** is `AKTuningTable`'s table, ported line for line: octave reduction and
   sort into the master set, the middle-C reference, the Nyquist clamp, `equalTemperament`,
   `masterSetInCents`. Not ported: the ETNN / delta-12ET dictionaries, which nothing in the product
   reads.
2. **`S1Scala`** is the parser the product actually uses — `frequencies2(fromScalaString:)` in
   `Tunings+TuneUp.swift`, AudioKit's parser as Synth One carries it — quirks kept: a cents line
   with trailing text is skipped rather than parsed, `1/1` and `2/1` are dropped, a count of 0
   is rejected. `std::regex` stands in for `NSRegularExpression`.
3. **The factory tunings are data, not builders.** `S1FactoryTunings.cpp` holds the 194 tunings
   (name, bank, master set as the Swift builder returned it, 17 significant digits) and is
   **generated from the Swift** by `TuningFixtureTests` in write mode
   (`Scripts/write-tuning-fixtures.sh`). The same test in check mode — part of the normal suite —
   regenerates it in memory and fails if the file on disk differs, so the Swift list remains the
   single source and cannot drift from the engine unnoticed. The builders are not ported because
   nothing in the product builds a tuning at run time; they only ever produced this list.
4. **The fixture is the proof.** The same test writes `Tests/Engine/Fixtures/factory-tunings.txt`:
   every factory tuning's 128 frequencies from the Swift table, plus six Scala cases (cents,
   ratios, whole numbers, CRLF, comments, the quirks, two rejections). `TuningTableTests` in CMake
   reads it and compares.

**Found on the way: `pow(2, x)` is not `pow(2, x)`.** LLVM rewrites a call to `pow` with a
literal base of 2 into `exp2(x)`, which differs from libm's `pow` in the last bit for some
exponents — 1100 cents came out `1.8877486253633871` against the Swift's `1.8877486253633868`.
The Swift, being the reference, gets libm's `pow`. `s1::powerOfTwo` loads the base through a
`volatile` so the rewrite cannot apply, and every compiler computes what the Swift computes.

**Consequences.**
- The engine can turn a preset's `tuningMasterSet` or a `.scl` file into the kernel's table
  without Swift (X1-5 will call it; X2 the JUCE build).
- After editing `Tunings+DefaultTunings.swift` or the table code, run
  `Scripts/write-tuning-fixtures.sh` and commit both generated files; the suite says so when it
  is needed.
- The CI workflow runs `ctest --verbose` now, so the measured counts are in the log.

**Verification.** `TuningTableTests` on macOS: **194 of 194 tables bit-exact**, every note within
1e-9 relative (measured 0), the generated list equal to the fixture in order, six Scala cases
equal; the 12-ET defaults (A4 = 440, middle C = 261.6255653006) and the rejections. Revert checks:
a changed entry in `S1FactoryTunings.cpp` fails the Swift check-mode test and passes when
restored. `engine` workflow run 35293220508 green on macOS, Linux and Windows.

## ADR-069 — The preset model in the engine, transcribed from the Swift and proved against it (X1-5)

**Date:** 2026-09-17 · **Status:** Accepted · **Cross-platform plan, X1-5** · Follows ADR-068

**Context.** A preset is a JSON dictionary of 114 keys that `Preset.swift` decodes with
`as? … ?? default` bridging (a missing or mistyped key takes the DSP's default for that
parameter), `Preset+Synth.apply` writes to the synth in a fixed order — order matters, because
`arpRate` and `tempoSyncToArpRate` re-drive four other parameters — and
`PresetDataManager.saveValuesToPreset` reads back with a handful of renames (`delayToggled` ←
`delayOn`, `widen` stored as 0 or 1 …). Upstream's comment on the field list: "You MUST match
these property names with the dictionary key used by init or you will forever lose the original
preset." 695 factory presets across 13 banks depend on all of it.

**Decision.**
1. **`s1::Preset`** (`Sources/S1Engine/Presets/`) is a transcription, not a rewrite: a script
   read `Preset.swift`, `Preset+Synth.swift` and `saveValuesToPreset` and emitted the field list
   with its defaults, `fromJSON` with the same fallback per key, `toJSON`, `apply` in upstream's
   order, and `capture`. The bridging rules are spelled out as functions (`asDouble`, `asInt` —
   an integer or an integral float, never 3.5 —, `asBool` — a bool or exactly 0/1 —, arrays whose
   every element bridges, sequencer arrays of exactly 16).
2. **JSON for Modern C++ 3.11.3** (MIT) is vendored as the single header under
   `Sources/S1Engine/third_party/nlohmann/`, unmodified, with its licence; `NOTICE.md` names it.
   The Catalyst products keep Foundation's JSON.
3. **The proof is a fixture the Swift wrote.** `PresetFixtureTests` (Xcode) applies every factory
   preset to one synth in bank order and records the decoded fields and the 150 values after
   `apply`, plus the key sets `JSONEncoder` writes with and without a tuning; in check mode it
   fails when the file is stale. `PresetTests` (CMake) decodes the same bank files with
   `s1::Preset`, applies them to the C++ kernel in the same order, and compares.

**Found on the way: `abs(float)` is not `fabs` everywhere.** The first Linux run reported 2,513
mismatching values, all in the tempo-synced parameters. `S1Rate.hpp`'s three nearest-rate
searches said `abs(difference)` on floats: libc++ and MSVC find a float overload, libstdc++
finds C's `abs(int)` and truncates the difference to a whole number, so the wrong rate wins.
`std::fabs` now, marked `PORT FIX` — the Mac has always computed `fabs`, so nothing changes there
(goldens 20 of 20 exact after the edit).

**Consequences.**
- The engine reads a bank, decodes a preset, applies it and writes it back without Swift. X1-7's
  harness can load the golden presets from the bank files; X2-5 can save and restore state as
  preset JSON the Mac app also reads.
- After editing `Preset.swift`, `Preset+Synth.swift`, `saveValuesToPreset` or a factory bank:
  `Scripts/write-preset-fixtures.sh`, commit the fixture. The suite says when.
- The transcription script is not kept; the fixture is the contract. A field added to the Swift
  fails `PresetTests`'s key check until `S1Preset` carries it too.

**Verification.** `PresetTests` on macOS, Linux and Windows (run green on all three after the
fabs fix): 695 of 695 presets decode to the Swift's fields; **695 of 695 apply to the same 150
values, bit-exact**; every preset survives `toJSON → fromJSON`; the writer's key set equals
`JSONEncoder`'s (112 keys, 114 with a tuning); the bridging rules on a sparse, mistyped preset.
Revert check: an off-by-one in `apply` shows as 608 mismatches. Xcode after the edit: 23 tests
green across the golden, fixture, hosted-synth and plugin-state suites, 20 of 20 goldens exact.

---

## ADR-070 — The wavetable loader in the engine, and a kernel that frees what it allocates (X1-6)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X1-6** · Follows ADR-069

**Context.** The kernel cannot render a frame without its 52 oscillator tables (4 waveforms × 13
band-limited versions, 4,096 samples each) and the 13 band frequencies that choose between them:
`S1NoteState::init` hands `ft_array` to `sp_oscmorph2d_init`, and a missing table is a crash, not
a silence. `S1Wavetables.swift` decodes them from `AKTable`'s Codable JSON in the framework bundle
and pushes them in through `setBandlimitFrequency`, `setupWaveform` and `setWaveform`. It was the
last Swift the engine needed before it could make a sound on its own. The plan's acceptance:
table floats equal exactly; tables survive ten engine create/destroy cycles.

**Decision.**
1. **`s1::Wavetables`** (`Sources/S1Engine/Wavetables/`) ports the Swift loader: `load(Source)`
   reads `bandlimitedWaveforms` (the 52 names, in kernel order), each named table and
   `bandlimitedWaveformFrequencies`; `apply(kernel)` makes the same three calls in the same order.
   A `Source` is a callback from a resource name to its JSON text, so the loader does not care
   where the data lives: `loadFromDirectory` indexes every `*.json` under a directory by file stem
   (the repository keeps per-waveform folders, the Mac bundle is flat), and X2 can hand it data
   linked into the plugin. One `Wavetables` value serves any number of kernels; `apply` copies.
2. **Stricter than the Swift.** A short index, a table that is not 4,096 samples or a frequency
   list that is not 13 throws a `std::runtime_error` naming the resource. The Swift checks only
   the index; the rest would have reached the kernel's fixed arrays.
3. **The JSON stays where it is** (`Sources/SynthOneCore/DSP/BandlimitedWavetables`, 5.5 MB of
   text for 852 KB of floats) and stays the only copy. How the plugin carries it — the JSON, or a
   binary blob generated from it — is X2's packaging decision; the `Source` callback leaves it open.
4. **The proof is a fixture the Swift wrote**, as for tunings and presets.
   `WavetableFixtureTests` records, per table, its name, size, an FNV-1a 64 over the samples' bit
   patterns and the first eight samples, and the 13 frequencies whole
   (`Tests/Engine/Fixtures/wavetables.txt`, 9 KB; `Scripts/write-wavetable-fixtures.sh`; check mode
   fails when stale). `WavetableTests` (CMake) loads the same JSON with the C++ loader and compares.

**Found on the way: the kernel never freed anything.** The ten-cycle test was run under macOS's
`leaks`: **79.6 MB leaked over eleven kernels.** Three separate causes, all upstream's:
- `~S1DSPKernel` was `= default`. A kernel destroyed while initialised kept everything `init()`
  had created — 7.2 MB, most of it the four delay lines. The AU calls `destroy()` from
  `deallocateRenderResources`, so the Mac products only paid this when a host freed a plugin it
  had not deallocated.
- `init()` replaces the seven note-state objects, and their 84 Soundpipe modules went with them
  unfreed — on every `allocateRenderResources`.
- Nothing freed the oscillator tables (852 KB). `destroy()` rightly leaves them alone — they are
  loaded once and outlive the allocate/deallocate cycle — so nobody did.

One synth for the life of an app hides all three. A host that opens and closes plugins all day
does not. `PORT FIX`: the destructor calls `destroy()` if initialised, frees the note states, then
the tables (last: the note states borrow the pointers); `init()` frees the note states' modules
where it replaces the objects; a second `setupWaveform` of one table frees the first. No memory
is freed earlier than the object holding it was already going away, so no pointer that was valid
before is dangling now. **0 leaks** after. Nothing on the render path changed.

**Consequences.**
- With kernel, tunings, presets and wavetables in C++, the engine can load a factory preset and
  play it with no Swift and no Apple code. X1-7's golden harness is now only a harness.
- After editing `S1Wavetables.swift`, `AKTable`'s coding or a table JSON:
  `Scripts/write-wavetable-fixtures.sh`, commit the fixture. The suite says when.
- `KernelEventTests` keeps its sine tables: it tests event timing, not timbre.
- `leaks --atExit -- <test>` is a cheap local check for any engine test that makes kernels
  (it needs no special build). CI does not run it; Linux ASan/LSan belongs with X1-7's harness,
  alongside the deferred RTSan pass.

**Verification.** `WavetableTests`: 13 of 13 frequencies and **52 of 52 tables (212,992 floats)
bit-exact** against the Swift loader; ten kernels made and destroyed from one `Wavetables` each
hold 52 exact tables — after a `destroy()`/`init()` cycle too — and render the same samples from
a real A3; a second `apply` leaves the tables exact; an in-memory `Source` loads; four malformed
inputs are refused by name. Revert check: scaling the decoded value by 1.0000001 shows as 0 of 52.
Xcode: 336 tests green, **20 of 20 goldens bit-exact** after the kernel edits. Signed build
installed 2026-09-18; `auval` (which opens, initialises and uninitialises the plugin repeatedly)
passed. CI run 35344520512: green on macOS, Linux and Windows, 52 of 52 on each.

---

## ADR-071 — The golden harness: twenty goldens through the engine alone, exact where the arithmetic is the same, measured where it is not (X1-7)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X1-7** · Follows ADR-070 · Amends ADR-065 (the `-ffp-contract` setting)

**Context.** X1's claim is that `Sources/S1Engine` *is* Synth One's sound, with no Swift,
Objective-C or Apple framework under it. The Mac products' proof of their sound is
`GoldenRenderTests`: twenty factory presets rendered through `AKSynthOne`, `S1AudioUnit` and
`AVAudioEngine`, compared with `Tests/Goldens/*.wav`. The plan asked for the same twenty through
the engine alone, on three OSes, within 1e-4 per sample and 1e-5 relative RMS, exact expected on
macOS.

**Decision.**
1. **`Tests/Engine/GoldenHarness.cpp`** renders by `GoldenRenderTests`' recipe (44.1 kHz,
   512-frame blocks, preset applied, 0.75 s to settle, A3, E4 at +0.4 s, both released at 1.0 s,
   1.5 s captured; notes through `startNote`/`stopNote` between blocks, as `AKSynthOne.play`
   reaches them) from a new engine per render, prepared step for step as the Mac product
   prepares one: construct, `s1::Wavetables::apply`, the parameter read-and-write-back
   `AKSynthOne.init` does, `prepareToRender`, `s1::Preset::apply` from the bank JSON.
   `Tests/Engine/WavFile.hpp` reads the goldens (RIFF chunks walked: AVAudioFile pads with `JUNK`
   and `FLLR`) and can write renders (`--write-renders`); `--list-differences` shows where.
2. **`S1DSPKernel::prepareToRender(channels, sampleRate)`** is what `S1AudioUnit
   allocateRenderResources` did inline — save parameters and tuning table, `init`, `reset`,
   restore, NPO, wavetable increments — moved statement for statement, and the AU calls it. One
   way to prepare the kernel, for the AU, the harness and JUCE's `prepareToPlay`.
3. **`-ffp-contract=on`, spelled out, for the engine and Soundpipe** (`S1_FP_CONTRACT`, a cache
   variable so `off` can be studied). X1-1 chose `off` on the theory that it keeps builds alike.
   The harness measured the opposite: `on` is Clang's default, so it is what the Xcode build —
   the shipped product and the goldens — has always had, and on arm64 it means fused
   multiply-add. With `off` this Mac reproduced **3 of 20** goldens; with `on`, **20 of 20, bit
   for bit** — through no AVAudioEngine, at `-O2` against goldens written at `-O0`.
4. **Two criteria, because there are two situations.**
   - *The arithmetic that wrote the goldens* (Apple Silicon): **bit-exact or fail**
     (`--require-exact`, which CMake passes on Apple arm64).
   - *Any other arithmetic* (x86-64 has no FMA in its baseline; glibc and the UCRT are other
     libms): the difference's RMS at least **50 dB under the golden's** (relative RMS ≤ 3.16e-3)
     **and** no more than **1 sample in 200** further than 0.001 from the golden.
5. **The criterion is itself tested.** Three self-checks render the twenty with one small
   deliberate fault and pass only if the tolerance criterion *rejects* them: the filter 1% sharp
   (19 of 20 rejected), the tuning 1 cent sharp (20 of 20), the second note one block late (7 of
   20 — the arpeggiated and sequenced presets only hold the note; its timing is not in their sound).
6. **A sanitizer job** (`engine.yml`, Clang on Linux): every engine test under ASan with LSan
   (fatal) and UBSan (reported). The harness alone makes and destroys some eighty engines.

**Why the plan's tolerance was wrong.** Measured on Linux and Windows (identical to each other
to three figures): 17 presets differ from the goldens by a relative RMS of 1e-7 to 5e-4 — rounding
carried through filters, delay and reverb, 66 dB or more under the signal. Three had one-sample
differences of 0.01 to 0.0255 with nothing either side. Reproduced on this Mac with
`-DS1_FP_CONTRACT=off` and read sample by sample: **the bit-crusher's sample-and-hold**. It is a
float counter compared with `<=` (`S1DSPKernel+process.cpp`), its step comes from
`exp2(log2(rate))`, and one bit of rounding now and then makes it take its new sample one sample
earlier or later: one sample off by as much as neighbouring samples differ, 101 of 133,120 at
worst. Both versions are the algorithm working; neither is more right. A per-sample maximum
cannot tell that from a fault, so the criterion is an RMS plus a bound on how many samples may
stray. 1e-5 relative RMS was never measured against anything: `GoldenRenderTests` has only ever run
on arm64, where the answer is 0. (The Mac products' x86_64 slice has the same no-FMA arithmetic
as the Linux job; it could not be run here — no Rosetta — but there is no reason to expect it to
differ from what Linux measured.)

**What this does not catch off the Mac:** a fault smaller than −50 dB — a gain wrong by 0.3%.
The exact criterion on Apple Silicon catches any such thing in the shared source; a fault that
exists *only* in another compiler's arithmetic and is that small is, by construction, inaudible.

**Consequences.**
- The answer to "will it sound the same?" is now measured: on Apple Silicon the engine is the
  AUv3's sound sample for sample; on Intel/AMD under Linux and Windows it is the same sound to
  within −63 dB, with the bit-crusher's steps landing a sample apart here and there.
- A golden rewritten for the Xcode test is rewritten for the harness (same files); the list of
  twenty lives in both (`Tests/Goldens/README.md`).
- **RTSan is deferred again, with a reason:** `-fsanitize=realtime` needs Clang 20 and
  `[[clang::nonblocking]]` on the render entry point; neither Xcode's Clang nor the CI images
  have it, and the realtime boundary that matters is JUCE's `processBlock` with our own
  `S1KernelListener` behind it. It belongs to X2 (with the harness's renderer as the driver).
- X1-8 is smaller than planned: the Mac app and AUv3 have run on `Sources/S1Engine` since X1-3,
  and the AU now prepares the kernel through the engine's own call. What is left is the owner's
  gate.

**Verification.** CI run 35347661117, four jobs green. macOS (arm64): **20 of 20 bit-exact**.
Linux (GCC) and Windows (MSVC): **20 of 20 within tolerance**, worst relative RMS 6.93e-4
(−63 dB), worst outlier count 101 of 133,120, 0 exact. Sanitizers: no ASan, LSan or UBSan report
in 11 tests. Determinism: two renders of one preset from two new engines identical on every OS.
Self-checks as in (5), same counts on every OS. Locally: `leaks` on the harness 0; 336 Xcode
tests green with the AU on `prepareToRender`, `GoldenRenderTests` 20 of 20 exact; signed build
installed 2026-09-18, `auval` passed.

---

## ADR-072 — The JUCE project: fetched JUCE, VST3 + Standalone, a processor held to the bare engine sample for sample (X2-1)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-1** · Follows ADR-054, ADR-055,
ADR-057, ADR-058, ADR-070, ADR-071 · Amends ADR-058 (one bundle ID; the VST3 class ID recorded)

**Context.** X1 left a portable engine proved against the goldens and a reference host for it
(`GoldenHarness`'s `makeEngine`). X2-1 is the first JUCE build: a project, the formats and identity
the X0 decisions fixed, a processor that makes sound with Init, and CI on three OSes. ADR-054
asked for the licence to be read again before the first CI build.

**The licence, re-read 2026-09-18** at tag 9.0.2 (`LICENSE.md`, `JUCE.spdx.json`) and
<https://juce.com/legal/juce-9-licence/> (EULA dated 2026-06-17): unchanged from ADR-054. AGPLv3
or the JUCE 9 EULA; Starter is free up to $20,000 a year; **no splash-screen, logo or attribution
clause** in any tier. Two clauses shape the build: §1.17, the framework may not be distributed on
its own — so JUCE is fetched, never vendored, and the public mirror never carries it (ADR-057 had
this right); §2.3, the framework must not be made subject to a copyleft licence — Arcade Ruins is
MIT, which asks nothing of JUCE. The bundled VST 3 SDK is 3.8.0, **MIT** (no Steinberg agreement to
sign); ASIO and AAX are not enabled. `NOTICE.md` has the entry.

**Decision.**
1. **`Sources/S1Plugin/`, behind `-DS1_BUILD_PLUGIN=ON` (default OFF).** The `engine` workflow
   stays a one-minute build; a new `plugin` workflow turns the option on. JUCE by `FetchContent`,
   pinned to 9.0.2's **commit** (`7278278…`), not the tag name: a tag can be moved.
2. **`juce_add_plugin`: VST3 + Standalone, no AU** (ADR-055). `BP03` / `Ruin`, product "Arcade
   Ruins", company "BadPackets" (the AUv3's manufacturer name), version from the root `project()`.
   **VST3 class ID `ABCDEF019182FAEB425030335275696E`** (controller
   `ABCDEF011234ABCD425030335275696E`) — JUCE's hash of the two codes, read from the built
   `moduleinfo.json`; permanent from the first release. **Amending ADR-058:** JUCE has one
   `BUNDLE_ID` per plugin, not one per format, so the `.vst3` carries
   `com.badpackets303.ArcadeRuinsStandalone` as well. It clashes with nothing (the Catalyst app
   and appex own `com.badpackets303.ArcadeRuins…`), and a VST3's bundle ID identifies it to no host.
3. **`S1PluginProcessor` hosts the engine in `makeEngine`'s order**: kernel constructed,
   `s1::Wavetables::apply`, every parameter read and written back (constructor);
   `prepareToRender` then `s1::Preset().apply` — Init — in `prepareToPlay`; `setOutput` +
   `processWithEvents` in `processBlock`. Stereo out, no input, no mono layout (the engine has
   none). MIDI of 1–3 bytes becomes `S1Event`s at its sample position in a fixed
   `std::array<S1Event, 512>`; a block with more is rendered in pieces, so nothing is dropped and
   nothing allocates. A note-on with velocity 0 is turned into a note-off (the kernel's plain MIDI
   path would start a silent voice; `S1HostMIDI` is X2-4). The host's generic editor. No
   parameters (X2-2), state (X2-5), tempo (X2-6) or denormal handling (X2-7, which must be
   *measured* against the goldens, not switched on in passing).
4. **Wavetables: the 54 JSON files as JUCE binary data**, read through
   `s1::Wavetables::load(Source)`, decoded once per process in a `juce::SharedResourcePointer`.
   Measured: 31 ms on this Mac, 5.5 MB in each binary. The 852 KB float blob ADR-070 mentioned
   needs a generator, an endianness rule and its own proof; 31 ms once per process does not pay
   for that. Revisit at X4 if installer size matters.
5. **The acceptance test is equality, not "is not silent".** `Tests/Plugin/PluginRenderTests`
   links the plugin's shared-code library and renders GoldenHarness's recipe twice — through
   `processBlock` with MIDI, tables from the binary; and through a bare kernel in the same blocks
   cut at the same notes, tables from the repository. Same compiler and machine, so the two must
   be **equal sample for sample on every OS**: block sizes 512, 64, 1024, 441, 37 and 1, notes at
   the start of their block and 129 samples into it.

**Found on the way: the engine's render depends on where `process()` calls are cut.** The first
version of the test compared every block size with the 512-block render and failed: 94–1,024
samples differ, by at most 0.0019 (Init peaks at 0.177). Upstream frees a released voice at the
top of a `process()` call once its envelope is under `S1_RELEASE_AMPLITUDE_THRESHOLD` (0.01), not
on the sample it gets there, so the end of a release tail is up to a block longer or shorter. It
is upstream's behaviour, it is in the goldens (written at 512), and the Mac AU has always had it
with whatever block size a host used. X2-1 does not change it; the test measures it (limit 5e-3,
"a tail's end, nothing more") and holds the *wrapper* to exactness with equal cuts. **The X2 gate —
goldens at odd block sizes — must reckon with it**: bit-exactness on Apple Silicon can only be
asked at 512-frame blocks. Against ADR-071's tolerance it is small for Init — at 1,024-frame
blocks 206 of 266,240 samples are over 0.001 (1 in 1,290; the limit is 1 in 200), at 64, 37 and 1
it is 68 — but a preset with many voices releasing, or a long release, has not been measured.
Either the gate's criterion is shown to cover tail ends on all twenty, or the voice is freed on
its sample (a `PORT FIX` that would rewrite goldens); that is the gate's decision, with this
measurement in hand.

**Consequences.**
- `Sources/S1Plugin/README.md` carries the rules: JUCE fetched not vendored, hosting order,
  nothing allocating on the audio thread, no fast-math/LTO flags from JUCE, permanent identity.
- The engine's headers are SYSTEM includes for the plugin target: JUCE's recommended warnings
  are for the plugin's code, the ported kernel keeps upstream's (ADR-065).
- CI artefacts (VST3 + Standalone per OS, 7 days) exist on the private repository for trying a
  build; they are unsigned and nothing is released from them (X4).
- macOS builds are arm64-only and take the SDK's deployment target for now; universal binaries
  and a deployment target are X4's.

**Verification.** Locally (arm64, AppleClang 21): 12 of 12 CTest tests; `PluginRender` — tables
52 of 52 equal, 12 of 12 processor-versus-engine renders with 0 differing samples, Init peak
0.177; the standalone launches and stays up; VST3 bundle and `moduleinfo.json` inspected.
CI: `plugin` run 35350332737 green on Clang/macOS, GCC/Linux and MSVC/Windows — on each, 12 of 12
tests, 52 of 52 tables equal, **12 of 12 processor-versus-engine renders with 0 differing
samples**, the block-cut measurement identical to the Mac's (1,024 samples, 0.00162833, at
1,024-frame blocks); tables decode in 34 / 64 / 99 ms. Its first run (35350012387) failed on
Linux as it should have: JUCE 9 needs `libxi-dev` (XInput2), which JUCE 8's list did not have.
`engine` run 35350012098 green, unchanged. The Mac products are untouched: no Xcode source
changed, nothing reinstalled.

---

## ADR-073 — The 150 parameters in JUCE: generated IDs, the kernel's ranges, values in as events, the engine's own changes reported back (X2-2)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-2** · Follows ADR-022, ADR-058,
ADR-072 · Contains a `PORT FIX` to `S1DSPKernel::prepareToRender`

**Context.** ADR-058 fixed a parameter's ID as the name of its `S1Parameter` enum case,
"generated, never typed". The Catalyst AUv3 does something else: its identifiers are the kernel
table's `presetKey`s, and X2-2's first act was to compare the two — 19 of 150 differ
(`filterAttack` for `filterAttackDuration`, the fifteen compressor keys are phrases with spaces,
and `compressorMasterMakeupGain` appears **twice**, once for `compressorReverbWetMakeupGain`). So
the IDs cannot be read from the kernel at run time; they have to come from the header. The
kernel's table does own the ranges and defaults. It owns no tapers and few names: the tapers are
the classic panels' (`knob.taper = 2`), the names and readouts the desktop layout's (P6-2).

**Decision.**
1. **IDs: CMake reads `S1Parameter.h`** and writes `S1_PARAMETER_NAME(name, number)` lines to
   `generated/S1ParameterNames.inc` (150 or the configure fails). `S1ParameterCatalog.cpp` expands
   them into the ID table and `static_assert`s every number against the enum. Version hint 1.
   **`Tests/Plugin/Fixtures/parameter-ids.txt` freezes index, ID and hint**; the test demands that
   every frozen line is still there unchanged, and allows new lines after them
   (`PluginParameterTests <fixture> --write-fixture` adds them). Revert-checked: one renamed line fails it.
2. **`S1ParameterCatalog` (no JUCE)**: per parameter — ID, name, kind (continuous / integer /
   toggle / choice), readout format, taper, choice names, and minimum/default/maximum **read from a
   kernel**. X3's interface will read the same list. Names are the desktop layout's with the
   section in front ("Filter Cutoff", "Amp Env Attack", "Seq Step 7 Pitch"), because a host shows one
   flat list; readouts are `S1ValueFormat`'s (kHz/Hz, s/ms, %, st, dB) plus note values for the
   rates under tempo sync and for the sequencer's step length, from `S1Rate`. Stepped parameters
   name their steps from the kernel's code (LFO waveforms and routing, filter type, arp direction).
   `frequencyA4` is stepped because the kernel truncates it to whole Hz — found by the test.
   Presentation may change in any release; identity may not.
3. **`S1HostParameter` holds the plain value**, the number the kernel takes, in an atomic; hosts
   get 0…1 through a `NormalisableRange` skewed to the Mac knob's taper. Flat list, enum order, no
   groups (VST3 units can be added later without touching identity).
4. **The kernel is only touched from `processBlock`** (and from `prepareToPlay`, when nothing
   renders). Each block, every parameter whose value differs from what the kernel was last given
   becomes an `S1EventKind_Parameter` event at the block's first sample — **the sync switch and
   the tempo first**, so a rate written in the same block is read under the sync written with it
   (the kernel quantises a rate as it arrives). JUCE gives a plugin one value per parameter per
   block; sample-accurate automation and ramps are X2-3.
5. **The engine's own changes (ADR-022) are read back after the render** for the five parameters
   the kernel rewrites — `lfo1Rate`, `lfo2Rate`, `autoPanFrequency`, `delayTime` (re-driven by
   tempo and sync; quantised under sync) and `arpSeqTempoMultiplier` (always a note value). Where
   the kernel's value differs, the host parameter takes it by compare-and-swap (a host write that
   landed meanwhile wins and goes out next block) and its listeners are told **from the audio
   thread**. In JUCE's VST3 wrapper that path ends in `outputParameterChanges` — the processor
   *reporting* a value — where the same call from the message thread is `performEdit`, which a
   host in write mode records. It is the path JUCE itself uses for incoming automation. No gesture
   is ever begun. This is the AUv3's `dependentParameters` + `implementorValueProvider` in VST3's terms.
6. **The parameters start as Init**: `s1::Preset().apply` in the constructor, then every host
   parameter takes the kernel's value. `prepareToPlay` first writes whatever the host has set
   since (a session's whole state) straight into the kernel, then prepares it. Init is no longer
   re-applied; the parameters are the state.
7. **`getTailLengthSeconds`** is computed: release + delay repeats down to −60 dB + an estimate of
   `sp_revsc`'s RT60, capped at 60 s. An estimate, and said to be one.

**`PORT FIX`: `prepareToRender` carries what each parameter was *set* to.** Upstream's allocate
sequence saved `parameters`, re-initialised, and restored. For the 45 *smoothed* parameters
that array is the glide's current position, which only reaches a newly set value as frames
render. Set a value, allocate with no render in between — a host restoring a session — and every
smoothed parameter (cutoff, the envelopes, the mix) came back as the *old* value while the stepped
ones kept the new. It was invisible in the render test (plugin and reference lost Init
identically) and was caught by `PluginParameterTests` reading the kernel: cutoff written as 777
came back 20,000. Now `getSynthParameter` — the target for a smoothed parameter — is what is
saved. Where nothing is gliding the two arrays are equal, which is every path the goldens and
the Mac tests take. **The Catalyst AUv3 has had this since upstream**; whether Logic ever hit it
depends on whether it restores state before or after allocating, and the interface re-applying
its preset would have hidden it. **Not changed:** after any `init` every smoothed parameter glides
up from 0 for about a second (upstream hands `sp_port_init` the value where it takes a half-time;
`sp_port` starts at 0). That is ADR-013's sweep, it is in the goldens, and it stays.

**Consequences.**
- `PluginRenderTests`' reference engine now applies Init *before* `prepareToRender`, as the plugin
  does; still 12 of 12 renders equal sample for sample.
- The AUv3's parameter identifiers and the JUCE IDs differ for 19 parameters. Nothing shares them
  (different plugins, ADR-058), but anything that ever maps one to the other must go through
  `S1Parameter`, never through the strings.
- `sendValueChangedMessageToListeners` takes JUCE's listener lock on the audio thread — as JUCE's
  own wrappers do for every automated parameter. RTSan (carried into X2) will name it; the answer
  is this paragraph.
- Still to come: X2-3 ramps and sample accuracy; X2-5 state (the preset JSON, not an APVTS);
  X2-6 host tempo driving `arpRate`, which will make `arpRate` engine-driven too.

**Verification.** `PluginParameterTests`, 51 checks: 150 parameters in enum order, 150 distinct
IDs, hint 1, the frozen list unchanged; ranges and defaults equal to a kernel's; host and kernel
equal at birth; a value written before `prepareToPlay` in the kernel after it and after a second
one at 48 kHz; each of the other 149 parameters written and found in the kernel one block later;
under sync 3.1 Hz becomes 3 Hz ("1/4 triplet" at 120 BPM), the host told once with no gesture; a
tempo of 90 re-drives the delay time, reported once, and the same 3 Hz now reads "1/8 note" (the
engine re-quantises by frequency, not by name); eight idle blocks move nothing; sync off and a
rate in one block keeps the rate; readouts, typed text, the cutoff taper, step counts, 0…1 round
trips, the tail. Revert-checked: without the `prepareToRender` fix the cutoff reads 20,000 and the
engine's own `KernelEvents` check fails too; a renamed line in the frozen list fails identity.
`PluginRenderTests` 12 of 12 exact. CI: `plugin` run 35354695631 and `engine` run 35354695677
green on macOS, Linux and Windows (13 tests each in `plugin`). The run before it failed on Windows
in `HeldNotes` — X1-2's thread test, whose writer finished before the reader thread was ever
scheduled; it now writes until the reader has read a thousand snapshots. Mac products, because
engine code changed: 336 Xcode tests green, `GoldenRenderTests` 20 of 20 bit-exact, signed build
installed 2026-09-18, `auval` passed.

---

## ADR-074 — The plugin's render does not depend on the host's buffer size: released voices are freed every frame, as a kernel option; ramps are the engine's own smoothing (X2-3)

**Date:** 2026-09-18 · **Status:** Accepted for the JUCE plugin · **the same switch for the Mac products is
the owner's, at the X2 gate** · **Cross-platform plan, X2-3** · Follows ADR-071, ADR-072, ADR-073 · Settles
ADR-072's open finding

**Context.** X2-3's acceptance asks for the goldens at other block sizes. ADR-072 had found that
the engine's render depends on where `process()` calls are cut, and read it as "the end of a
release tail, a block early or late". X2-3 measured it properly: `GoldenHarness --block-size N`
renders the twenty golden presets in N-frame blocks with every note on the sample the goldens have
it on. **Upstream's path, against the goldens (Apple Silicon, where 512 is bit-exact):**

| Block size | bit-exact | within ADR-071's tolerance | worst relative RMS |
|---|---|---|---|
| 512 (the goldens') | 20 | 20 | 0 |
| 64 | 9 | 16 | 0.73 |
| 480 | 8 | 16 | 0.89 |
| 1,024 | 16 | 17 | 0.77 |
| 37 | 8 | 16 | 0.65 |
| 2,048 | 11 | 14 | 0.92 |

A relative RMS of 0.7–0.9 is not a tail's end; it is a different waveform. The cause is one line
of upstream's and one of its consequences. `process()` frees released voices (envelope under
0.01) **once, at the top of the call**. `turnOnKey` gives a note that is *already sounding* its old
voice back — oscillator phase, filter state and all — and gives any other note a fresh one. An
arpeggio with a short release retriggers the same key again and again, and whether the last
instance has been freed yet depends on where the host's buffer boundary fell. Missing Time
(release 24 ms, arp on) parts from its golden 11,904 samples in and never returns; SubSonic Pad,
Let's Play and Forth of Bass follow. It is two legitimate performances of the same patch, not a
fault anyone would name by ear — but it means an offline bounce (large buffers) and the live
session it came from (small ones) are different audio, and that no tolerance can make "goldens at
odd block sizes" pass. The Catalyst AUv3 has always behaved this way in every host.

**Decision.**
1. **`S1DSPKernel::freeReleasedVoicesEveryFrame`** (default `false`). Off: upstream's path,
   untouched — the Mac products and the goldens. On: the same check (`freeReleasedVoices()`, the
   code moved into a function, not changed) runs at the top of every frame instead. **The JUCE
   plugin sets it.** It is not a new behaviour: it is *exactly what upstream's path renders in
   one-frame buffers*, made independent of the host.
2. **Proved, not argued** — `GoldenHarness --check-block-independence`, a CTest on every OS: with
   the option on, each of the twenty presets renders the **same samples** in blocks of 512, 64,
   480, 1,024 and 37, and they **equal upstream's path rendered in 1-frame blocks**; and the option
   is needed (upstream's path at 64 differs from itself at 512 for 11 of 20).
3. **What the plugin's sound is, then, against the goldens:** at any block size, 8 of 20 bit-exact,
   16 of 20 within ADR-071's tolerance, and the four arpeggiated presets above outside it (relative
   RMS 0.0076, 0.030, 0.22, 0.79) — the same four, by much the same amounts, that upstream's own
   path misses at a 64-frame buffer. The goldens remain the proof of the *engine* (option off, 512: 20
   of 20 exact, enforced). The plugin's proof is the chain: goldens → upstream's path → the same
   path in 1-frame blocks → the option, at any block size → `processBlock` (ADR-072's equality).
4. **Ramps are the engine's smoothing; `startRamp` still ignores its duration.** The 45 parameters
   where a step would be heard (cutoff, resonance, levels, envelope times, mixes, detune…) already
   glide through `sp_port` with `portamentoHalfTime` (0.1 s). Measured through `processBlock`: a
   500 → 5,000 Hz cutoff change moves the filter by at most 0.7073 Hz in any sample — the
   smoothing's own bound, 4,500 × (1 − 0.5^(1/4,410)) — rising every sample. The continuous
   parameters that do not glide (the two LFO rates, the tempo, the step length, fifteen compressor
   settings, the delay input's two) take their value at the block's first sample; none of them is
   in the signal path as a gain or a filter coefficient. A second, linear ramp on top of `sp_port`
   would change how every automated parameter moves compared with the Mac products, for nothing
   audible.
5. **One value per parameter per block** is what JUCE hands a plugin (its VST3 wrapper keeps the
   last point of a sample-accurate automation queue). At 2,048 frames that is 46 ms of
   quantisation ahead of a 100 ms smoothing. Accepted and recorded; MIDI *is* sample-accurate.
6. **48 and 96 kHz.** There are no goldens there and resampling them would prove the resampler. The
   checks are: `processBlock` equals the bare engine sample for sample at both rates (blocks of
   512, 480, 37) — which also shows a kernel constructed at 44.1 kHz and prepared at another rate
   equals one constructed at that rate; Init's A3 measures 219.67 Hz at all three rates (autocorrelation);
   the level agrees within 0.16 dB.

**For the owner, at the X2 gate — not blocking anything.** The Mac app and AUv3 could set the same
option. Logic users would then get the same audio from a bounce as from playback, at every buffer
size. The price is that 12 of the 20 goldens would be rewritten (8 stay bit-identical), four of them
audibly-different-on-paper arpeggios — different in the way the AUv3 already differs from itself
between two buffer sizes. Until that is decided the Mac products are byte-for-byte what they were:
336 tests, 20 of 20 goldens exact.

**Found on the way.** `sp_port` never quite arrives: at 500 Hz its last step falls under a float's
resolution and the glide stops 0.135 Hz short. Upstream's, in the goldens, left alone.

**Verification.** `GoldensBlockIndependence`: 20 of 20 same at five block sizes, 20 of 20 equal to
upstream's path in 1-frame blocks, upstream's path moves for 11 of 20. `Goldens` (option off):
20 of 20 bit-exact on Apple Silicon. `PluginRenderTests`: 12 of 12 processor-versus-engine renders
exact, the engine identical across six block sizes (was: up to 1,024 samples of Init differing),
6 more exact at 48/96 kHz, pitch and level as above, a note-on at sample 300 of 512 first sounds at
sample 300, the cutoff ramp bound, an unsmoothed rate in use from the block's first sample. 14 of 14
CTest tests locally. Mac products: 336 Xcode tests green, `GoldenRenderTests` 20 of 20 bit-exact,
signed build installed 2026-09-18, `auval` passed.
CI: `engine` run 35356759979 (three OSes and the sanitizer job) and `plugin` run 35356759865 (three OSes)
green; `GoldensBlockIndependence` reads 20 of 20 / 20 of 20 / 11 of 20 on Linux and Windows as on the Mac.

---

## ADR-075 — Host MIDI in the JUCE plugin goes through `S1HostMIDI`; the mod wheel runs on the render thread; the router is held to the standalone's notes on every OS (X2-4)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-4** · Follows ADR-031, ADR-032,
ADR-063, ADR-073

**Context.** Since X2-1 the processor fed raw MIDI to the kernel with the router off: upstream's
handler, which plays note on and off and CC 123 and nothing else. The Catalyst AUv3 routes host
MIDI through `S1HostMIDI` (ADR-031), the render-thread port of the standalone's main-thread
chain — channel and omni, octave shift, white-keys-only, hold, the sustain pedal, mono's return to
the highest held key, pitch bend — proved equal to that chain by `HostMIDIParityTests`, which
runs only where Swift and UIKit do. What the router calls "the interface's" — the mod wheel,
program change, bank select, MIDI learn — it forwards to a listener, and on the Mac the wheel is
an on-screen control whose callback writes a parameter chosen by the preset's `modWheelRouting`.

**Decision.**
1. **The processor turns the router on** (`hostMIDI.enabled`), calls `beginRenderCycle` at the top
   of every `processBlock` as the AUv3's render block does, and is the kernel's `S1KernelListener`.
   Its own velocity-0 conversion is gone: the router has the rule. The router's settings keep the
   standalone's out-of-the-box values (omni, no shift, no hold) until an interface exists (X3-8).
2. **The mod wheel runs where the controller arrives** — `S1ModWheel.hpp`, no JUCE:
   `value = cc / 127`; routing 0 → cutoff `3 × scaleRangeLog2(1 − value, 120…7600)` (360 Hz at the
   top, the range's maximum at the bottom), 1 and 2 → `setDependentParameter` on an LFO rate. Each
   line names the Swift it mirrors. A trip to a message thread and back is not available: an
   offline bounce renders faster than any other thread answers (ADR-031's own reason), and there
   is no interface until X3. `modWheelRouting` is preset state, not one of the 150 parameters; the
   processor holds it (`setModWheelRouting`) for X2-5 to save and X2-9 to load.
3. **`pitchbend` and `cutoff` join the parameters read back after every render** (ADR-073's
   `engineDriven`), because MIDI now moves them in the engine. The host's parameter follows the
   wheel and is told as a report, no gesture — what the AUv3's `implementorValueProvider` gives a
   host that asks. Program change and bank select wait for the preset library (X2-9); MIDI learn is
   out of scope (ADR-056).
4. **Parity, carried to the OSes Swift does not run on.** `HostMIDIParityTests`' scenarios became
   data (7 scripted, 8 seeded random of 150 events), and a new test there writes down **what the
   standalone played**, event by event — `Tests/Engine/Fixtures/host-midi.txt`, with the 128-entry
   white-keys map — in check mode in the normal suite, written by
   `Scripts/write-host-midi-fixtures.sh` (the pattern of ADR-068–070). `Tests/Engine/HostMIDITests.cpp`
   replays the file's MIDI through the router alone, hosted as the plugin hosts it (settings in
   the atomics, `beginRenderCycle`, MIDI as `S1Event`s), and requires the file's notes. It is an
   *engine* test: the router is engine code and runs in the fast `engine` workflow.
5. **`Tests/Plugin/PluginMIDITests`** is the plugin around it: one key plays once at its velocity;
   velocity 0 releases; omni; the pedal holds a released key (still sounding a second later) and
   lifting it stops it; mono switched by a *host parameter* returns to the highest held key; pitch
   bend is **heard** (A3 measured 219.9 Hz, 11.9997 semitones up with a 12-semitone range) and
   reported once with no gesture; the mod wheel sets 360 Hz / the maximum, is reported, leaves the
   host able to write the cutoff afterwards, and follows the routing; CC 123.

**Found on the way.**
- **Init's bend range is 0.** Upstream's `Preset()` and the Starter Bank's Init both say so, as do
  230 of the 695 factory presets (386 have ±12): the pitch wheel does nothing on Init, by the
  preset's choice. Faithful, so kept; the test sets a range before it bends.
- The mono return re-presses the held key **with the released key's note-off velocity** — often 0
  (`+62:0` in the fixture). The standalone does it, so the router does.
- A mono or hold switch is noticed at the next block's `beginRenderCycle`, so *when* the held keys
  are released depends on the buffer size. It is a person's switch, quantised like every parameter
  (ADR-074 §5), not a performance's timing; recorded, not changed.
- `make` kept a stale engine object twice after a revert-check restored a source file within the
  same second as the mutated build. Rebuild the library target explicitly after restoring.

**Verification.** `HostMIDI` (engine): 15 scenarios, **1,237 events, the router plays the
standalone's notes for every one**; 128 of 128 white keys; pitch wheel, CC 123, a note shifted out
of range, router off. Revert-checked both ways: mono returning to the *lowest* held key fails 104
events; one changed fixture line fails the Swift check-mode test. `PluginMIDI`: 21 checks.
`PluginRender` still 12 + 6 exact — the router makes the same `startNote`/`stopNote` calls the
reference engine makes directly. 16 of 16 CTest tests locally; 337 Xcode tests green (one new),
goldens 20 of 20 exact. No product source of the Mac app or AUv3 changed, so nothing was reinstalled.
CI: `engine` run 35358886298 (three OSes and the sanitizer job) and `plugin` run 35358886322 (three OSes)
green; on Linux and Windows the router plays the standalone's notes for all 1,237 events, as on the Mac.

---

## ADR-076 — Plugin state: JSON text holding the 150 parameters by ID, the engine's preset, the tuning table and the router's settings; built off the audio thread, delivered on it (X2-5)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-5** · Follows ADR-069, ADR-073, ADR-075;
the AUv3's counterpart is P4-4's `fullState`

**Context.** A host saves a plugin's state into its session file — while audio runs, from a
thread of its choosing — and hands it back on another machine, possibly another OS, possibly to
a later or an earlier build. The AUv3's `fullState` is the parameter tree plus 128 tuning
frequencies and the notes-per-octave (P4-4). The engine has a preset model that reads and writes
the Mac app's own JSON (ADR-069).

**Decision.**
1. **The format is JSON text**, UTF-8: `{"format": "ArcadeRuins.state", "version": 1, "plugin": …,
   "parameters", "preset", "tuning", "midi"}` (`S1PluginState.hpp`, no JUCE). No byte order, no
   struct layout, no float format: a `float` goes out as the `double` it equals and comes back
   the same `float`. 12 KB.
2. **`parameters` — every parameter by its permanent ID (ADR-073) — is the authority for the
   sound.** Unknown IDs are ignored and missing ones keep their value, so states move between
   builds in both directions; values are clamped to the kernel's range and stepped ones land on a
   step; a value of the wrong type is as good as missing. **`pitchbend` is never written and always
   comes back centred**: it is a wheel's position, and a session reopened with the wheel at rest
   must not play bent (the host parameter follows the wheel since ADR-075, so it *would* be saved).
3. **`preset` is the engine's preset JSON** with the parameters captured into its fields
   (`s1::Preset::capture` gained a form that reads from a function instead of a kernel; the
   sequencer rows, which upstream's capture leaves to the interface, are filled in here) — so a
   session holds a preset the Mac app can read, with its identity: name, bank, uid, author, text,
   `tuningName`, `tuningMasterSet`, `modWheelRouting`. The processor keeps that identity under a lock
   the audio thread never takes.
4. **When `parameters` does not name every parameter the sound comes from `preset`, through a
   scratch kernel.** A bank file's preset wrapped as a state, or a state from a build with fewer
   parameters. It cannot be done field by field, because **upstream's apply order decides some
   values**: `delayTime` is written early, while the *previous* tempo-sync setting still stands, and
   is quantised to a note value by it before the preset's own switch arrives — Cool Beans Epic Mega
   Pad's 0.599 s delay plays as 0.667 s on a new Mac engine, sync off or not. So the preset is
   applied, in upstream's order, to an `S1DSPKernel` made for the purpose — new, as the goldens'
   kernels are — and the 150 values read back. Never the rendering kernel. X2-9's preset loading
   will go the same way. (Upstream's result depends on the preset loaded *before*; from a new
   kernel is the only reproducible choice, and the goldens'.)
5. **`tuning` is the table itself**, 128 frequencies and the notes-per-octave, as `fullState` has
   it; all 128 or none. `frequencyA4` is a parameter and is saved, but it is **inert in the engine
   upstream** — nothing reads it; on the Mac only the Tunings code writes it — so the table is
   what makes the pitch, and X3-5 owns rebuilding it.
6. **Threads.** `getStateInformation` reads the *host parameters'* atomics and the processor's own
   copies (tuning, routing, identity, the router's atomics) — never the kernel, which is
   rendering. `setStateInformation` writes the host parameters' plain values exactly (no trip
   through 0…1) and notifies listeners — inside the wrapper's `setState` a VST3 host is not sent an
   edit (JUCE's `inSetState`) — stores the tuning in the processor's copy and raises two flags;
   **`deliverPendingToKernel`, at the top of `processBlock` and of `prepareToPlay`, writes the
   table and owes the kernel `Preset::apply`'s `resetSequencer`.** The parameters follow by
   ADR-073's path, sync switch and tempo first. The processor's copies are the authority, as the
   host parameters are: a state read back before a single block has run is already right.
7. **What is not a state changes nothing**: empty, garbage, another plugin's chunk, an array, half
   a file. Better the sound that was there than half of another.

**Found on the way.** `s1::Preset()` — Swift's `Preset()` — has compressor ratios of 0 and the
like, which the kernel clamps on arrival; Init is what the *kernel* makes of it, which is why the
plugin reads its starting values back from the kernel (ADR-073) rather than from the struct. One
factory preset has `arpInterval` 8.04; a host's stepped parameter makes it 8.

**Consequences.**
- `Tests/Plugin/Fixtures/state-v1.json` is a released format's witness: **never rewritten**. A
  version 2 adds `state-v2.json` and keeps reading this one.
- `currentState()` / `applyState()` are the processor's state API for X2-9 (preset library) and
  X3 — but a preset chosen by a person in an editor is an *edit*, and must tell the host so
  (gestures), which `applyState` from inside `setStateInformation` rightly does not.
- The router's settings ride in the state now; `preset.isHoldMode` is still nobody's (X2-9/X3-8).

**Verification.** `PluginState`, 25 checks: a recipe that moves 126 parameters, a 19-EDO table at
A4 = 432, UTF-8 name, routing and router settings, saved in one instance and reopened in another
at another sample rate — 149 parameters equal to the bit, the wheel centred, tuning, identity,
routing, settings; saved again before any audio: the same text byte for byte; after
`prepareToPlay` and a block the kernel holds all 150 and A4 = 432 Hz, 19 steps up = 864 Hz, and
the text is unchanged; a state loaded between blocks is not in the kernel until the next block;
five kinds of non-state change nothing; a "version 7" state with unknown keys, an unknown
parameter, 1.4 for a stepped one, a string for a number, 99 for a volume; **18 factory presets from
three banks, each as a state's `preset`: the plugin's kernel equals the engine's own apply**; the
committed version-1 state loads to the recipe's 150 values, saves as the same JSON, and this build
writes the same JSON for the recipe. `PluginStateFixtureTests` (Swift): the Mac app's dictionary
initialiser and `JSONDecoder` both read the fixture's preset — name, uid, tuning, routing, five
values, 48 sequencer cells. 17 of 17 CTest tests; 338 Xcode tests green, goldens 20 of 20
bit-exact; signed build installed 2026-09-18, `auval` passed (the engine's preset file changed).
CI: `plugin` run 35362783123 green on macOS, Linux and Windows — the Mac-written state loads to the
recipe's values and is written back as the same JSON on each. **Its first run (35361346383) failed
on Linux and Windows, and the fault was the test's:** the recipe computed `min + range × fraction`
in `float`, one fused multiply-add on Apple Silicon and two operations elsewhere, so 13 of its
"expected" values existed only on a Mac (ADR-071's lesson, met again). The file itself had loaded
and re-saved identically. The recipe's numbers are exact decimals now, and the fixture — not yet
merged — was written again from them; from here on it is fixed.

---

## ADR-077 — Host tempo and transport in the JUCE plugin: the play head into the kernel's own two handlers; the host's tempo wins over the tempo parameter; a transport stop is an all-notes-off (X2-6)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-6** · Follows ADR-025
(the AUv3's tempo and transport), ADR-022, ADR-073, ADR-075; amends ADR-025's stop handler

**Context.** The kernel has had `handleTempoSetting(float)` and `handleTransportState(bool)` since
P4-5; the AUv3's render block calls them every cycle from the host's two blocks. JUCE gives a
processor an `AudioPlayHead`, valid only inside `processBlock`; a standalone has none, and a host
need not fill in the tempo or the playing flag.

**Decision.**
1. **No transport struct.** At the top of every `processBlock` the processor reads
   `getPlayHead()->getPosition()` and calls the kernel's two handlers — tempo, then transport,
   before anything of the block is rendered, as the AUv3 does. Each acts on a difference only:
   the tempo against `arpRate` *as the kernel holds it* (ADR-025), the transport on the edge to
   stopped. A tempo that is missing, not finite or not positive is no tempo; a missing position
   is no transport. Then nothing is called, and the plugin's own tempo applies — the standalone.
2. **While the host has a tempo it is the tempo; the tempo parameter is reported, not obeyed.**
   `arpRate` is skipped when changed host parameters are turned into events, and joins the
   parameters read back after the render: whatever was written to it — automation, an editor, a
   restored session — it is put back to the host's tempo within the block and the host is told
   (off the message thread: a VST3 output parameter change, no gesture, ADR-073). The AUv3 behaves
   the same way by construction. **A saved tempo cannot override a live one:** a session saved
   at 90 BPM restores the parameter as 90, and the first block in a 120 BPM project is already
   rendered at 120 — the handler runs before the block's first sample. When a host's tempo goes
   away the last one stays and the parameter is obeyed again.
   `S1PluginProcessor::isUsingHostTempo()` tells an interface which it is (X3); `arpBeatCounter()`
   is the sequencer's step count for its step lights.
3. **A transport stop is an all-notes-off** (`PORT FIX`, both products). P4-5's handler released
   the sounding voices and rewound the sequencer, and deliberately left the keys alone because
   `heldNoteNumbers` was then a main-thread array. Two defects followed, both found by
   `PluginTransportTests` and both present in the Mac AUv3:
   - **Every key stayed down.** In `heldNotes`, so an arpeggio went on after the stop; and in the
     host MIDI router, which does not press a key that is already down (`pressAdded`, the
     on-screen keyboard's rule): a host that stopped without note-offs — the very case the
     handler exists for — had its next note-on of the same key swallowed. The stop now does what
     CC123 does (`S1HostMIDI::transportDidStop`: the router's `allNotesOff`, then
     `stopAllNotes`); without the router, `stopAllNotes`. `heldNotes` has been render-thread safe
     since X1-2.
   - **The envelopes never saw the gate fall.** ADR-025 says the stop uses "the two lines
     `turnOffKey` uses"; for a polyphonic voice `turnOffKey` uses four — the other two run each
     envelope once with the gate down. Without them, a voice that had already decayed under the
     release threshold (any sound with no sustain) is freed before it runs again, its envelope
     stays where a held key left it, and the voice's next note — gate still high, no attack — is
     **silent**: after a stop, the first note of the next phrase was missing. The two lines are
     added. (Mono is left as `turnOffKey` has it: its next `turnOnKey` drops the gate itself
     unless legato, where not retriggering is upstream's meaning.)
   Still not done, as ADR-025 decided: locking the sequencer to the host's beat position. The
   arpeggiator starts when keys arrive, on their sample.

**Found, and kept.**
- **Upstream's sequencer counts beats and steps every `arpSeqTempoMultiplier` of one, while its
  readout names that value as a fraction of a bar.** A sixteenth-note step — 125 ms at 120 BPM — is
  0.25, and reads "1/4 note", in the Mac app too ("Divisions: 1/4 note"). The plan's acceptance
  ("a 1/16 arp step is 125 ms") is met with that value; the label is the Mac's and is pinned in
  the test. Whether the readout should say what is heard is an interface question for the owner
  (X3).
- **A tempo change re-quantises the synced values by their time, not by their name** (ADR-022;
  the AUv3 the same). Small moves keep the note value — a quarter-note delay at 120 is 0.48 s and
  still a quarter note at 125 — but a jump far enough lands on a neighbour: 125 → 90 BPM turns that
  quarter note into a "1/4 triplet" (0.444 s). The same happens when a preset made at one tempo is
  loaded into a project at another. Measured and printed by the test, not required by it.
  **Open for the owner at the X2 gate, with the voice-freeing question:** keep the note value
  across tempo changes instead (both products; an engine change).

**Consequences.**
- The Mac AUv3 changes in one respect: keys still down when the transport stops are released
  (an arpeggio no longer goes on under held keys after a stop), and the first note after a stop
  is no longer lost on sounds without sustain. The standalone Mac app has no transport. Goldens
  do not involve the transport.
- `arpRate` is now among the parameters the plugin reports to the host; a host's automation lane
  for it is ignored while the host has a tempo, which is every DAW.
- X3's tempo control should show itself as the host's when `isUsingHostTempo()`.

**Verification.** `PluginTransport` (new CTest, a play head the test controls): at 120 BPM from the
host — with the tempo parameter written to 90 — 25 arpeggio steps are heard, **mean step 124.999
ms measured from the rendered output, no step off by 0.5 ms**; 100 ms at 150 BPM; 125 ms at blocks
of 64, 1,024 and 37; no play head, no position, no bpm: the parameter's 90 BPM, 166.667 ms; a
steady tempo reports nothing, a new one once with no gesture; a value written under a host tempo
does not reach the kernel and is put back; 5,000 and 0.25 BPM settle at the range's ends without
further reports, NaN is no tempo; synced delay and LFO follow 120 → 125 as quarter notes, each
reported once; a session saved at 90 plays at the host's 120 from its first block; a held note is
released by the stop with no note-off and the same key sounds when played again; the stop's block
puts the step count to 0; after it nothing plays; keys arriving at sample 200 of a block start
the arpeggio on that sample with step 0 (C3, then G3); keys the host never released play again;
eight notes after stops that caught decayed voices are all heard; a transport that never moves
disturbs nothing. **Revert-checked four ways:** without the envelope lines 5 checks fail (the
first step after a stop arrives one step late, as G3); without the key release 3; with the tempo
parameter obeyed 2; without the put-back 5.
`PluginTransportTests.testAPhraseAfterAStopBeginsWithItsFirstNote` (Swift) holds the AUv3 to the
same: with the envelope lines removed the first click after a stop measures 4e-05 against 0.22.
18 of 18 CTest tests; 339 Xcode tests green, goldens 20 of 20 bit-exact; signed build installed
2026-09-18, `auval` passed (the kernel's stop handler and the router changed).
CI: `plugin` run 35366014956 and `engine` run 35366014961 green on macOS, Linux and Windows
(and the sanitizers job) on their first run — the step times hold to the same 0.02 ms there.

---

## ADR-078 — Denormal protection: every render call runs with subnormals flushed to zero, in the JUCE plugin and in the Mac products (X2-7)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-7** · Follows ADR-071,
ADR-074

**Context.** The engine had only ever run under Clang on Macs. Its effects — phaser, delay,
reverb, their filters, the compressors — run whether or not a note sounds, and after the last
voice is freed their state decays from a real signal towards nothing: through the subnormal
range, where x86 processors do arithmetic slowly. Nothing in the engine or upstream guards
against it (no flush-to-zero, no DC offset).

**Measured first** (`Tests/Plugin/PluginDenormalTests`: a five-note chord held 4 s, then a tail,
timed per 512-frame block, per-second medians; the same performance through the plugin, the bare
engine, and the bare engine under the guard):
- **The engine reaches subnormals and never leaves.** With short effects its output is subnormal
  for 1.89 million samples of a minute's tail and ends parked at 1.4e-45 — the smallest subnormal,
  which a feedback path rounds back to itself and never to zero. Same count on all three OSes.
- **What that costs, unprotected:** on the CI's x86 machines a silent instrument is 1.25–1.5×
  dearer per block on Linux (540–800 µs against 420–510) and 1.15–1.8× on Windows; a long
  release on Windows costs 1.39× the held chord (the voices' own envelopes and filters). On Apple
  Silicon about 5%. Nothing catastrophic on today's processors — and permanent, for every idle
  instance in a session.
- **Protected:** no second of the tail above 1.01× the sounding part on either x86 machine, the
  silence flat to its end, and the guard costs nothing while notes sound.
- **It is not heard.** `GoldenHarness --flush-to-zero`: 20 of 20 goldens still bit-exact on Apple
  Silicon; `PluginRender` (guarded plugin against the unguarded bare engine) still exact.
- **CoreAudio does not do it for us.** A probe on this Mac (macOS 27, arm64): on an
  `AVAudioEngine` render thread two 1e-20 floats multiply to 1e-40, as on the main thread.

**Decision.**
1. **The JUCE plugin:** `juce::ScopedNoDenormals` is the first statement of `processBlock` —
   flush-to-zero and denormals-are-zero on x86, FZ on arm64, the caller's mode restored on the
   way out. `prepareToPlay` renders nothing and needs none. The standalone renders through the
   same call.
2. **The Mac products too** (`S1ScopedFlushToZero` in `S1AudioUnit.mm`, first statement of the
   render block: `fegetenv` / `fesetenv(FE_DFL_DISABLE_DENORMS_ENV)` / restore — Apple's
   `<fenv.h>` has the mode on both its architectures). The app and the AUv3 both render through
   that block. For Intel Macs chiefly; bit-exact, so nothing to hear and no golden to rewrite.
3. **Not in the engine itself.** The mode is per thread and belongs to whoever owns the render
   call; a host of the engine wraps its call (PORTING.md says so). No DC offset or noise is added
   anywhere: it would be heard by the goldens, and the mode makes it unnecessary.

**The plan's acceptance, as met.** "A 30-second silent tail after a reverb-heavy preset uses no
more CPU than the sounding part, measured on x86": for three sounds (a long wet reverb fed by a
delay; short effects, the case that reaches subnormals soonest; dry) the plugin's dearest tail
second over 40 s is ≤ 1.01× a sounding block on Linux and Windows x86-64. The assertion allows
1.25×, on the quickest of three performances per second — the first CI run read 1.48× for one
second on a busy machine, and a neighbour can only add time.

**Verification.** `PluginDenormals` (new CTest): a play head — called only inside `processBlock`
— sees 1e-20 × 1e-20 = 0 there, and the test's thread computes 1e-40 before, after
`prepareToPlay` and after `processBlock`; zero subnormal samples out of the plugin in 3 × 40 s ×
three sounds; the timing criterion; the unprotected engine's numbers printed beside it on every
OS. Revert-checked: without the guard the mode check fails and 3.6 million subnormal samples come
out. `GoldensFlushToZero` (new CTest, Apple only): 20 of 20 exact. Swift:
`PluginTransportTests.testTheRenderFlushesSubnormalsAndHandsTheModeBack` sees the same from the
AU's tempo block (revert-checked). 20 of 20 CTest tests; 340 Xcode tests green, goldens 20 of 20
bit-exact; signed build installed 2026-09-18, `auval` passed. CI: `plugin` run 35372776286 and
`engine` run 35372776297 green on macOS, Linux and Windows; the measurements above are from
`plugin` runs 35370147959 and 35371606536 on the same branch.

---

## ADR-079 — Validation: pluginval at strictness 10 with Steinberg's validator handed to it, both pinned; a RealtimeSanitizer build (X2-8)

**Date:** 2026-09-18 · **Status:** Accepted — **CI verification of the last three commits is
owed** (see Verification) · **Cross-platform plan, X2-8** · Follows ADR-072, ADR-073, ADR-076

**Context.** `auval` holds the Catalyst AUv3 to Apple's rules (`Scripts/validate-au.sh`). The JUCE
build has no AU (ADR-055/058); what holds a VST3 to its hosts' expectations is Tracktion's
`pluginval` — which opens, fuzzes, saves, restores and renders a plugin the way careless hosts do —
and Steinberg's own `validator`. The plan's row also lists `auval -v aumu <subtype> BP03`: that
line is the AUv3's and is already run; there is nothing for it in the JUCE build.

**Decision.**
1. **pluginval `v1.0.4` at `--strictness-level 10`, in process, on the built `.vst3`, in the
   `plugin` workflow on macOS, Linux (under `xvfb-run`) and Windows.** Tracktion's release
   archives, pinned by version **and SHA-256** (recorded from the first run; the release carries
   no digests): Linux `c01c49d8…5352`, macOS `3c4c533b…b29f`, Windows `c08e61ce…15ab`. Its log is
   kept as an artefact for 14 days, pass or fail.
2. **Steinberg's `validator -e`, built in the workflow from the SDK** at `v3.8.0_build_66`
   (commit `9fad9770…`) — the SDK version JUCE 9.0.2 bundles, MIT — only the `validator` target,
   no VSTGUI, no examples; run by itself and **handed to pluginval with `--vst3validator`.**
3. **A skipped test fails the step.** Found on the first run: without a validator path pluginval
   prints `Skipping vst3 validator as validator path hasn't been set`, carries on, and ends with
   `SUCCESS`. 1.x does not carry the validator inside it, whatever one remembers.
4. **`Scripts/validate-plugin.sh`** does the same on a developer's machine, and builds BOTH tools
   from their authors' repositories pinned by tag and commit (pluginval `ed19c2c1…`) into
   `build/validation` — nothing precompiled is downloaded and run locally.
5. **RealtimeSanitizer:** `-DS1_RTSAN=ON` (Clang 20+) adds `-fsanitize=realtime` and defines
   `S1_NONBLOCKING` as `[[clang::nonblocking]]` on `S1DSPKernel::process`, `processWithEvents`
   and `S1PluginProcessor::processBlock`; the `realtime-sanitizer` job runs every test under it.
   In every other build the macro is empty — the attribute wants its functions `noexcept`, and
   no product build changes for a check one CI job makes.

**Found.**
- **pluginval at strictness 10 passed on all three OSes on its first run** — every test, the
  parameter fuzzing, state from a background thread, editor automation, bus layouts — with the
  plugin as X2-7 left it. X2-2's and X2-5's thread rules were written for exactly these tests.
- **Steinberg's validator: 536 of 537.** `Programlist 000->Program 000: has no name!!!` —
  `getProgramName` returned an empty string for the one program a host is shown.
  **Fixed:** the program is the sound by its name (`identity.name`, under its lock), `"Init"` when
  that is blank; `PluginState` checks it. 537 of 537, no warnings. pluginval alone would never
  have said so (3).

**Verification.** Local, macOS arm64, `Scripts/validate-plugin.sh`: validator 537 of 537;
pluginval strictness 10 `SUCCESS` with the validator run inside it (369 ms, exit 0), nothing
skipped. CI `plugin` run 35381919830 (pluginval alone, before 2–3 existed): `SUCCESS` on macOS,
Linux and Windows. 20 of 20 CTest tests locally. **Owed:** GitHub stopped starting this
repository's jobs on 2026-09-18 19:00 UTC — *"recent account payments have failed or your spending
limit needs to be increased"* — so the validator build on Linux and Windows, the skipped-test
guard and the `realtime-sanitizer` job (whose first attempt failed only at linking the `.vst3`, a
shared library, with the sanitizer's runtime: it builds the tests alone now) **have not run.**
The branch `x2-validation` is not merged until they have. RTSan is expected to find things — JUCE's
listener lock under `sendValueChangedMessageToListeners` on the audio thread (ADR-073) first of
all — and each gets a decision here.

**Amendment, 2026-09-18 — macOS leaves the CI matrix (owner's decision).** Both workflows run on
Linux and Windows only. On a private repository macOS minutes bill tenfold (Windows twice), a
`plugin` run is about 14 minutes per OS, and the day's runs spent the account's allowance — which
is what stopped the jobs. Making the repository public was considered and rejected: it would
publish the history (the owner's email), `upstream/` (AudioKit's Audiobus key), AudioKit's App
Store screenshots and `docs/private/`, none of which can be taken back. What macOS CI gave is
given locally before every merge, on the only machine that can show the goldens bit-exact: the
full CTest run in `build/plugin`, the Xcode suite, `Scripts/validate-plugin.sh`, and for engine
or Mac-source changes `Scripts/build.sh` + `Scripts/validate-au.sh`. "CI on three OSes" in the
working pattern now reads: Linux and Windows in CI, macOS here. A run costs about a quarter of
what it did. The macOS branches of the workflow steps are kept, so adding `macos-latest` back to
the matrix is one word.

**Second amendment, 2026-09-18 — CI moves to the developer's machines (owner's decision: GitHub's
billing is not going to change).** The workflows stay in the repository, pinned and correct as
far as they could be checked, for the day jobs start again; nothing waits on them any more.
- **Linux: `Scripts/validate-linux.sh [all|tests|validate|rtsan] [--x86]`**, in Docker on the Mac —
  `Scripts/linux/Dockerfile` (Ubuntu 24.04, GCC 13, JUCE's packages, xvfb, gtkmm, Clang 20) and
  `Scripts/linux/run.sh`; the repository mounted read-only, build trees in a Docker volume. Native
  arm64 by default (GCC, libstdc++, glibc and X11 are where Linux differs from the Mac); `--x86` is
  an emulated x86-64 container for arithmetic without fused multiply-add (ADR-071), slow.
- **Windows: `Scripts\validate-windows.ps1`**, run by the owner on their Windows machine (Visual
  Studio 2022 C++, CMake, Git): MSVC build, every CTest test, the validator built from the pinned
  SDK, pluginval from the archive pinned by SHA-256 with the validator handed to it. It prints a
  block to paste back. Syntax-checked with PowerShell's own parser (in Microsoft's container);
  **it has not run on Windows yet**, and until its block comes back for a commit, Windows is owed
  for that commit and STATE.md says so.
- **macOS:** as the first amendment has it.
The working pattern's "CI on three OSes" now reads: macOS here, Linux here in Docker, Windows on
the owner's machine — a task merges when the first two are green and says plainly whether
Windows has been run.

**What the Linux runs found (2026-09-18).**
- **Steinberg's SDK will not configure on Linux without `gtkmm-3.0`** — its hosting samples
  (the validator among them) include an editor host that asks pkg-config for it. Added to the image
  and to the workflow. It would have failed in CI the same way.
- **pluginval 1.0.4 cannot run Steinberg's validator on Linux**: it hands it the `.so` inside the
  bundle, and SDK 3.8's validator answers "is not a module directory" — for any plugin. On Linux
  the validator is run by itself (**537 of 537**) and pluginval without it (**strictness 10:
  SUCCESS**, under xvfb); the skipped-test guard allows exactly that one skip there. On macOS and
  Windows pluginval runs the validator itself.
- **The RealtimeSanitizer, on its first run, found two allocations on the audio thread — both
  upstream's, both in the Mac products, both fixed (`PORT FIX`), the goldens bit-exact after each:**
  1. **The voices were made in the first render call.** `init` ends with "initializeNoteStates()
     must be called AFTER init returns, BEFORE process", and upstream left it to the first
     `process` or the first key: seven note states, a dozen Soundpipe modules each, every one a
     `malloc`, in the first cycle of every host. `prepareToRender` makes them now — after `init`,
     before any render, where the oscillator tables are already required; the lazy calls find the
     work done.
  2. **Every arpeggio step allocated and freed.** `S1Sequencer::sequencerLastNotes` was a
     `std::list<int>`: a node per note turned on, freed when it is turned off. It is a
     `std::vector<int>` at the capacity `reserveNotes` gives it. (`reserveNotes` *resizes* it, so
     it starts as 1,024 zeros that the first step boundary "turns off" — upstream's oddity, in the
     goldens, kept.)
  After both: every test under `-fsanitize=realtime` with no finding — the kernel's render calls
  and the plugin's `processBlock`, parameter reports to listeners from the audio thread included
  (ADR-073's worry: JUCE 9 takes no lock there that the sanitizer sees).
- The sanitizer stage leaves the test `Goldens` out: Clang 20 on arm64 Linux reproduces 10 of 20
  goldens bit-exactly and puts one (Soi Ok Balagan) at relative RMS 0.0042 against the 0.0032
  limit. Not a toolchain the product is built with; GCC on the same machine is 20 of 20 within
  tolerance. The twenty presets still render under the sanitizer in the other golden tests.

**Verification, final tree (2026-09-18).** macOS arm64: 20 of 20 CTest tests (goldens bit-exact),
`Scripts/validate-plugin.sh` — validator 537 of 537, pluginval strictness 10 `SUCCESS` with the
validator inside it; 340 Xcode tests green, signed build installed, `auval` passed. Linux arm64 in
Docker: 19 of 19 CTest under GCC 13, validator 537 of 537, pluginval `SUCCESS`, the
RealtimeSanitizer stage clean (18 tests). Linux x86-64, emulated: 19 of 19 CTest. **Windows: owed**
— pluginval alone passed there in CI run 35381919830, before the validator, the program name and
the two engine fixes; `Scripts\validate-windows.ps1` has not been run.

**Windows, 2026-09-18 20:28 — run by the owner, `main` @ `9cb5531`.** `Scripts\validate-windows.ps1`
on Windows 11 Home, Visual Studio 2026 Community 18.10.1 with its own CMake 4.3.1, Intel Core
i7-6700HQ: configured and built with MSVC, **19 of 19 CTest tests, Steinberg's validator 537 of
537, pluginval strictness 10 `SUCCESS`** with the validator inside it. The script ran unchanged on
its first real Windows run. It is also the first build with Visual Studio 2026's compiler (CI had
2022's): nothing new from it. The denormal test on that 2015 laptop processor: a sounding block
of five voices with every effect on costs 1.5–1.6 ms of the 11.6 ms a 512-frame block lasts, and
no second of the 40 s tail costs more than 0.96× that. With this, X2-8's verification is complete
on all three OSes.

---

## ADR-080 — The preset library: the Mac app's factory banks linked into the plugin, user banks as files in a per-user folder, a host's programs the AUv3's 695; and the plugin starts with the SHIPPED Init (X2-9)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-9** · Follows ADR-069,
ADR-076, ADR-079; P4-4's `S1FactoryPresets` is the AUv3's counterpart

**Context.** The Mac app keeps its banks as `<name>.json` files — a JSON array of presets — in its
App Group container, seeded from thirteen bundled files, and offers a host all 695 as AU factory
presets named `Bank: Preset` in a fixed order (a host stores the number). The JUCE plugin had one
unnamed-then-named program and no presets.

**Decision.**
1. **`S1PresetLibrary` (no JUCE).** *Factory banks:* the Mac app's thirteen files linked in as
   JUCE binary data (`S1PresetData`), byte for byte — read-only because they are the binary;
   parsed on first use, never when a host merely scans the plugin; in `S1FactoryPresets.bankOrder`.
   *User banks:* `<name>.json` in a folder the library is GIVEN — the Mac app's bank file format,
   so a bank from either product opens in the other; a single exported preset is a bank of one.
   The folder is read at every listing (another instance, the standalone, may have written);
   a bank is written whole, beside itself, then renamed into place; last writer wins. What is not
   a bank is left out and named as a problem. Bank names become file names no filesystem here or
   on the next machine refuses.
2. **Where:** `<user application data>/BadPackets/Arcade Ruins/Banks` — `~/Library/Application
   Support/…` on macOS, `%APPDATA%\…` on Windows, `~/.config/…` on Linux. **Not the Catalyst
   products' App Group container:** the two libraries sit side by side and neither writes in the
   other's (whether they ever share is X0-2's question at the X3 gate; the files are compatible
   whenever it is asked). Making a plugin touches no disk; nothing is created until a save.
3. **A host's programs are the 695 factory presets, numbered and named as the Mac AUv3's** — held
   to `S1FactoryPresets` itself by a Swift-written fixture (`FactoryProgramFixtureTests` →
   `Tests/Plugin/Fixtures/factory-programs.txt`), names exact (four end in a space). JUCE's VST3
   wrapper changes programs on the controller's thread, never in `process`, so loading may
   allocate. User presets are not programs: the list a host numbers must not move.
4. **Loading a preset** (`loadPreset`): its 150 values as a NEW engine plays them — applied to a
   scratch kernel in upstream's order and read back (ADR-076; 0.11 ms) — the wheel centred, name
   and mod-wheel routing taken, the sequencer reset, **the tuning table left alone** (a preset's
   tuning is X3-5's; the identity keeps the tuning names that describe the table that stays).
   From a host's program change: reported without gestures. **From a person (`asEdit`): every
   changed parameter inside its own gesture, so a host records it** — X3-8's browser will use
   that. `saveCurrentPreset(bank, name)` captures the 150 values into the identity
   (`PluginState::capturedPreset`) and writes the bank. A session saved on a factory preset
   reopens showing that program (same uid and name — 23 uids are shared in the banks).
5. **MIDI program change stays unhandled until X3-8:** it arrives on the render thread, and what
   it should select ("preset N of the current bank", as the Mac app has it) needs the browser's
   notion of a current bank.

**Found, and changed.**
- **The plugin did not start with Init.** Since X2-2 it started with `s1::Preset()` — the preset
  MODEL's bare field defaults — which differ from the shipped "Init" (factory bank `User`, the
  Mac app's Init and one of the twenty goldens) in **28 parameters**: bend range 0 instead of
  ±12 (X2-4's "Init's bend range is 0"), the three compressors at their stops, cutoff 4 kHz for
  2 kHz, tempo sync on. It starts with the shipped Init now — read from that one small file — and
  shows it to a host as what it is, the list's last program, "User: Init".
- **`PORT FIX`: the compressors were made for the wrong sample rate.** Upstream makes the three
  `S1Compressor`s once, in the kernel's CONSTRUCTOR, and `sp_compressor_init` takes its time
  constants from the rate of that moment; `S1DSPKernel::init`, which every host calls afterwards
  with the real rate, never touched them. Every host constructs at 44.1 kHz first — the AU too —
  so in a 48 kHz project the compressors attacked and released 9% too fast, at 96 kHz 2.2×.
  Found because the shipped Init, unlike the bare defaults, actually compresses: `PluginRender`'s
  plugin (constructed at 44.1 kHz, prepared at 96) stopped equalling its reference (constructed
  at 96) once a second note pushed the level over the threshold. `init` makes them again
  (`S1Compressor::prepare`). Goldens bit-exact: they are rendered at the rate they are
  constructed at.

**Verification.** `PluginPresets` (new CTest): the default folder's path and that it is not a
Group Container; making a plugin and listing banks touch no disk; the thirteen linked-in banks
equal the repository's files byte for byte; 695 programs equal the AUv3's list name for name, none
empty; a new instance shows "User: Init" and IS it (0 of 149 parameters differ); 31 programs
across the banks land as the preset gives a new engine, reported with no gesture, the wheel
centred, the tuning untouched; program 412 in the kernel after a block; a saved session reopens on
program 412; a preset loaded as an edit: one gesture per changed parameter; a sound saved into a
new user bank in a folder with a non-ASCII name, found by a second library object, the file a Mac
bank (array, `bank`, `position`), **loaded again: all 150 parameters the same numbers**; replaced
by name, added, removed by uid; saving into "BankA" makes a USER bank and leaves the factory's
alone; two non-banks named as problems while three banks load; file-name rules. `PluginRender`
at 96 kHz is the compressor fix's test (revert: 9,328 samples differ). `PluginState` and
`PluginMIDI` updated for the list and for Init's octave of bend.

---

## ADR-081 — The standalone: JUCE's holder with our own application object — every MIDI input open, settings beside the banks — and an engine that survives its audio device changing (X2-10)

**Date:** 2026-09-18 · **Status:** Accepted · **Cross-platform plan, X2-10** · Follows ADR-043
(the Catalyst standalone's silent engine after a hardware change), ADR-077, ADR-080

**Context.** `juce_add_plugin … FORMATS VST3 Standalone` has built a standalone since X2-1:
JUCE's `StandalonePluginHolder` (an `AudioDeviceManager`, an `AudioProcessorPlayer`, the
processor) in a `StandaloneFilterWindow` showing the editor, with an Options menu for the
audio/MIDI settings dialog. Nobody had run it to a purpose.

**Decision.**
1. **Keep the holder and the window; replace the application object**
   (`Sources/S1Plugin/S1StandaloneApp.cpp`, `JUCE_USE_CUSTOM_PLUGIN_STANDALONE_APP=1`, compiled
   into the Standalone target only — JUCE's `StandaloneFilterApp` is `final`, so it is that
   class's text with two differences):
   - **Every MIDI input is open, and one plugged in later opens by itself** (`autoOpenMidiDevices`
     — the holder's half-second timer). JUCE opens none on a desktop: a keyboard is silent until
     its box is ticked in a settings dialog. An instrument plays when it is played; the Mac app
     listens to every source too.
   - **The settings file is beside the banks**: `<application data>/BadPackets/Arcade Ruins/Arcade
     Ruins.settings` (audio device, window position, and the plugin's own state — ADR-076 — so
     the standalone reopens on the sound it was closed on).
2. **No audio input.** The processor has no input bus, so the holder opens none, asks for no
   microphone permission and shows no feedback-loop notice.
3. **The internal tempo is the `arpRate` parameter** — there is no play head, so ADR-077's rule
   applies by itself ("Tempo" in the generic view). Nothing to build.
4. **An audio device change is JUCE's to handle, and the engine's to survive.** The player calls
   `releaseResources`, then `prepareToPlay` at the new rate and buffer size. That path needs
   X2-2's carried parameters and X2-9's compressors — and one more thing, found here:
   **`PORT FIX`: `prepareToRender` tells the host-MIDI router (`S1HostMIDI::kernelWasPrepared`).**
   `init` drops every voice and held note; the router kept its keys. A key held across a device
   change — or across any host's re-prepare, the Mac AUv3's included — was still "down" in the
   router and silent in the kernel, and its next note-on was swallowed (`pressAdded`): ADR-077's
   fault through another door.

**Verification.**
- **Live, on this Mac (2026-09-18):** the standalone opened on the built-in device at 48 kHz; its
  settings listed every MIDI input open without anyone opening them (an IAC bus and the owner's
  three hardware ports); a virtual CoreMIDI source created AFTER launch was picked up within the
  timer's half second — its mod wheel at 127 reached the render thread (the saved state's
  `cutoff` went from Init's 2,000 to 360, `S1ModWheel`'s figure); quitting wrote the plugin's
  version-1 state into the settings; relaunching and quitting with nothing played left `cutoff`
  at 360 — the state is restored, not re-made. The file the check wrote was moved out of the
  owner's folder afterwards.
- **`PluginStandalone` (new CTest)** — the processor in a `juce::AudioProcessorPlayer` with a
  stand-in device: started at 48 kHz/512, a key through the player's MIDI collector sounds at 220
  Hz; the device stops and comes back at 96 kHz/256 with the key still held — the parameters are
  kept in the host's list and in the kernel, the old note is silence (not a drone, not a crash),
  **the same key played again without ever being released sounds** (failed before the fix: 0),
  in tune, and stops when released; a third device at 44.1 kHz with callbacks of 1,024, 37 and
  480 frames: 440 Hz, every sample finite; 25 more restarts and it still plays in tune.
- **By hand, the owner's (macOS and Windows), because no test can plug in headphones:** open it;
  play a hardware keyboard without touching any setting; change the output device or its sample
  rate while it sounds (Options > Audio/MIDI Settings, or plug in headphones) — it must keep
  playing; quit and reopen — the device and the sound come back.

**Windows, by hand — confirmed by the owner, 2026-09-18** (Windows 11, the machine of ADR-079's
run): the list above — the standalone opens, a hardware keyboard plays without any setting being
touched, it keeps playing through an audio device change, and the device and the sound come back
after a quit. Reported as "ADR-081 list is confirmed on my Windows machine"; the standalone they
ran is the one `Scripts\validate-windows.ps1` builds. **Still to come for the X2 gate:** that
script's printed block for `main` after X2-9/X2-10 (the automated half — it was not pasted), the
same list on the Mac, and the gate's two questions.

**Windows, the automated half — run by the owner 2026-09-18 22:31, `main` @ `a57f59b`** (X2-9 and
X2-10 both in it): Windows 11 Home, Visual Studio 2026 Community 18.10.1, CMake 4.3.1, Intel Core
i7-6700HQ — built with MSVC (the standalone's application object among it), **21 of 21 CTest
tests** (`PluginPresets` with its non-ASCII folder and its renamed-over bank, `PluginStandalone`
across its device changes), **Steinberg's validator 537 of 537, pluginval strictness 10
`SUCCESS`**. `RESULT: PASSED`. A sounding block is 1.8–1.9 ms there now (1.5–1.6 ms at X2-8): the
plugin starts with the shipped Init since X2-9, whose compressors and effects work; no second of
the tail above 1.00×. With this and the hands-on list above, Windows owes nothing for X2.

---

## ADR-082 — A tempo change keeps the note value of what is synced to it (the owner's decision at the X2 gate)

**Date:** 2026-09-18 · **Status:** Accepted · **The X2 gate** · Follows ADR-022, ADR-025, ADR-076,
ADR-077 (which found it and put the question) · The owner: *"yes, the LFO and delay should match
up with the tempo."*

**Context.** With tempo sync on, the two LFO rates, the auto-pan rate and the delay time sit on
note values. When the tempo changed, upstream re-quantised each by its TIME — the nearest note
value at the new tempo to the seconds or hertz it had at the old one. Small changes keep the note
(120 → 125: a quarter note stays one); a jump does not: 125 → 90 BPM turned a quarter-note delay
(0.48 s) into a quarter triplet (0.444 s), and a 3 Hz quarter-triplet LFO at 120 became, silently,
an eighth note at 90. Loading a preset made at one tempo into a project at another did the same.

**Decision.**
1. **`S1DSPKernel::_setTempoKeepingNoteValues`:** each synced parameter's note value is read at
   the tempo it was quantised at — where it sits on one exactly — and it is given that note
   value's frequency or time at the new tempo. A note value the new tempo cannot give within the
   parameter's range (a half-note delay at 40 BPM is 3 s, over the 2.5 s maximum) falls back to
   upstream's way: the nearest that fits.
2. **A host's tempo always does this** (`handleTempoSetting`) — the JUCE plugin and the Mac AUv3.
3. **The `arpRate` PARAMETER does it where its kernel's owner says so**
   (`tempoParameterKeepsNoteValues`, default off): **on in the JUCE plugin** — its Tempo control,
   the standalone's tempo. **`s1::Preset::apply` switches it off for its own duration, always:** a
   preset writes `arpRate` in the middle of its other values, and there upstream's re-quantising
   is what reads the preset's seconds back as the notes they were saved as (ADR-076). The goldens
   are bit-exact.
4. **A preset loaded under a host's tempo is translated by note value** (`loadPreset`): its own
   tempo is not played, so its synced values are read at the PRESET's tempo and given at the
   HOST's — a quarter-note delay saved at 100 BPM is a quarter note in a 140 BPM project (0.4286
   s), not whatever lies nearest 0.6 s there.
5. **Not in this step: the Mac standalone app's own tempo control** (the switch stays off in the
   Mac products). Its interface writes `arpRate` through the same call its preset loading makes
   from three places (`PresetDataManager.loadPreset`, with its freeze options, as well as
   `Preset.apply(to:)`), so switching it on there needs those wrapped first. Turning that knob
   moves through small steps, which keep the note anyway; typed jumps and tap tempo are where it
   would show. Offered to the owner as a follow-up; in a host, the AUv3 follows the host (2).

**Verification.** `PluginTransport`: the host 120 → 125 → 90 → 60 → 180 → 120 — a quarter-note delay
and LFO are a quarter note throughout (0.667 s and 1.5 Hz at 90; 0.5 s and 2 Hz again at 120),
each change reported once; the fallback case lands inside the range; with no host, the Tempo
control 120 → 90 keeps a quarter-note delay a quarter note, and with sync off nothing moves; a
preset saved at 100 BPM (quarter-note delay, half-note LFO) loaded in a 140 BPM project: a quarter
note and a half note, in the host's list and in the kernel. `PluginParameters`: the check that
pinned upstream's behaviour since X2-2 now pins this (a 1/4 triplet at 120 is 2.25 Hz and a 1/4
triplet at 90). Swift `testAHostTempoJumpKeepsTheNoteValue` holds the AUv3 to (2); revert-checked
there (in the JUCE plugin the switch of (3) masks a revert of (2), which is why). 22 of 22 CTest
tests, the goldens bit-exact.

**Windows — run by the owner 2026-09-19 09:31, `main` @ `ea8fd00`** (this change in it): Windows 11,
Visual Studio 2026 Community 18.10.1, Intel Core i7-6700HQ — built with MSVC, 21 of 21 CTest tests
(`PluginTransport`'s note-value checks and `PluginParameters`' rewritten one among them),
Steinberg's validator 537 of 537, pluginval strictness 10 `SUCCESS`. `RESULT: PASSED`. Verified on
all three OSes.

---

## ADR-083 — The layout specification is measured from the Mac layout, not typed (X3-1)

**Date:** 2026-09-19 · **Status:** Accepted · **X3-1** · Follows ADR-045–048 (the desktop layout
and its skins), ADR-059–064 (Cabinet), ADR-056 (X3's scope), ADR-073 (the parameter catalog)

**Context.** X3 draws the interface again in JUCE, from "the 0.5.0 desktop layout, written down as
data". The Mac layout is not a table: `S1DesktopLayout+Rows.swift` builds stack views, and Auto
Layout decides where each control lands — `equalCentering`, three sections of a row tied by width
multipliers, cells as wide as their widest line. Transcribing that by hand would be a second
layout that agrees with the first until someone changes one of them; re-implementing the solver in
JUCE is worse. And which parameter each control drives is not in the layout at all: it is in the
four panel controllers' `conductor.bind` calls.

**Decision.**
1. **The specification is written by a Swift test from the layout itself.**
   `Tests/SynthOneTests/LayoutSpecFixtureTests.swift` builds the desktop layout at the design size
   (1440 × 900) under each skin, exactly as `DesktopLayoutTests` and `SkinTests` do, and writes
   `Sources/S1Plugin/Layout/layout-spec.json`: the metrics, the type by role, and per skin the
   whole palette (every `S1Palette` field, by reflection, so a new colour cannot be forgotten), the
   dress, the regions, the fifteen sections (frame, header, body, accent), every control (id, the
   parameter's `S1Parameter` case name — the JUCE parameter ID, ADR-058 — kind, Mac class, frame,
   its title and readout lines), the envelope plots and XY pads with the parameters they show, the
   toolbar / play-bar / status-bar items, and every free label with its font and colour.
   `Scripts/write-layout-spec.sh` writes it; in the normal suite the same test CHECKS the
   committed file and fails when it is stale — the pattern of the tuning, preset, wavetable,
   host-MIDI and factory-program fixtures. **Never edit the JSON; never type a frame in C++.**
2. **Bindings come from the conductor's own list** (`Conductor.bindings`), plus six controls the
   panels wire by hand and the conductor never hears of: the five "dependent parameters" (LFO 1
   and 2 rate, delay time, auto-pan rate, the sequencer's step length — marked `dependent`: their
   Mac knobs hold a 0…1 position, ADR-022) and the play bar's Transpose. The filter-type picker
   stands in for the hidden classic button that keeps the binding.
3. **Cabinet's rectangle table is carried as it is** — `S1SkinTemplate`'s numbers, in the
   painting's pixels — beside the frames the sections take from it at the design size. The
   interface scales uniformly from the design size (X3-7), so nothing in the file is a fraction
   or a constraint.
4. **`s1plugin::LayoutSpec` reads it** (`S1LayoutSpec.hpp/.cpp`, no JUCE, nlohmann like the state
   and the presets): strict — a missing field, a frame that is not four numbers, a parameter that
   is not an `S1Parameter`, an id used twice, and the whole file is refused with the path of the
   first fault; a half-read layout would be an interface with controls silently absent. The file
   is linked in as JUCE binary data (`ArcadeRuinsLayout`; `S1LinkedLayoutSpec()`, parsed on first
   use — never at a host's scan).
5. **Left out on purpose:** the Cabinet extras (`docs/private/cabinet-extras.md`; X3-6 scopes
   them — the test filters them by name), the preset browser (X3-4), the Tunings sheet (X3-5),
   the classic layout (ADR-056).

**Measured.** 125 controls under each skin, the same ids on the same parameters; **124 of the 150
parameters have a control or a display. The other 26 are listed in `PluginLayoutSpecTests`:** 22
live on the Dev panel (the three compressors' fifteen, `filterMix`, `detuningMultiplier`,
`bitCrushDepth`, the delay input's two, `portamentoHalfTime`, `oscBandlimitIndexOverride`), three
are the pitch wheel and the Wheels popover's bend range (X3-8), and `frequencyA4` is the Tunings
panel's (X3-5). **This meets X3-3's acceptance line head on** — "all 150 parameters reachable from
the interface" — because ADR-056 dropped the Dev panel: X3-3 has to put that to the owner (the 22
stay reachable through the host's generic view and automation either way). Studio's rows are 158 /
220 / 122 / 247; its knobs 30 / 40 / 44 / 46 / 48 / 52 / 68 (the plan named the five large sizes;
40 is the LFOs', 30 the sequencer's). Cabinet's sections sit on the painted rectangles to 0.61
point — Auto Layout puts each edge on the half-point grid.

**The acceptance check, against the running app — not against the test that wrote the file.** The
test bundle builds the layout with no window and in its own idiom, so agreement with itself proves
nothing about the product. `Scripts/check-layout-spec.sh`, per skin: `desktop_render.py` (new
`RENDER_FRAMES=1`) renders the Debug app's window and writes the frame of every visible view in
it; `Scripts/debug/compare_layout_frames.py` requires every section, control and display of the
specification to have a view of its Mac class within 1 point (2 px of the 2× render) on every
edge, each view used once; and `Tests/Plugin/LayoutWireframe` — a JUCE console tool on the
plugin's own reader — draws the wireframe over the render to look at. **Result, 2026-09-19:
Studio 144 of 144 frames, worst 0.00 points; Cabinet 144 of 144, worst 0.00** — with the owner's
library and a different preset loaded than the test's Init, so the frames do not depend on the
sound.

**Consequences.** A change to the Mac desktop layout now fails `LayoutSpecFixtureTests` until
`Scripts/write-layout-spec.sh` is run, and the JUCE interface follows at its next build — for as
long as the Mac layout is the design's source. If the X3 gate retires the Catalyst products
(ADR-055), the JSON becomes the source and the Swift writer goes with them; the file's format does
not change. A readout's width follows its text (`valueFrame` is the cell's full width for that
reason), and `Interval` / `Div` cells are as wide as their readout at Init — X3-2's cells should
centre text in the line, not size to it.

**Verification, 2026-09-19.** macOS — 25 of 25 CTest tests (three new: `PluginLayoutSpec`,
`LayoutWireframeStudio`, `LayoutWireframeCabinet`; the goldens bit-exact), Steinberg's validator
537 of 537, pluginval strictness 10 `SUCCESS`, **343 Xcode tests green** with the specification's
check mode among them. Revert-checked: a knob moved 3 points in the JSON fails the Swift check
("is stale") and fails the comparison with the running app ("Filter.cutoff: 3.00 points off").
No Mac product source changed — nothing rebuilt, reinstalled or `auval`ed. Linux arm64 in Docker —
24 of 24 CTest tests under GCC 13 (the file read, both wireframes drawn), validator 537 of 537,
pluginval `SUCCESS`, RealtimeSanitizer clean (23 of 23 under Clang 20). **Windows: owed** — asked
of the owner at the merge.

---

## ADR-084 — The controls kit: the Mac drawing ported function for function, every edit a gesture, tested with no window (X3-2)

**Date:** 2026-09-19 · **Status:** Accepted · **X3-2** · Follows ADR-083 (the layout specification),
ADR-073 (what a parameter write means to a VST3 host), ADR-048 (one accent per section), ADR-077
(the host's tempo is the tempo)

**Context.** X3 draws every control again in JUCE. The Mac controls are UIKit views driven by raw
touches, drawn — under the desktop layout — by one file, `S1DesktopStyle.swift`, from the skin's
palette and the control's section accent; three classic drawings (the morph selector, the ADSR
view, the touch point) ride along unchanged. X3-1 left all of that as data: every colour, the
dress, each control's `kind`, frame and parameter.

**Decision.**
1. **Two layers, `Sources/S1Plugin/UI/`.** `s1ui::Style` (`S1KitStyle`) is drawing only: a port of
   `S1DesktopStyle.swift` function for function (`drawKnob`, `drawSwitch`, `drawLFOChip`,
   `drawWavePicker`, `drawStepper`, `drawTempoStepper`, `drawTwoWaySwitch`, `drawDirection`,
   `drawFader`, `drawStepButton`) plus the number box, the segmented picker, the morph selector,
   the envelope and the pad, onto `juce::Graphics`. It owns no colour and no size — the palette
   by S1Palette's field names, the dress, the accent handed in. `S1KitControls` is the components:
   `ParameterControl` and one class per `kind` — `Knob`, `Toggle` (pill and step bar),
   `TwoWaySwitch`, `LFOChip`, `CellPicker` (waves, direction, segmented), `MorphSelector`,
   `Stepper` (plain and tempo), `StepOctave`, `StepFader` — with `XYPad`, `EnvelopeView` and
   `ValueReadout` for what spans several parameters; `makeControl` / `makeDisplay` build the right
   one from a specification entry, named for accessibility ("Filter Cutoff").
2. **Every edit is a gesture through `juce::ParameterAttachment`** on the `S1HostParameter`: a drag
   is begin / values / end, a click one complete gesture, so a host in write mode records it, an
   undo manager sees one step, and automation, the generic view and what the engine reports back
   (ADR-073) all arrive through the same attachment. Nothing in the kit touches the processor.
3. **What the plan asked of every control lives in the base class:** double-click puts the default
   back; the wheel and the arrow keys nudge (whole steps for a stepped parameter — fractions add up
   until they make one; shift is ×10); Alt makes a drag, the wheel and the keys fine (the Mac's ⌥,
   ×0.2); a focus ring in the accent; an accessibility handler — a slider with the parameter's
   plain range and the host's own text, or a checkable toggle button — and a name.
4. **The Mac's behaviour is kept where it is a rule and not where it is a touch-screen accident.**
   Kept: a knob's 0.005 of travel per point with right and up adding; the chip's halves (LFO 1 left,
   LFO 2 right, value a bitmask); a click anywhere flips a switch, the Arp / Seq switch included;
   the fader's cap goes where the pointer is, its travel 10 points inside each end (3 short of the
   groove, as on the Mac); the envelope plot's three areas and rates (a point is a millisecond,
   ten points one per cent of sustain). **Changed, each marked `PORT:`:** a click on the morph
   selector goes where it is (the Mac ignores a touch's first point); the step's number box SHOWS
   the pattern value an octave outward while boosted instead of mutating a stored number (the Mac
   label adds 12 every time its setter runs); callbacks fire once per click, not on down and up;
   the XY pad's snap-back restores the values held when grabbed, inside the same gesture.
5. **The tempo under a host is shown, not edited:** `Stepper::setHostOwned` (X3-3 drives it from
   `isUsingHostTempo()`).
6. **Tested with no window and no desktop.** Mouse handlers only translate events into plain
   methods (`grab`, `dragBy`, `letGo`, `pressAt`, `press`, `moveTo`, `nudge`, `resetToDefault`);
   `Tests/Plugin/PluginControlsKitTests` calls those on the real processor's parameters with a
   listener counting gestures, paints with `createComponentSnapshot` at 1× and 2×, and builds the
   accessibility handler directly. On the test's thread the attachment calls back at once
   (`ScopedJuceInitialiser_GUI` makes it the message thread), so nothing waits on a run loop.
   `Tests/Plugin/ControlsKitSheet` paints the whole kit on the specification's frames — the
   picture held beside the Mac render.
7. **The specification grew three facts the kit needed** (the Swift writer, regenerated): a chip's
   words (`title` from `buttonText`), the two-way switch as its own kind `twoWay` with its two
   words, and each envelope plot's `curve` and `fill` as the Mac view has them under that skin —
   measured, because my guess was wrong: the filter envelope is NOT unfilled, its fill is
   `#2c2c2c` under an orange line, and the amplitude envelope's line is `#1a1a1a` over orange.

**The type — open, the owner's.** The Mac interface is set in Avenir Next Condensed, a macOS
system font that Windows and Linux do not have and that cannot be shipped. `Style::font` uses it
where the system has it and otherwise the default sans narrowed to its width (×0.82), which keeps
every label inside the frame the specification measured. A face that ships with the plugin means
a font file in the repository and a NOTICE.md line — a download and a licence, so it was put to the
owner rather than done (candidates under the SIL Open Font Licence: Barlow Condensed, Sofia Sans
Condensed, Archivo Narrow). Until then macOS looks as the Mac app does and the other two look
approximate. Nothing else in the kit depends on the answer.

**Measured.** 125 of 125 controls and 4 of 4 displays built for each skin, each painting at 1× and
2× (the 2× image exactly twice the 1×), named and focusable. 100 points of drag = 0.500 of a knob's
travel, 0.100 with Alt, one gesture; reset = the default as one gesture; a key 0.010, shift 0.100;
a stepped parameter one whole step per key and whole numbers under a one-point-at-a-time drag; a
host's write moves knob, readout ("1.00 kHz") and pixels; a knob's arc is its section's accent
(mint in Cabinet's Mix, orange under Studio); chip 1 → 3 → 2; pickers by cell and by key; stepper
zones, clamping, "120 bpm", host-owned; number box 7 / 19 / −17 / −5; fader ends at 10 points;
pad x / y-upward, a gesture on each parameter, snap-back; envelope areas and rates; a one-point
border is one whole pixel row at 1× and two at 2×. Side by side with the Mac render
(`Scripts/check-layout-spec.sh`'s images) the kit matches under both skins; Core Graphics' blur is
softer than a JUCE drop shadow of the same radius, so glows use four fifths of it.
**Revert-checked:** the drag's sensitivity at 0.004 fails two checks (0.4, 0.08); a border drawn
off the half-point fails both edge checks (blue 97 and 12 against 212 and 183). The first edge
check was worthless — Studio's border and well are six levels apart, so it passed whatever was
drawn — and was rewritten on Cabinet's cyan border: **a revert-check that cannot fail is the
finding.**

**Known differences from the Mac, for X3-3's side-by-side.** The sequencer's Interval reads
"+12 st" (the catalog's format since X2-2, ADR-073) where the Mac's cell reads "12". The morph
selector's and the touch point's orange are the classic kits' own under every skin, as on the Mac.
The segmented picker's cells are equal; UIKit sizes each to its word. The Cabinet pads have no CRT
frame yet (decoration: X3-6). No editor exists: the processor still returns the generic one.

**Verification, 2026-09-19.** macOS — 28 of 28 CTest tests (new: `PluginControlsKit`, 70 checks,
`ControlsKitSheetStudio`, `ControlsKitSheetCabinet`; the goldens bit-exact), Steinberg's validator
537 of 537, pluginval strictness 10 `SUCCESS`, 343 Xcode tests green with the regenerated
specification's check mode. No Mac product source changed — nothing rebuilt, reinstalled or
`auval`ed. Linux arm64 in Docker — 27 of 27 CTest tests under GCC 13 (the kit built, driven and
painted with no window and no fonts installed), validator 537 of 537, pluginval `SUCCESS`,
RealtimeSanitizer clean (26 of 26 under Clang 20). **Windows: owed**, with X3-1's (the owner's try
of 2026-09-19 found "nothing new" after `git pull`; the block was not pasted, so which commit their
clone holds is not known).


---

## ADR-085 — The editor: the specification's frames, the kit's controls, the painting under Cabinet; every parameter reachable (X3-3)

**Date:** 2026-09-19 · **Status:** Accepted · **X3-3** · Follows ADR-083, ADR-084, ADR-056 (scope),
ADR-059/064 (Cabinet, the default), ADR-077 (the host's tempo)

**Context.** X3-1 left where everything sits and what it drives; X3-2 left every control. X3-3 is
the window: toolbar, fifteen sections, play bar, status bar — and the plan's acceptance, "all 150
parameters reachable from the interface; a test walks the component tree", against a desktop
layout that gives 26 of them no control (ADR-083) and a scope decision that dropped the panel 22
of those lived on (ADR-056).

**Decision.**
1. **`S1PluginEditor` (`Sources/S1Plugin/UI/`) is what `createEditor` returns**, at the design size
   1440 × 900, not resizable (X3-7 scales it). It knows no frame, colour or binding: controls come
   from `makeControl` on the specification's frames, a `ValueReadout` on every `valueFrame`, plots
   and pads from `makeDisplay`, toolbar and play-bar pieces from the specification's `items`.
   Everything that never moves — bars, section panels, titles, labels, the painting — is one
   opaque, buffered `Backdrop`.
2. **Both skins from one build; the constructor takes the skin's key, Cabinet by default.** Under
   Cabinet the backdrop is the owner's painting (`s1_template_cabinet@2x.jpg`, the Mac app's own
   file, linked in with the wordmark as `ArcadeRuinsArt`; 1.2 MB) and the header's buttons are
   invisible hit areas over the painted ones; under Studio it draws `S1SectionView`'s panels and the
   toolbar. Choosing a skin in the interface is X3-6.
3. **Every parameter is reachable: Settings opens "Every parameter"** — JUCE's generic list of all
   150 on a card over the sections. 124 have a control, plot or pad of their own; the other 26 —
   the Dev panel's 22, the pitch wheel and its range, `frequencyA4` — are there. This keeps
   ADR-056 (no Dev panel is rebuilt) and meets the plan's line as written; when X3-6 builds real
   Settings the list becomes one entry in it. **Put to the owner as done, not asked**: it costs
   nothing to remove.
4. **The dependent parameters sit by note value, as on the Mac** (`s1ui::PositionMap`,
   `dependentPositionMap`): found by the side-by-side, not by a test — with tempo sync on the Mac's
   LFO-rate knob for "1/8 note" sat at 60% of its travel and the kit's, mapped through the host
   parameter's Hz range, at 15%; pad 1's point likewise. The kit now uses the engine's own
   arithmetic (`S1Rate`: `nearestFrequency` / `nearestTime` / `nearestFactor` for where a value
   sits, `rateFrom…01` for what a position means, the 0.4 taper with sync off), reading the sync
   switch and the tempo from their host parameters; the editor repaints those five knobs and the
   pad when either moves. A drag steps through note values, as the Mac's does.
5. **What spans controls is the editor's, on a 30 Hz timer** (`refreshLiveState`, callable without
   one): the playing step's ring from `arpBeatCounter()` while the arpeggiator is on and the counter
   is moving; the tempo shown as the host's (`Stepper::setHostOwned`, ADR-077); the rate readouts;
   Mono lit from `isMono`; the preset's name; the scope.
6. **Three small things were added to the processor, none touching the sound:**
   `requestAllNotesOff()` — Panic: an atomic flag, consumed at the top of the next block as a CC
   123 event through the router (never the kernel from the message thread; the router lets go of
   its keys too, ADR-081's rule); a lock-free ring of the last 1,024 LEFT output samples for the
   scope (left, as the Mac's plot: a widened sound's two sides cancel in a sum — measured, the
   first version summed them); `currentPresetBank()` / `currentPresetName()`.
7. **Working now:** every parameter control, plot and pad; previous / next through the 695 factory
   presets in a host's program order, loaded as a person's choice (gestures, so a host records
   them); Panic; Mono; Snap; the scope; About; Every parameter. **Says where it comes instead of
   pretending:** the preset browser, Save and the dice (X3-4), Tuning (X3-5), Hold, Wheels and the
   keyboard's octave (X3-8) — a press writes "… comes with X3-n of the plan." in the status bar.
   **Left out on purpose:** MIDI Learn (deferred for 1.0, ADR-056) and the recorder (a host
   records; the painted plate is About, as in the Mac plugin).

**Measured against the Mac app, same preset in both** (`desktop_render.py` with `RENDER_SELECT`,
`EditorSnapshot --program`, `Scripts/debug/compare_editor_render.py`): mean difference per colour
channel (0–255) inside each section's frame — **Studio 1.4 to 6.1, 3.3 over the whole window;
Cabinet 2.4 to 8.3, 5.9 over the window** (its glows are where a JUCE shadow and Core Graphics'
differ most); Pads the outlier in both (10.6 / 11.3): the touch point's glow, and under Cabinet
the CRT frame that is X3-6's. A number, not a verdict — it is there so a missing or misplaced
control shows at once; the owner's eyes are the acceptance.

**Known differences, for the owner's side-by-side** — none silently "fixed": the preset reads
"Bank: Name" where the Mac reads "index: Name" (X3-4 settles it with the browser); Interval reads
"+12 st" (ADR-084); the step length reads "1/4 note" where the Mac reads "1/2 note" for the same
value (ADR-077's label question, still the owner's); the play bar's two steppers are the desktop
stepper where the Mac keeps the classic arrows there; no MIDI Learn button; the hint says "Alt"
for ⌥; Cabinet's pads have no CRT frame yet.

**Tested with no window** (`Tests/Plugin/PluginEditorTests`, 37 checks): both skins at the design
size; the tree walked — 125 parameter controls, each on its specified frame and parameter; 124
parameters with a control of their own and the list of all 150 behind Settings (the 26 printed);
the window opaque everywhere; every item pressable; previous / next / wrap with gestures counted;
Mono; "comes with X3-4"; **Panic heard** — a held note silent eight seconds on with the key never
lifted, and the same key playing again; the scope's ring holding the sound; the tempo under a host
at 97 BPM reading "97 bpm" and refusing edits, then the plugin's own again; exactly one step ringed
while the arpeggiator runs; five editors made and destroyed with parameters moving between.
`EditorSnapshot` paints the whole window (about 85 ms at 2× here, once: the backdrop is buffered).
pluginval opens the real editor at strictness 10.

**Revert-checked, and the first try found the test, not the code.** With the panic event taken out
the Panic check still PASSED: by then the test had stepped to a factory preset whose note dies
away by itself, so "silence eight seconds on" was true whatever Panic did. The test now loads the
shipped Init, shows the held note still sounding after eight seconds (0.387) and only then presses
Panic: without the event it fails at 0.387, with it the output is 0. The fourth time this project
has met the rule — **test with a sound that uses the thing** (ADR-077, ADR-078, ADR-080) — and the
second revert-check in two tasks that did not fail (ADR-084).

**Verification, 2026-09-19.** macOS — 31 of 31 CTest tests (the goldens bit-exact), Steinberg's
validator 537 of 537, pluginval strictness 10 `SUCCESS` with its three editor tests run on the real
window. Linux arm64 in Docker — 30 of 30 under GCC 13, validator 537 of 537, pluginval `SUCCESS`
under xvfb, RealtimeSanitizer clean (29 of 29 under Clang 20): the panic event and the scope's ring
allocate nothing on the audio thread. No Mac product source, Swift or specification change, so no
Xcode run. **Windows: owed**, with X3-1's and X3-2's. **The owner's side-by-side sign-off: open.**


## ADR-086 — The preset browser: the banks become the person's files, a model with no JUCE in it, the Mac's card over it (X3-4)

**Date:** 2026-09-19 · **Status:** Accepted · **X3-4** · Follows ADR-080 (the library), ADR-085 (the
editor), ADR-040 (Bonus into BankA), ADR-036 (a test must never write the owner's files),
ADR-044 (never a modal panel from a plugin), ADR-047 (the Mac's drop-down)

**Context.** X2-9 gave the plugin presets without an interface: the thirteen factory banks linked
into the binary, read-only, plus user banks as files in a shared folder. X3-3 gave the window, and
left the preset name, Presets, Save and the dice saying "comes with X3-4". The plan's acceptance
for X3-4 is *every operation the Mac browser performs works in a host and in the standalone,
including saving; import reads a bank exported by the Mac app unchanged.*

That acceptance cannot be met with read-only factory banks. Starring a factory preset, reordering
BankA, renaming a bank, deleting a preset — every one of them writes to a bank the binary holds.

**Decision.**
1. **The banks become files the person owns, on first use — what the Mac does on first launch.**
   `PresetsViewController.loadBanks` writes the bundled bank files into Documents and never reads
   the bundle again; `PresetBrowser::load()` does the same into
   `<application data>/BadPackets/Arcade Ruins/Banks`, and from then on a file IS the bank. Twelve
   banks, not thirteen: `Bonus.json`'s presets say `"bank": "BankA"` inside and the Mac appends them
   to BankA (ADR-040), so BankA is written with all 135. The order is AppSettings.swift's
   `initBanks`, transcribed into `PresetBrowser::initialBankOrder`. About 2 MB, written once, and
   **only when a person asks for a preset** — never when a host scans the plugin or opens the
   window: the editor makes the browser lazily, on the first press of the preset name, ▶, ◀, the
   dice or Save.
2. **What a HOST stores is untouched by any of it.** `PresetLibrary::factoryProgram` still reads the
   banks linked into the binary, so program 137 is the same sound after the person has reordered
   their copy of BankA, renamed it or thrown it away. A test holds program 0 to its name across the
   whole session's editing.
3. **The model is `s1plugin::PresetBrowser` — no JUCE in it**, a port of the Mac browser's own
   logic file for file: `sortPresets` (All by bank, the six categories, Alphabetical, Favorites,
   a bank's own order), the category row numbers (`bankStartingIndex` is 9 here because it is 9
   there — the sorting is written against those integers), New, New Bank, duplicate " [copy]",
   the star, save, delete, reorder, rename and delete a bank, import and export. It is driven and
   measured with no window by `Tests/Plugin/PluginPresetBrowserTests` (101 checks).
4. **The card is a thin view** (`s1ui::PresetPanel`): the Mac's 380 × 720 drop-down, hung under the
   preset name, with PRESETS and "+", the search field, the categories and banks at 228 points, the
   presets of the selection, the chosen preset's category and notes, and New / Import / Reorder /
   Import Bank. Everything it does can be done without a mouse (`chooseRow`, `chooseCategory`,
   `pressButton`, `pressRowButton`, `setSearch`, `editorCardSave`), which is how `PluginEditorTests`
   works it. A click anywhere else puts it away, as the Mac's backdrop does.
5. **Previous, next and the dice walk the list the browser is showing**, not the host's program
   order — a bank, a category, or the search's matches. The browser opens on All, as
   `PresetsViewController.viewDidLoad` does, so ▶ walks the whole library until a person picks a row.
6. **Save is the Mac's Save**: `savePresetPressed` opens the preset editor on the sound as it stands
   (`Manager+PresetsDelegate.saveEditedPreset`), so a name, a category and a bank are chosen before
   anything is written. A sound that came from a host's session and is in no bank is offered as a
   new preset.
7. **A uid is how a row, a save and a deletion name a preset — and the shipped banks do not hold
   695 different ones.** 670 uids for 695 presets: 23 are used twice, upstream copying a preset
   between banks. Upstream never noticed because its tables hold object references; here a reorder
   of Starter Bank moved a preset in another bank. `readFolder` gives the second of each pair a
   fresh uid and writes that bank back once; after that the files hold what is read. **Found by a
   test, not by a guess** — see the revert-check below.
8. **Where the banks' order lives:** `banks.order` beside them, a JSON array of names, written on
   every change. Deliberately **not** a `.json`, because `PresetLibrary::userBanks` reads every
   `.json` in the folder as a bank and would have shown the order file as one. The Mac keeps the
   same thing in its own `banks.json` in AppSettings' folder.

**Where it differs from the Mac, on purpose.**
- **Search filters the list in place** instead of opening the classic search screen over the
  window; the rule it matches is the screen's own (the name or the notes, anywhere in the library,
  sorted by name).
- **Reorder gives each row two arrows** where the Mac gives drag handles: while Reorder is on, a
  row carries ▴ and ▾ and nothing else, and Done puts the star, rename, duplicate and share back.
- **The preset editor's category and bank are pop-up menus**, where the Mac uses two tables — it
  uses tables only because a `UIPickerView` crashes under Optimize Interface for Mac (ADR-033),
  which is no constraint here.
- **Import and Export go through `juce::FileChooser::launchAsync`, never a modal call**: a plugin
  does not own the host's event loop (ADR-044's lesson in JUCE's words).
- **The toolbar still reads "Bank: Name" where the Mac reads "index: Name".** Decided here and
  told, not asked: the Mac's number is the preset's place in its bank, which means nothing without
  the bank beside it, and "Bank: Name" is what the host's own program menu shows. Say the word and
  it becomes the Mac's.

**Two small additions elsewhere:** `PresetLibrary::removeBank` (a bank's file taken away; one that
is not there is not a failure) and `presetDefaults()` (what an imported file's missing keys take).

**Tested.** `PluginPresetBrowserTests` (101 checks, in a folder of its own under the system's
temporary folder — ADR-036's rule): the twelve banks written on first load and in AppSettings'
order, BankA holding its 41 and Bonus's 94, every preset with a uid of its own; the category rows
and their numbers; what each row shows; the search by name and by notes; stepping and wrapping;
New, the star, duplicate, save (the name, the category, the sound's own values, a move between
banks), delete and what plays afterwards, reorder; the order kept across a reopened browser;
New Bank, rename and delete a bank; **a bank the Mac app exported read unchanged** — all 15 presets
of `Starter Bank.json`, in the file's order, with the file's sounds, each under a uid of its own,
and the Mac's own " [rename]" when the name is taken; one preset exported and imported back.
`PluginEditorTests` adds 30 checks through the card itself (69 in all now): it drops down under the name and inside
the window at 380 wide, a row chosen is the sound that plays (in gestures a host records), a bank
row filters, the search narrows, New plays the new preset, the star stars, Save keeps the sound
that was playing under the name and category it was given, the arrows move a row and put it back,
duplicate plays the copy, the dice plays another, and the name puts the card away.
`EditorSnapshot --presets` paints the card for both skins, so it is known to draw on every OS.

**Revert-checked, three times, and one of them was the finding.**
- Take the uid dedupe out and **two** checks fail — "every preset has a uid of its own" and "the row
  moved down two, and the others came up". That is how the duplicate uids were found at all: the
  reorder test failed before anyone suspected the data.
- Drop the banks' order file and the reopened browser lists a later bank before an earlier one.
  **The first version of that check could not fail**: it only asked whether the file existed, and
  the twelve bundled names are enough to order themselves. It now makes a thirteenth bank, renames
  it to sort first, and reads it back — and that one fails. The third check in three tasks that
  did not fail as written (ADR-084, ADR-085).
- Take the view's reorder guard out and four checks fail.

**Also found: `juce::TextEditor::setText` POSTS its change message** (`postCommandMessage`), so a
search set from code reaches the model only when the message loop runs — and in a test it never
would. `PresetPanel::setSearch` tells the model itself.

**Verification, 2026-09-19.** macOS — 34 of 34 CTest tests (the goldens bit-exact; new:
`PluginPresetBrowser`, and the two `EditorSnapshotPresets…`), Steinberg's validator 537 of 537,
pluginval strictness 10 `SUCCESS`. Linux arm64 in Docker — see STATE.md. No Mac product source,
Swift or specification change, so no Xcode run. **Windows: owed**, with X3-1's, X3-2's and X3-3's.

## ADR-087 — The tunings: the Mac's banks as a model, a preset's own scale played, and A4 made live (X3-5)

**Date:** 2026-09-20 · **Status:** Accepted · **X3-5** · Follows ADR-068 (the tunings as engine
data), ADR-086 (the model-and-view shape), ADR-076 (a preset's values), ADR-085 §"the tuning
stays", ADR-056 (scope)

**Context.** X1-4 put the 194 shipped tunings, the tuning table and the Scala parser in the engine
as plain C++ and proved them bit-exact against the Swift. Nothing above them was built: X3-3's
editor said "Tuning comes with X3-5", `loadPreset` deliberately left the tuning table alone, and
the plan's acceptance for X3-5 is *a preset that carries a tuning plays in it, and the panel's
tables match the Mac's*. **478 of the 695 factory presets carry a tuning; 11 of them carry one that
is not twelve notes** — Wilson hexanies, two North Indian ragas, a 19-tone Narushima scale, harmonic
dyads and triads. Until now the plugin played every one of them in 12 ET.

**Decision.**
1. **`s1plugin::TuningLibrary` is the model, with no JUCE in it** — a port of the Mac's `Tunings`,
   `Tuning` and `TuningBank` operation for operation: three banks (Curated, User, "Hexanies With
   Proportional Triads"), the sort that strips 12 ET and puts it back at row 0 of the two banks
   that carry it, `nameForCell` and `encoding` (two tunings are the same tuning when name and
   encoding match), selection, the user bank, and Scala import through the engine's own parser.
   The 194 tunings are NOT rebuilt: they are already `s1::factoryTunings()`.
2. **`tunings_v1.json`, the Mac app's own format and file name, in the folder ABOVE the banks.**
   Not beside them: `PresetLibrary::userBanks` reads every `.json` there as a bank and would have
   listed the tunings file as one — the same trap `banks.order` avoided in ADR-086.
   One key is ours: `isSelected` on a bank, because upstream keeps the chosen bank in AppSettings,
   which a plugin has none of. Swift's synthesised decoder ignores keys it does not know.
3. **A preset's tuning is applied when it is loaded**, as `PresetDataManager` does under
   `AppSettings.saveTuningWithPreset` — which is **true** on the Mac, so it is the default here.
   A preset with no tuning of its own puts 12 ET back. `setSavesTuningWithPreset(false)` turns the
   whole business off. A sound saved now names the tuning it is actually in.
4. **The tuning library follows the banks' folder**, and is made only when something asks for a
   preset or opens the card. That is a safety property, not a convenience: every test that can
   reach a bank must already redirect the preset library, because the real folder is the owner's
   (ADR-036), and this cannot be forgotten separately.
5. **A4 is live here, and inert on the Mac.** `frequencyA4` is one of the 150 parameters; the
   kernel's own comment says "special case for updating the tuning table based on frequency at A4"
   and then only truncates the value — **nothing in the engine reads it**, on the Mac either
   (`Sources/S1Engine/PORTING.md`: "`frequencyA4` is stored and read by nothing"). Here it moves
   the table's reference, by the inverse of TuneUp's own arithmetic
   (`middleC = A4 × 2^(-9/12)`), so the master-tuning knob does what it says.
   **Decided and reported, not asked.** What it costs: **five of the 695 factory presets ask for an
   A4 that is not 440** — "BB Synth Won Sign-off" (410), "JEC Rainbow Dome Synthi" (434), "JEC Soft
   iVCS3" (432), "JEC Slow Lesley" (434), "Let's Play" (439) — and those five now play at the pitch
   they ask for, where the Mac plays them at 440. The other 690 are unaffected.
   **The goldens cannot move**: the change is in the plugin's tuning model, not in the engine, and
   the Mac products are untouched (their A4 stays inert until the owner says otherwise).
6. **The card is `s1ui::TuningsPanel`** (700 × 560, over the sections): the banks, the tunings of
   the chosen bank with their note counts, the pitch wheel as a horagram — every degree at its
   place round the octave, hue BY that place, which is `Tunings.color(forPitch:)` — the
   master-tuning knob, and Reset / Random / Import a scale / Delete. It is a view: every operation
   is the model's. **frequencyA4 has a control at last** — it was one of the 26 the desktop layout
   gives none (ADR-083), and the editor now builds 126 parameter controls with the card open.
7. **Left out on purpose:** TuneUp, Wilsonic and D1 — they hand a tuning to another iOS app by
   URL, which ADR-056's scope does not rebuild.

**Tested.** `PluginTuningsTests` (58 checks, in a folder of its own): the three banks under the
Mac's names; 12 ET at row 0 of Curated and User and absent from the hexany bank; `nameForCell`'s
padding and `encoding`'s indifference to order and octave; the 128 frequencies (note 69 at 440,
middle C at 261.6255653006, a semitone at 100 cents); A4 432 moving the WHOLE table and not just
the As; selection surviving a second library on the same folder, in the folder above the banks and
not in it; the user bank refusing to lose 12 ET, taking a tuning once however often it is set,
deleting and reordering; a Scala file read and nonsense refused; **the eleven microtonal presets
each leaving the kernel in a scale of its own note count, under its own name, with all 128
frequencies the scale's and not 12 ET's**; a 12 ET preset putting it back; the switch; a saved
sound carrying its tuning into another instance. `PluginEditorTests` adds the card (80 checks in
all now). `EditorSnapshot --tunings` paints it for both skins.

**And it is heard, not just tabled.** Two keys are sounded and their interval measured from the
audio: 100 cents in 12 ET, and with "5 Harmonic Series: Pentad" under the same sound, 315 cents —
key 61 measured at **313.952 Hz against the scale's 313.951**. A4 at 432 puts the same key 31.8
cents flat of where 440 puts it.

**Three things the measurements taught, each after a check failed.**
- **An interval is measurable; a pitch is not.** The first version asked for absolute frequencies
  and got nonsense, because a preset is free to sound an octave below the key.
- **Not with any sound, though.** Measuring the interval under the microtonal PRESET still failed:
  "JEC Digiharp" runs two detuned oscillators, so autocorrelation reads the blend — 292 cents where
  its scale says 315. The scale is applied to the shipped Init instead, and that the eleven presets
  each put their own scale in the kernel is checked exactly, against all 128 frequencies.
- **Autocorrelation locks to the octave below**, and a window at the start of a note catches the
  glide. The measure takes the shortest tall peak, 0.6 s into the note.

**Revert-checked.** Stop applying a preset's tuning and four checks fail, the eleven-preset
acceptance among them. Stop A4 moving the table and four more fail, including the heard one.

**Verification, 2026-09-20.** macOS — 37 of 37 CTest tests (the goldens bit-exact; new:
`PluginTunings`, and the two `EditorSnapshotTunings…`), Steinberg's validator 537 of 537, pluginval
strictness 10 `SUCCESS`. Linux arm64 in Docker — see STATE.md. No Mac product source, Swift or
specification change, so no Xcode run. **Windows: owed.**

## ADR-088 — The skins in the window, a typeface that ships, and the cabinet made whole (X3-6)

**Date:** 2026-09-20 · **Status:** Accepted · **X3-6** · Follows ADR-084 (the kit and its open
typeface question), ADR-085 (the editor; Settings), ADR-061 (the joystick), ADR-059/064 (Cabinet),
ADR-083 (the specification is measured, never typed)

**Context.** X3-6 is the plan's "Studio + Cabinet skins, Cabinet the default". Three more things
were booked into it by the owner's own look at X3-3 — *"the joystick is missing from the arcade
game and the x/y pads don't do the starfield effect"* — plus the CRT frame Cabinet's pads lacked.
And ADR-084's open question, the typeface, was answered on 2026-09-20: **Barlow Condensed, yes.**

**Decision.**
1. **The typeface ships.** Three weights of Barlow Condensed (SIL OFL 1.1) are linked into the
   plugin and used wherever the system has no Avenir Next Condensed — everywhere but macOS, which
   keeps the Mac's own face. The old fallback squeezed the default sans to 0.82 of its width; this
   face is condensed, so a label is its own shape. The licence travels with the files and is in
   NOTICE.md. `Style::preferLinkedTypeface(true)` forces it, which is how a test on macOS sees
   what Windows sees, and `EditorSnapshot --linked-face` draws it.
   **What a typeface has to satisfy is not "it loads"**: every one of the specification's 33
   labels, and every section title, still fits the frame the Mac measured for it.
2. **The skin is chosen in the window.** `applySkin` re-dresses in place — every control, plot,
   pad, item and the backdrop made again from the specification, at the same size, with the cards
   torn down first because they hold the style. No new editor; the sound is not touched. The
   choice is kept in `interface.json` beside the banks, so the standalone and the VST3 open in the
   same skin, as the Mac keeps its own in preferences.
3. **Settings is a real card**, as ADR-085 said it would be at X3-6: a button per skin with the
   one in use lit, X3-5's "a preset carries its own tuning", and the list of all 150 parameters as
   one entry in it rather than the whole of Settings.
4. **The cabinet has its stick back.** The painting ships with the joystick cut OUT of it
   (`generate.py` lifts it and fills the hole from the console beside it), so a window that does
   not draw the two sprites shows an empty console — which is exactly what the owner saw. The
   sprites are linked in, and **their boxes are MEASURED, not typed**: the Swift writer now emits
   `template.joystick` (ball box, rod box, pivot, reach, in the painting's own pixels) and
   `S1LayoutSpec` reads it (ADR-083's rule).
   **It is live, as on the Mac** (ADR-061): the rod turns about its socket, the ball slides 7
   painting pixels up for a push and 8 down for a pull, nothing stretches, and letting go springs
   it back. Up is the mod wheel, sideways bends the pitch. It owns no parameter: the wheel goes
   through a new interface path on the processor (an atomic the next block applies through the
   same call CC 1 takes — the message thread never touches the kernel), and the bend through the
   `pitchbend` host parameter. **Upstream's 15% dead zone is the PITCH's, not the picture's**: a
   small lean moves the stick and not the note.
5. **The pads throw their starfield**, upstream's `CAEmitterCell` drawn rather than animated:
   birth rate 80 a second, lifetime 1.70 s, velocity 190 ± 60, the full circle, a spark growing
   from 0.05, additive — and **from the pad's CENTRE, which is where the Mac's emitter sits**, not
   from the touch. On while the pad is held, off when it is let go, which is when the clock runs.
   **Amended 2026-09-21, at the owner's word, in the JUCE plugin only:** "barely visible … a little
   bolder with smaller particles", "let the focus follow the cursor", and the target at half its
   size. The motion is still upstream's; the look is small bright sparks (one to three points, a
   hot core, nearly opaque while young), **each leaving from where the touch was when it was
   born**, so the field streams behind the cursor — the cursor rather than the target, which on a
   tempo-synced pad steps between note values. `Style::PadTouch`, `kPadTargetScale`. The random
   draws now happen for every star whether or not it is drawn: before, a skipped star consumed
   none, so every heading shifted as the hold went on. The Mac keeps its centre and its discs.
6. **Cabinet's pads are framed as screens** (`S1CRTFrame`): a one-point border in the skin's frame
   accent at 0.9, its glow at 0.45 and radius 6, and scanlines — one dark line every three points
   at 16% black. The frame accent was already in the specification (`#2ee8ff` for Cabinet, none
   for Studio), so this needed no new measurement.
7. **The red power buttons are NOT in this task.** ADR-062's greyscale cycle — fifteen zones,
   every held colour swapped and restored, a shuffled eight-second blink — is a task's worth on
   its own. The owner agreed, 2026-09-20.

**Tested.** `PluginTypefaceTests` (8 checks) — the three weights are the linked face and not the
system's, no squeeze, and every label and section title fits. `PluginControlsKitTests` gains the
bezel and the starfield (13 more): the frame draws its line and **leaves what it frames alone**,
Studio gets none, a pad that is not held throws nothing, a held one throws more the longer it is
held, and the burst's mean distance from the middle grows — 6.2 points at 0.05 s, 35.2 at 0.35.
`PluginEditorTests` (105 checks now) adds the joystick and the skin: the stick is on the
specification's own box and inside the window; a push moves the mod wheel and the kernel hears it
at the next block; a lean bends the pitch; a lean inside the dead zone bends nothing **and still
draws the stick leaning**; letting go centres the bend; Studio has no stick; the skin changes in
place with every control rebuilt, the window still opaque everywhere, and the choice remembered.

**Revert-checked, and one of the two found a check that could not fail.**
- Let the bezel's glow paint where a layer shadow would not, and "no glow spilled inside it"
  fails at 1,200 pixels. **Found by eye first**: the first cut tinted the pads it was framing,
  because a `CALayer` shadow falls behind opaque content and a JUCE drop shadow is painted.
- Apply the dead zone to the picture as well as to the pitch, and the first version of that check
  **passed** — it read back the number it had just written. It measures the PIXELS now, and fails
  at 0 changed. The fourth such check in five tasks (ADR-084, ADR-085, ADR-086).

**And Linux found a third thing, which macOS could not.** `PluginTypefaceTests` failed there with
two labels wider than their frames, the status-bar hint worst. The hint's specification text holds
an Option sign and a non-breaking hyphen — glyphs the Mac's own face has, Barlow does not, and a
Docker image with almost no fonts substitutes with something wider still. **The editor had always
replaced those two before drawing**; the test was measuring the raw text, which the interface never
paints. The substitution is `Style::drawable` now, in one place, used by both.

**And then Windows failed on it, because I put the bug back.** The owner's run of 5028b6e did not
build: two init-captures inside nested lambdas in the new Settings card — **the very form their own
fix had removed at X3-5, and which had been written into CLAUDE.md's gotchas hours earlier in the
same session.** Reading a rule is not obeying it, so the form is now banned outright and checked
mechanically: a `juce::Component::SafePointer` is never made in a capture list, it is a named local
captured by copy, and `ctest -R NoNestedInitCapture` greps every UI source for it on all three
operating systems. All six sites were converted, not only the two that break, so no judgement about
nesting is needed. Revert-checked: putting one back fails the check and names the file and line.

**And the owner asked for the Windows script to stop lying.** Twice it reported `ok` for the tests
and the validators after the build had failed, because the previous run's test programs and `.vst3`
were still on disk — a stale pass, which is worse than no result. Each step now names what it needs;
a step whose ground did not pass reports `not run` and its body never executes, and a skipped step
blocks its own dependants in turn. Verified in a real PowerShell before it was sent: the failing
path reports one `FAIL` and four `not run`, the passing path still runs everything.

**And the owner found one by using it**, which no test had: leaned hard right, the ball was cut off
against the console — *"the joystick becomes obscured by the yellow buttons to its right"*. **JUCE
clips a component's painting to its bounds and UIKit does not**, so on the Mac the sprite draws
outside its view and here it met the edge of `reach`. The component is wider than the grab area now
(24 painting pixels a side, `Joystick::kSwing`) and `hitTest` keeps the clicks inside `reach`, so
nothing painted beside the stick loses its own. Checked by comparing the leaned picture with the
upright one: the ball reaches past the grab area's edge and stops short of the box's.
Revert-checked at a margin of 0, where it is flush against the edge — 0 pixels clear.

**Verification, 2026-09-20.** macOS — 39 of 39 CTest tests, Steinberg's validator 537 of 537,
pluginval strictness 10 `SUCCESS`, and **343 Xcode tests green** (the Swift writer changed, so the
specification was regenerated and its check-mode test had to agree). Linux arm64 in Docker — see
STATE.md. **Windows: owed.**

## ADR-089 — The window scales: one transform on a design-size stage, letterboxed (X3-7)

**Date:** 2026-09-21 · **Status:** Accepted · **X3-7** · Follows ADR-083 (the layout is measured, in
design points), ADR-085 (the editor was built at the design size and not resizable), ADR-019 (the
Mac's `S1ScalingContainer`, which settled the same question for the Mac app in 2026-09)

**Context.** Everything in the interface sits where a Swift test measured it on the Mac: 1440 × 900
design points, 144 frames a skin, read from a generated file. There is no adaptive layout underneath
and there was never meant to be one — a stretch would strand every control and open gaps between
sections, which is what hard requirement 1 forbids. But a plugin does not choose its window: a host
gives it one, a 1280 × 800 laptop has no room for 1440 × 900 at all, and pluginval at strictness 10
resizes the editor to sizes nobody would pick.

**Decision.**
1. **Everything is a child of one `stage` component, which is always the design size.** The window
   scales it with a single `AffineTransform`, uniform and centred. Nothing is re-laid out, no frame
   is recomputed, and every control, card, label and hit area stays in the design points the
   specification measured — the Mac's answer (ADR-019) in JUCE's terms. JUCE's own documentation
   asks for exactly this shape: an editor must not carry a transform of its own, because the host
   sets one for its scale factor, so *"put the component you want to transform in a child of the
   editor and transform that instead"*.
2. **The scale is the SMALLER of width/design and height/design**, so the whole interface always
   fits and is never cropped, whatever shape the window is. What is left over is painted in the
   skin's own window colour, centred — a letterbox, not a stretch.
3. **The window resizes between 0.75× and 1.5×**, the plan's range, with the design's aspect ratio
   fixed in the constrainer so a drag on one edge takes the other with it, and a bottom-right corner
   resizer for hosts that do not draw their own. `spec.minimumSize` is the LAYOUT's minimum — the
   design size itself — not the window's: below 1× the interface is drawn smaller, not reflowed.
   A host may still hand the editor any size at all, and `resized` fits the interface into it.
4. **Nothing remembers the size here.** A host stores its editor's size in its session and JUCE's
   standalone window restores its own, so a third keeper would only give them something to disagree
   with.

**What the measurements say** (`PluginEditorTests`, 14 new checks, no window): the limits are 1080 ×
675 to 2160 × 1350 and a drag to 2000 × 900 comes back at the design's 1.6 ratio; at 0.75×, 1×,
1.25× and 1.5× every one of the 125 controls is drawn on its measured frame times the scale, centred
— worst error 0.75 of a point, which is the rounding of a half-pixel offset; **the plan's acceptance,
a 1280 × 800 laptop, shows the whole interface at 0.85× with nothing cropped**; the preset browser's
card and the Tunings card scale with it and stay inside the window; a window of another shape
(1600 × 675) scales by its tighter side and is centred to within a point, with the margin on either
side painted in the window's colour.

**Two checks that could not fail, found by reverting** — the fifth and sixth in seven tasks:
- **A click is not a drawing.** The first hit-test check asked the window what was under each
  control's centre and got nothing at any scale, because **a component is not visible until
  something shows it** and an invisible one answers no clicks: the check passed at 0.75× and 1.5×
  by comparing 0 with 0. With `setVisible(true)` — what a host does — all 125 controls answer at
  every scale, and the count is required to be the same as 1×'s AND over 100.
- **An opaque component's snapshot is always opaque.** The letterbox check counted pixels with an
  alpha of 255 and passed with the fill taken out: `createComponentSnapshot` makes an RGB image for
  an opaque component, and RGB has no alpha to be 0. It reads the margin's COLOUR now — Cabinet's
  window is `#08070d`, which is not the black an unpainted image leaves. Reverted: six of six
  sample points fail.

**Reverted properly: with the transform removed, eleven checks fail** — cropping (55 controls
outside the window), the geometry at 0.75×, 1.25× and 1.5×, the clicks, the centring, the letterbox,
both cards, and the border at 1.5× (blue 13, where the interface is not drawn at all).

**A thing worth knowing, from a revert that did NOT fail: in JUCE, caching does not cost sharpness.**
The worry was the backdrop, which is one buffered image holding every panel, bar and section title:
a buffer kept at 1× and scaled up would blur the lot. Buffering the WHOLE stage as a revert changed
nothing — `StandardCachedComponentImage` renders at the graphics context's physical pixel scale,
which includes the transforms above it, so a cached component is redrawn when the scale it is shown
at changes.

**Amended the same day, by the owner's Windows run — and the first crispness check was measuring the
platform, not this code.** It compared the gradient energy of a native 1.5× render with a 1× render
stretched into the same size: 1.31× on macOS, and 0.74× when the transform was taken away, so it
discriminated here. On Windows it read **1.07 against a threshold of 1.15, and failed**, and the
owner settled what it meant before reporting it: with the backdrop's buffering switched OFF the
ratio was 1.0725, against 1.0711 with it on. **Nothing is cached and stretched there; the
platforms' resamplers differ.** A baseline made by the platform's own `Image::rescaled` is not a
constant, so a threshold fitted on one renderer cannot hold on another.

**What replaced it is ADR-084's measurement, taken through the window's transform** — the owner's
own suggestion, and the technique already proven on all three systems. The Transpose stepper's
one-point border is a hard cyan edge (`#22A6B8`) over a near-black well, and its top sits at design
y 868 — 1302.0 at 1.5×, a whole pixel — where it must still read its own colour. **This check was
written twice.** The first version compared the border at 1.5× with the same border at 1×, and a
half-pixel offset on the transform moved BOTH: `0E3540` in each, one level apart, passing. **A
comparison whose two sides share the fault cannot see it** — the same lesson as a check that reads
back what it just wrote, one step removed. The colour is read absolutely now: blue 185 with the
interface on the pixel grid, 62 half a pixel off. That is also what makes the `std::floor` on the
centring offset a decision rather than a detail: the interface lands on whole pixels at every scale.

**Verification, 2026-09-21.** macOS — 40 of 40 CTest tests (new: `EditorSnapshotLaptop`, the 0.85×
window painted so every OS is known to draw a scaled one), Steinberg's validator and pluginval
strictness 10 with its editor tests on a resizable window. Linux arm64 in Docker — see STATE.md.
Windows — 39 of 39 CTest, validator 537/537, pluginval 10 `SUCCESS` at `a9d5b6a`, the border
reading its own colour under a third renderer. No Mac product source, no Swift and no specification
change: the Xcode suite was not needed.

## ADR-090 — The keyboard drawer: the interface plays MIDI, and the router is the only route (X3-8)

**Date:** 2026-09-21 · **Status:** Accepted · **X3-8** · Follows ADR-031 (`S1HostMIDI`: the host's
route is the only route), ADR-039 (the Mac's keyboard strip, and the window that does NOT resize
for it), ADR-045 (the desktop layout has no keyboard), ADR-089 (the window scales)

**Context.** The play bar has had three controls that said "comes with X3-8" since X3-3 — Hold,
Wheels and the octave — and the status bar has promised musical typing for as long. The plan asks
for the keyboard itself: *"the on-screen keyboard slides in on a shortcut, as the design's ⌘K
proposed"*, with the acceptance that its notes *"go through the same path as host MIDI and sound
identical"*, closed by default and remembered per instance.

Two of the owner's own decisions shaped this. **The desktop layout has no keyboard** (ADR-045) —
the Mac draws one only in the classic layout — so there is nothing to copy the placement from.
And **ADR-039 reverted window-resizing for the keyboard** after they tried it in Logic: Show
"only elongates the virtual keyboard a bit, and doesn't add much value".

**Decision.**
1. **The interface plays MIDI.** `sendMIDIFromInterface(status, data1, data2)` puts a message in a
   fixed lock-free ring that the audio thread drains at the top of the next block, into the same
   event array the host's MIDI goes into, **before** it. So a key in the drawer is not "like" a
   host note, it **is** one: the octave shift, white keys, hold, mono, the arpeggiator and every
   held-key bookkeeping happen once, in the router, where they already had tests. Nothing
   allocates and nothing locks; a full queue drops and says so.
2. **The drawer overlays, and stops above the play bar.** It does not resize the window — the
   owner settled that once already (ADR-039), and under ADR-089 a taller interface in a window a
   host refuses to grow would SHRINK everything. Hold, Octave, Transpose and Wheels stay visible
   beneath the keys, which is where they belong while playing. Four octaves at the Mac's own
   proportions (its keyboard is 898 × 88 in a 1024-point window; this is 1424 × 124 in a 1440-point
   one). Command-K opens and closes it, as the design proposed.
3. **`s1plugin::Keybed` is upstream's geometry, with no JUCE in it** (ADR-086's pattern): an octave
   is `width/octaves − width/(octaves² × 7)` wide, a black key is 55% of the length
   (`topKeyHeightRatio`) and two of the black band's **28 slots** plus four points wide, and
   hit-testing is `noteFromTouchLocation12ET` — a y threshold at 55%, then integer division into a
   7-slot or 28-slot table. It is a touch model, not a piano's, and it is kept because it is the
   only on-screen keyboard either product has.
   **One PORT FIX:** upstream's own arithmetic sounds a **D** in the sliver of the C that closes
   the keyboard, because the octave it computes there is past the last one. That C sounds a C here.
4. **The octave control moves what the keys SOUND, not where they are.** The router adds the shift
   to every note that reaches it, so the drawer sends the note it draws and the shift is applied
   once. The keys' labels say what they sound, and a note the router is holding lights the key
   below it by the shift. **This was wrong first** — see below.
5. **Hold is the router's latch** (`KeyboardView.holdMode`, already in the engine and already
   saved per instance): a note-off is ignored while it is on, and switching it off releases every
   key. The button lights from the router rather than remembering its own state, so a host's
   automation or a second window cannot disagree with it.
6. **Wheels is upstream's popover**: what the mod wheel moves (Cutoff / LFO 1 / LFO 2) and how far
   the pitch wheel bends (`pitchbendMinSemitones`, `pitchbendMaxSemitones`) — two of the 26
   parameters the desktop layout gives no control of their own (ADR-083), which now have one.
7. **Musical typing is `Manager+ComputerKeyboard`'s map**, which the status bar has been promising:
   A–K and W/E/T/Y/U/O/P/' play C to F♯ an octave and a half up, Z/X move the octave (the same one
   the stepper moves — the Mac learned that lesson too), C/V move the velocity by 16. A key
   carrying a modifier is a menu's, not a note's, or Command-S would play a D; a repeat does not
   retrigger; and the octave keys release what is sounding first, because those notes belong to the
   octave they were played in.
8. **The drawer is remembered per instance**, in the session's state (`window.keyboardShown`), not
   in `interface.json` — two instances can differ, as their tunings can. A state written before it
   existed does not name it, and what a state does not name stays as it was: a fresh instance is
   closed, so an old session opens closed.

**The acceptance is measured as audio.** `PluginKeyboardTests` plays the same note into two
identical plugins — once through `sendMIDIFromInterface`, once as the host's own MIDI — and
compares 12,288 samples: **worst difference exactly 0**. Reverted (the interface's events delivered
one sample later) it fails at 1.03e-4.

**A bug the tests did not catch and a picture did.** The first version moved the drawer's keys with
the octave control *and* let the router shift the note — so a key sounded **two** octaves up, not
one. Every check passed: they asked where the keys were, not what they sounded. The render showed
the keyboard relabelled while the shift was also being applied underneath. The check that exists
now presses the key that sounded middle C and requires the note to be 72; reverted, it reads 84.
**Ask what a control SOUNDS, not where it sits** — the same lesson as ADR-085's dependent knobs,
which a side-by-side found and no test had.

**Verification, 2026-09-21.** macOS — 43 of 43 CTest tests (new: `PluginKeyboard`, 29 checks, and
the two `EditorSnapshotKeyboard…`; `PluginEditor` is 147 now), Steinberg's validator and pluginval
strictness 10. Revert-checked three times: the double shift (84 where it should be 72), the
acceptance (one sample late), and the state's fixture, which was rewritten for the new field — four
lines, purely additive. Linux arm64 in Docker — see STATE.md. **Windows: owed for this commit.**
No Mac product source, no Swift and no specification change: the Xcode suite was not needed.

---

## ADR-092 — The X3 gate: the Mac products become "Arcade Ruins Classic"; one repository, two public faces

**Date:** 2026-09-21 · **Status:** accepted (the owner's decision; resolves ADR-055's deferral)

**Context.** ADR-055 kept the Catalyst app and AUv3 through X2 and left their future to the X3
gate. With X3 built, the owner: "I'd like to keep that since it has a unique interface, but maybe
rename it so it's distinct from the new version? Or maybe we can create a new repository for
Arcade Ruins VST or something to show that it's a cross platform product."

**Decision.**
1. **The Mac products stay, as "Arcade Ruins Classic"** — the edition with the iPad's interface.
   The JUCE plugin takes the plain name "Arcade Ruins". **The NAME only:** `CFBundleDisplayName`
   (app and extension, and all eight localisations), the AU component's name and description, and
   the four alerts that name the app. **Unchanged:** `aumu`/`ruin`/`BP03` (a host stores the codes,
   not the name — ADR-029 — so every session still opens), both bundle identifiers, the App Group,
   the bundle file names (`ArcadeRuins.app`, which every script addresses), `~/Music/Arcade Ruins`,
   the wordmark (the owner's artwork, and the family's name), and "About Arcade Ruins" (it is an
   item of the layout specification the JUCE interface is built from).
2. **The repository is NOT split.** One engine is compiled into both products; the plugin's layout
   is measured from the Mac's by a Swift test (ADR-083); the goldens have two readers (ADR-071);
   the router is held to the Mac's notes (ADR-075). Each of those links has caught a real fault.
3. ~~**Two PUBLIC repositories instead, at X4**~~ — **overturned by the owner on 2026-09-22, before
   anything was built: ONE public repository carries both products.** See ADR-098.
4. **The JUCE build will ship an AU under a code of its own** (ADR-058's deferral) — not one that
   differs from `ruin` by case alone. The code is still to be chosen, and like `ruin` it is
   permanent from the first release.

**Found on the way.** The Japanese and Turkish `InfoPlist.strings` still said `シンセ1` and
`Synth Bir` — upstream's translations of "Synth One", missed by ADR-029, which fixed the six that
said it in English. All eight carry the new name.

**Left open.** Whether Classic should one day show ONLY the classic interface (it also holds the
desktop layout and skins the JUCE plugin reproduces). Not now: the plugin's layout is generated
from that code. And the README, release notes and the public page still say "Arcade Ruins" of
the Mac product — X4-4 has rewritten those (ADR-098).

**Verification.** The Xcode suite 343/343; `Scripts/build.sh` signed build, and the names and
codes read off the built bundles (`PlistBuddy`). Not installed, and `auval` not run:
`Scripts/validate-au.sh` replaces `/Applications/ArcadeRuins.app`, which is the owner's to ask for.

---

## ADR-093 — The JUCE build ships an AU: `aumu` / `ArRu` / `BP03`, and what auval found

**Date:** 2026-09-21 · **Status:** accepted (the owner chose the code; resolves ADR-058's deferral)

**Context.** ADR-092 put an AU in the JUCE build. ADR-058 had picked `Ruin` as the plugin code
knowing that "in JUCE, one code serves every format" — the AU's subtype AND half of the VST3
class ID — and deferred the AU. `Ruin` and the Classic AUv3's `ruin` differ by case alone.

**Decision.**
1. **`PLUGIN_CODE ArRu`** (the owner: "ArRu is fine"), `FORMATS VST3 AU Standalone` on Apple,
   VST3 and Standalone elsewhere. **The VST3's identity changed with it** —
   class ID `ABCDEF019182FAEB4250303341725275`, controller `ABCDEF011234ABCD4250303341725275`
   (the last eight digits are the code) — free because nothing from the JUCE build has been
   released; a session saved against a development build of the VST3 will not find it. **From
   the first release this code is as permanent as `ruin`.**
2. **The two AUs sit side by side:** "BadPackets: Arcade Ruins" (`ArRu`, a `.component` in
   `~/Library/Audio/Plug-Ins/Components`) and "BadPackets: Arcade Ruins Classic" (`ruin`, the
   AUv3 in the Catalyst app). Different codes, different kinds; neither knows of the other.
3. **`Scripts/validate-plugin.sh --au`** installs the component for this user, runs Apple's
   `auval` and pluginval strictness 10 on it. Opt-in, because it installs. Logic will not load an
   AU that fails `auval`, so this stage is the AU's gate on the Mac.

**What auval found — in every format, not just the AU.** One failure: *"Parameter did not retain
set value when Initialized"*, Seq Step Length, 0.308594 written and 0.249022 read back. auval
sets a parameter, uninitialises, initialises **with no audio between**, and reads. The engine
snaps a tempo-related value to its nearest note value, and `prepareToPlay` told the host so at
once and silently (X2-2's "quietly: the host asked for this state"). To a host that is a value
changing under it for no reason it can see. **`prepareToPlay` no longer reports**: `engineValues`
keeps what was WRITTEN, so the first rendered block sees the difference and reports it exactly as
it reports every later snap — once, with a notification, no gesture. pluginval at strictness 10
and Steinberg's validator had both passed this for a week; neither re-initialises without
rendering. Five "did not retain default value when set" WARNINGS remain (two envelope times, the
LFO rates): float rounding through the taper and the same snapping, and auval passes with them.

**Verification.** `auval -v aumu ArRu BP03`: AU VALIDATION SUCCEEDED; pluginval 10 on the AU:
SUCCESS. `PluginParameters` has the check in auval's own numbers, so Linux and Windows hold it
too (reverted: 0.249022 where 0.308594 should be). macOS 43/43; VST3 validator 537/537.

---

## ADR-094 — X4-1 / X4-2: how "Arcade Ruins" is packaged on three systems

**Date:** 2026-09-21 · **Status:** accepted; the macOS package and the Windows installer await the owner's certificates

**Decision.**
- **macOS — `Scripts/release-plugin.sh`:** ONE installer package over three component packages —
  the VST3 (`/Library/Audio/Plug-Ins/VST3`), the AU (`…/Components`) and the standalone
  (`/Applications`), each a choice. **Universal** (arm64 + x86_64, macOS 11.0), every bundle
  signed Developer ID Application with the hardened runtime and a secure timestamp, no
  entitlements. The PACKAGE needs a **Developer ID Installer** certificate — a different one,
  which the owner's keychain does not have yet; the script says so before building.
  Notarisation is `release.sh`'s no-wait / poll / resume flow (ADR-053), then stapled.
  **`BundleIsRelocatable` false on every component**: by default the installer finds a bundle
  with the same identifier ANYWHERE on the disk — a build folder — and installs there.
  `BundleIsVersionChecked` false, so an older release can be put back. `uninstall.sh` beside it
  removes the three and their receipts and leaves `~/Library/Application Support/BadPackets`.
  The Catalyst products keep `Scripts/release.sh`.
- **Linux — `Scripts/release-linux.sh`:** a tarball (VST3, standalone, `install.sh` to `~/.vst3`
  and `~/.local/bin` with a menu entry, `uninstall.sh`, LICENSE, NOTICE) built in Docker on
  **Ubuntu 22.04, not the validation image's 24.04**: a binary needs the glibc it was built
  against or newer, so 24.04 would shut out everything of 22.04's age. Its README states the
  glibc it needs and the libraries it links, read from the binaries. Not signed; the checksum
  is the check. aarch64 here natively, x86-64 by `--x86` (emulated, slow — and worth the wait for more than the
  artefact: it renders the goldens with no fused multiply-add, ADR-071's other arithmetic).
- **Windows — `Scripts\release-windows.ps1` + `Scripts\windows\ArcadeRuins.iss`** (Inno Setup 6), on
  the owner's machine: the VST3 to `Common Files\VST3`, the standalone to Program Files, each a
  choice. **The release build links the C runtime in** (`CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`):
  MSVC's default needs the Visual C++ Redistributable, which a developer's machine has and a
  musician's may not, and a plugin that cannot find `VCRUNTIME140.dll` fails silently — the host
  never lists it. The script reads the DLL's imports back and fails if the runtime is still
  among them, and runs every CTest test on THOSE binaries. Authenticode when a certificate
  thumbprint is given (the owner buys it, X4-2). The `AppId` GUID in the `.iss` is permanent.
- **Every release script runs the whole test suite on the binaries it packages** — the plan's
  "goldens green on the release commit" — and refuses a dirty working tree.

**Found on the way.** The universal build was the first time anything here compiled for an Intel
Mac: `GoldenHarness` used `FE_DFL_DISABLE_DENORMS_ENV`, which is Apple Silicon's name —
Intel's is `FE_DFL_DISABLE_SSE_DENORMS_ENV`. **And the Intel half cannot be RUN here: this Mac has
no Rosetta** (`arch -x86_64`: "Bad CPU type"). It compiles, links and is signed; nobody has
heard it. An Intel Mac, or Rosetta installed by the owner, is X4-3's.

**Verification, 2026-09-21.** macOS: `ALLOW_UNSIGNED_PKG=1 NOTARISE=0` — 43/43 on the universal
build (goldens bit-exact at the 11.0 deployment target), the package expanded and read back:
three components, the right locations, `relocatable="false"`, each bundle's signature valid
with `flags=runtime` and a timestamp, both halves in each. NOT installed, NOT notarised (no
Installer certificate). **Then, once the owner made the Developer ID Installer certificate
(2026-09-21): the whole run, end to end — signed, submitted, `Accepted` in 60 seconds, stapled,
and `spctl -a -t install` says `accepted / source=Notarized Developer ID`.**
`ArcadeRuins-0.5.0-macOS.pkg`, 47 MB, SHA-256 beside it. Linux (aarch64): 42/42 under GCC 11 / glibc 2.35, goldens included; the
tarball then taken to a CLEAN Debian 12 container (another distribution, glibc 2.36 — older than
the validation image's) with only libasound2, libfreetype6 and libfontconfig1 added: it
installs, `ldd` finds nothing missing in either binary, the plugin loads and exports
`GetPluginFactory`, and after `uninstall.sh` 0 files are left. Windows: written, not run.

---

## ADR-095 — Two version lines, and what ships untested

**Date:** 2026-09-21 · **Status:** accepted (the owner's decisions)

**Context.** Both products were numbered 0.5.0 — one from `CMakeLists.txt`, one from
`project.yml` — so the macOS package came out as `ArcadeRuins-0.5.0-macOS.pkg` beside Classic's
released `ArcadeRuins-0.5.0-macOS.zip`: two different instruments, one letter apart.

**Decision.** The owner: *"The classic version should stay at 0.5 and the new version should be
1.0."* **Arcade Ruins is 1.0.0** and numbers itself from `CMakeLists.txt`; **Classic keeps 0.5.x**
in `project.yml`. They are separate lines and will not be kept in step: the artefacts, the AU's
version code, the state file's `plugin` field and both release scripts all read their own.

**And the Intel half ships without being tried.** The owner: *"I'm not worried about the
intel-half part, I'll let other users test that out for me."* So the universal build's **Intel
half is released untested** — no Intel Mac here, and this one has no Rosetta (ADR-094). It is
stated plainly in the release notes and the README rather than left to be discovered.

**Whether Windows ships unsigned was left open here and decided in ADR-097: it ships unsigned.**

**Consequences.** A release touches two numbers, never one. `Tests/Plugin/Fixtures/state-v1.json`
carries `"plugin": "0.5.0"` and always will — `PluginStateTests` erases the field before
comparing, deliberately, so a version bump is not a fixture rewrite.

---

## ADR-096 — Captions are drawn FITTED, because `drawText` curtails and every renderer curtails differently

**Date:** 2026-09-21 · **Status:** accepted

**Context.** The owner's Windows screenshot of 1.0.0 (2026-09-21, the standalone at a window scale
of 1.10) showed **"Pitch Trac"** and **"Transpos"** — each missing its last letter. Linux, rendered
from the same commit, showed both in full, and `PluginTypefaceTests` **passed on Windows**, so
JUCE's own `GlyphArrangement::getStringWidth` there said both fitted the room they were given.

**What is actually happening.** `Graphics::drawText` does not clip — it **curtails**
(`addCurtailedLineOfText`): it deletes the glyphs that do not fit and says nothing. And it does so
with the advances the renderer computes **through the window's transform**, which is not what the
same renderer answers at 1×. So a caption can measure as fitting in a test and lose a letter on
screen at 1.1×, on one platform only. Three measurements pinned it: "Semitones" and "Feedback"
are the same width to the pixel on Windows and Linux (42 and 38 design points), so the typeface
and its metrics are identical; only the two longest captions differ; and the Windows window was
at 1.1035× (1589 × 1023 including its title bar, over a 1440 × 900 stage).

**Decision.** The backdrop draws every caption and label with **`drawFittedText`**, one line, a
minimum horizontal scale of `Style::kCaptionSqueeze` (0.7) — so a renderer that measures wide
**squeezes the text imperceptibly instead of deleting a letter**, at any scale. `kCaptionRoom` is
20 points a side (was 12). Together the tightest caption now needs 55% of its room on this Mac and
a glyph is only dropped past 143%.

**The check follows the fault, not the platform.** `PluginTypefaceTests` measured captions at 1×
only, which is why it passed on Windows. It now measures **at 0.75×, 1×, 1.1× and 1.5× — every
scale the window has** — asserts that each caption could be squeezed into its room rather than cut,
and prints the tightest one with its margin, so each OS's own run reports its real numbers.

**This cannot be verified here.** No Windows machine, and the fault only appears at a scale under
that renderer. The fix is structural — with `drawFittedText` a letter cannot be dropped unless the
text needs 143% of its room — but **the proof is the owner's next Windows screenshot**, and until
then this ADR is reasoning, not evidence. Fourth time a picture found what every check passed:
ADR-085 (the dependent knobs), ADR-090 (the octave), X4-4 (the same captions on Linux), this.

---

## ADR-097 — Windows ships unsigned, and the records keep the cabinet's extras

**Date:** 2026-09-22 · **Status:** accepted (the owner's decisions)

**Windows ships unsigned.** The owner, asked what it costs a person: *"ship Windows unsigned."*
What they will meet, in order — a browser notice that the file is not commonly downloaded;
SmartScreen's *"Windows protected your PC"* screen, whose default button is **Don't run** and which
needs "More info" → "Run anyway"; and a UAC prompt naming an **unknown publisher**, because the
installer writes to Program Files. Managed machines may refuse it outright.

The decision is the cheaper one **because the middle option does not exist**: a standard (OV)
certificate — a few hundred a year, and on a hardware token since 2023 — puts a name on the UAC
prompt but leaves SmartScreen warning until the file earns a download reputation. Only an **EV**
certificate buys a clean first run. So the choice is EV or nothing, and for a personal project
shared for testing it is nothing. The README tells people what they will see and how to get past
it, and the published SHA-256 is what a careful person checks instead. If a certificate is ever
bought, `Scripts\release-windows.ps1` takes its thumbprint and nothing else changes.
**macOS is unaffected** — that package is signed and notarised (ADR-094), and installs silently.

**The cabinet's extras stay in the development records.** The owner, 2026-09-17: *"don't reveal
the easter eggs on Github"*; asked again now that the cross-platform work has filled STATE.md,
`PORT_PLAN.md`, `CLAUDE.md`, the ADR log and `Sources/S1Plugin/README.md` with about 35 mentions
of them: *"Leave the easter eggs."* Nothing had been exported — the public mirror's last export
predates all of it — so this is a choice, not a repair.

**What it rests on:** the source has always been public and undisguised (`S1CabinetJoystick.swift`
names itself), so a reader of the code finds them anyway; the records only make them searchable.
The instruction that stands is about **user-facing** material, and that stays clean:
`docs/private/cabinet-extras.md` is still excluded from the mirror, and the README, the release
notes and the release pages say nothing. A filter over the exported documents was considered and
refused — a rule that silently rewrites prose fails quietly, which is the one thing these records
must not do.

---

## ADR-098 — One public repository, carrying both products

**Date:** 2026-09-22 · **Status:** accepted (the owner's decision; overturns ADR-092's clause 3)

**Context.** ADR-092 planned a second public repository for the cross-platform product, leaving
the existing `badpackets303/ArcadeRuins` as Classic's. Writing X4-4's documentation made the cost
of that plain, and the owner was asked again before any of it was built: *"Let's just do one
repository."*

**Why the earlier plan was wrong.** The existing public repository is already **named**
`ArcadeRuins` and already exports this whole tree, the JUCE plugin included — so a second one
would have been a near-duplicate of the same source, to be kept in step by hand, for the sake of
a name. And the two products are not separable in the way two repositories would imply: one
engine is compiled into both (`Sources/S1Engine`), the plugin's layout is measured from the Mac's
by a Swift test (ADR-083), and the goldens and the MIDI fixture each have two readers. A reader
who had only half of it could not run the tests that hold the halves together.

**Decision.** **One public repository, `badpackets303/ArcadeRuins`, presenting two products** —
Arcade Ruins (Windows, macOS, Linux: VST3, AU, standalone) and Arcade Ruins Classic (the Mac app
and its AUv3). `Scripts/publish-public.sh` is unchanged and there is no second script to write.
The README that X4-4 wrote already does this: a comparison table, one engine, both build routes,
and each product's own download. Releases are distinguished by their tag and their artefacts'
names, which is what the version split (ADR-095) is for.

**Consequences.** Nothing to build, and one thing not to do: the GitHub release page will carry
both products' downloads, so their names must stay unmistakable — `ArcadeRuins-1.0.0-macOS.pkg`
and `ArcadeRuins-0.5.0-macOS.zip` are a `.pkg` and a `.zip` of different products, and the
release notes name each.

---

## ADR-099 — The power cycle plans from where the zones ARE, and a repeated press is ignored

**Date:** 2026-09-22 · **Status:** accepted

**Context.** The owner, using the plugin: *"the red button turns off the colors, but neither of
them turn them back on again."* Every check passed, the model's own tests passed, and pressing the
buttons once each in a test on the real clock worked — 19 zones drained over eight seconds and 19
came back. The report was still right.

**What was wrong — two faults, compounding.** `PowerCycle::isLit` answered `!powered` for any zone
it had not planned, and every zone is planned from the assumption that it starts in the state the
cycle is leaving. That is true of a cycle begun at rest and false of anything else:

1. **A repeated press restarted the eight seconds.** The first zone does not settle for a second,
   so pressing the button shows almost nothing at first — and a person presses again. Each press
   built a new cycle from zero. Pressing "on" once a second left the interface **dark
   indefinitely**: measured, six presses a second apart, 0 of 19 zones lit, and only leaving it
   alone for nine seconds brought it back. This is exactly what the owner met.
2. **Pressing the other button part way through blacked out the half still lit.** Three seconds
   into the drain, 13 zones were still lit; pressing "on" reported every unsettled zone as dark,
   so the interface went black at once and then relit — the button appearing to do the opposite of
   what it says. With fault 1 also in play it did not even recover fully (7 of 19).

**Decision.** A cycle is given **only the zones that still have to change**, which is what ADR-062
said all along ("zones still to change, shuffled"), and `isLit` answers **`powered`** for a zone
nobody planned — it is already where this cycle is going. And `runPower` **ignores a press in the
direction it is already going**, rather than starting again. Pressing the *other* button still
abandons the cycle, as it always did.

**How it was found, and the lesson.** Not by a test — by the owner using it, then by a scratch
program that pressed the real buttons through `mouseDown`/`mouseUp` and watched the zones on the
real clock, printing a line a second. The first two sequences it tried (once each, in order) were
what every existing check already did, and they passed. **The third — pressing a button twice —
failed at once.** Every check of this feature had driven it one press at a time from rest; nobody
had asked what a second press does. The permanent checks now do both sequences, with the injected
clock, and each fails when its half of the fix is removed (18 instead of 19; 0 lit instead of 13).

**Consequences.** The four release artefacts of 1.0.0 predate this and must be built again before
X4-5. Nothing else changes: the power is still a look and nothing else, still unsaved, and the
pixel checks — the zones colourless when cut, off-then-on identical to never darkened — are
untouched and still pass.

