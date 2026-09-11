# Arcade Ruins — Project Context

**Read this file and `STATE.md` before doing anything else.** `STATE.md` is the live status;
this file is the standing rules.

## What this project is

Re-engineering [AudioKit Synth One](https://github.com/AudioKit/AudioKitSynthOne) (iOS/iPadOS,
archived 2022, v1.4.1) into a macOS product shipped as **both** a standalone app and an **AUv3
instrument plugin** (`aumu` / `ruin` / `BP03`) for Logic, Live, GarageBand, Reaper and Bitwig.

**The product is "Arcade Ruins"** (P5-4, ADR-029) — an unofficial port, MIT, not affiliated with
AudioKit. Internal target and module names are deliberately still `SynthOne*`: they are a
provenance signal (ADR-009) and invisible to users. Rebrand at the product-identity level only.
**`Scripts/branding/generate.py` regenerates every branded asset.** The icon is code, not a
hand-drawn PNG. Every wordmark — header, About and mailing-list — is the owner's artwork,
`Scripts/branding/source/Arcade-Ruins.png`, which the script fits to each frame (ADR-029).

**Hard requirements from the owner:**
1. **Preserve the user interface** — 12 storyboard panels, custom knobs, touch pads, keyboard.
2. **Preserve functionality** — same DSP, same 150 parameters, same presets and tunings.
3. Multi-session effort; every session must leave the project resumable.

**Settled:** Mac Catalyst (ADR-001, spike-proven) · no AudioKit dependency (ADR-002) · XcodeGen
(ADR-003) · no Ableton Link (ADR-004) · local-only (ADR-005); the app and plugin are **signed with the
owner's team 8RSH7U3222** so they share presets through an App Group (ADR-041, which supersedes ADR-005's
ad-hoc signing) ·
named Arcade Ruins, AU subtype `ruin` (ADR-029).

## Start here, every session

```bash
cat STATE.md                 # current phase, task board, next action
git log --oneline -10
Scripts/fetch-references.sh  # if .references/ is missing (it is gitignored)
Scripts/build.sh             # regenerate + signed build (team 8RSH7U3222, ADR-041)
# Tests build unsigned, so they need no certificate. Keep them out of ./DerivedData,
# which is what gets installed (ADR-038):
xcodebuild -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/SynthOneTestDD \
    CODE_SIGNING_ALLOWED=NO test
Scripts/validate-au.sh       # auval — a real check since P4-2. ~8s since P4-3; a hang is at 0% CPU
```

**Run the tests often.** Since P2-4 the suite includes golden renders of 20 shipped presets, so an
accidental change to the DSP fails immediately instead of at the end of a phase.

Then do the **Next action** named at the top of `STATE.md`.

## Layout

```
README.md      Public-facing: what it is, how to build it, attribution
LICENSE        MIT (ours) · NOTICE.md — every upstream licence and the trademark position
PORT_PLAN.md   Phases and task IDs (P0-1 … P5-6) with acceptance criteria
STATE.md       Live status + session log. THE resume point.
docs/          01-decisions.md (ADRs) · 02-audiokit-api-surface.md · 03-parity-checklist.md
               04-build-and-test.md · reference/ (App Store screenshots)
upstream/      Pinned READ-ONLY copy of AudioKitSynthOne @ 6466a37
.references/   Pinned AudioKit 4.9.2, gitignored — fetch with Scripts/fetch-references.sh
project.yml    XcodeGen spec — the source of truth for targets and build settings
Sources/       Soundpipe/ · S1Support/ · SynthOneCore/ · SynthOne/ · SynthOneAU/
Scripts/branding/  Generates the wordmark and the 18 app icons
Tests/ Scripts/
```

Each vendored or ported directory carries its own record: `Sources/Soundpipe/VENDORING.md`,
`Sources/S1Support/PORTING.md`, `Sources/SynthOneCore/AudioUnitBase/PORTING.md`,
`Sources/SynthOneCore/DSP/PORTING.md`. **Read the relevant one before touching that code.**

## Ground rules

- **`upstream/` is read-only.** Port code *out* of it. Never edit it.
- **`SynthOne.xcodeproj` is generated.** Edit `project.yml`, run `xcodegen generate`. Hand edits are lost.
- **No CocoaPods.** Everything is vendored source.
- **Ported code keeps its `AK` names** (ADR-009). `SynthOneCore` re-exports `S1Support`, so porting a
  Synth One file means changing `import AudioKit` → `import SynthOneCore` and nothing else. The `S1`
  prefix is for code we own outright. The prefix is a provenance signal — respect it.
- **Minimal diffs against upstream.** This is a port, not a redesign. When you must change ported
  code, leave a `PORT FIX:` or `PORT:` comment saying why, and record it in that directory's
  PORTING.md.
- **Tests assert behaviour, not linkage.** A bad port compiles and links fine and sounds wrong —
  that is exactly how ADR-011 happened. Measure frequencies, amplitudes, envelope shapes.
- **Never mark a task done in `STATE.md` unless it builds and its verification step passed.**

## Session protocol

**End of session** (or when context runs low):
1. Update `STATE.md` — task board, blockers, **Next action**.
2. Append a dated Session Log entry (what changed and *why*, including anything surprising).
3. Record non-obvious decisions in `docs/01-decisions.md` as a new ADR.
4. Commit, prefixed with the task ID (`P1-3: ...`). Push.

Use a heredoc for commit messages (`git commit -F -`) — backticks in `-m` get shell-interpreted.

## Hard-won gotchas

Each of these cost real time. See `docs/04-build-and-test.md` for the build-level list.

| | |
|---|---|
| **Symbol presence ≠ compatibility** | P1-2 vendored canonical Soundpipe after checking every `sp_*` name existed. The signatures and semantics differed, and the band-limited `sp_oscmorph2d` was missing entirely — the anti-aliasing would have silently vanished. ADR-011 |
| `sp_create` returns **0**, not `SP_OK` (=1) | Only `base.c` deviates; every module's `*_create` returns `SP_OK`. Check the out-pointer |
| `pow2(x)` **squares**; it is not 2^x | It is Synth One's velocity curve. Misreading it changes how the instrument plays |
| `upstream/DSP/Kernel/oscmorph2d.c` is a **stale decoy** | The real band-limited module is in AudioKit's `Core/SoundpipeExtension/` |
| AudioKit 4.9.2 **does not compile** on modern Swift | Three integer/float narrowing bugs, incl. `exp2((noteNumber - 69) / 12)` — integer division that would collapse 128 notes onto ~11 frequencies |
| `AKAudioUnit` **replaces** `implementorValueObserver` | `allocateRenderResources` overwrites whatever `createParameters` installed. Upstream behaviour, preserved — and it is why host events arrive as *render* events at all. The observer you write in `createParameters` is not the one that runs. ADR-010, ADR-022 |
| Catalyst renders the iPad UI at **77%** | The idiom choice is an explicit P3-1 decision, not a default. ADR-007 |
| App Groups need a Team ID | Unavailable under ad-hoc signing, so P3-3 needs different shared storage. ADR-006 |
| `Bundle.main` in ported UI code is a latent **runtime** crash | Storyboards, presets and assets are framework resources. Use `Bundle.synthOneCore` / `UIImage.synthOne(_:)`. `#imageLiteral` **traps** rather than returning nil. ADR-017 |
| A storyboard class that fails to resolve is **silent** | You get a bare `UIView` with nil outlets, not an error. `UILoadTests` asserts concrete types for this reason. 18 `customModule` attributes needed correcting at P3-1 |
| `assert` is compiled out of Release | Upstream shipped a bounds assertion that reads `17 < 16`. Their Release build never saw it; every Debug build of the Tunings panel died on launch |
| XcodeGen makes **every** framework header public by default | And it keeps the **first** source entry matching a file, so per-file `public` entries must precede the directory that sweeps up the rest. Get it wrong and the framework ships no public headers *while still building*. ADR-012 |
| `AK_ENUM` is **not** `NS_ENUM` | It is `enum __attribute__((enum_extensibility(open))) a : int`. Our shim had it wrong for five sessions; it only compiled because `S1Parameter.h` was reached from Obj-C++. ADR-012 |
| `#pragma once` ≠ include guard here | Public headers are *copied*, so the same header reached from the source tree and from `<SynthOneCore/…>` is two files. Use named guards. ADR-012 |
| A note struck right after `allocateRenderResources` **sweeps up into tune** | `sp_port_init` zeroes its state, so parameters re-ramp from 0 while `S1NoteState::run` multiplies `oscmorph->freq` by `detuningMultiplier` every sample. Upstream. Do not "fix" it. ADR-013 |
| `xcodebuild` does not pass the shell env to the test runner | `SYNTHONE_WRITE_GOLDENS=1 xcodebuild …` is silently ignored; it must be `TEST_RUNNER_…`. Use `Scripts/write-goldens.sh` |
| Goldens are **float32**, not 16-bit | Four of the twenty presets render above full scale; integer PCM clamps them and the suite fails on clipping. ADR-016 |
| Never `@objc` anything in `SynthOneCore` that mentions an `S1Support` type | It lands in `SynthOneCore-Swift.h` as `@import S1Support`, which no consumer can resolve — S1Support is a static library. ADR-014 |
| A 90-second `AVAudioEngine` was a **consent dialog**, not CoreAudio | Upstream's `.playAndRecord` session prompts for the microphone and blocks until answered — the app is `.playback` now. Re-measured, `outputNode` costs 0.59 s. The rules that survive: enable manual rendering *first* when you want no hardware, and an AUv3 must **never** touch `outputNode`. ADR-015, corrected |
| Wavetables must be loaded **before** `allocateRenderResources` | It walks `ft_array` to rescale `sicvt`, and `S1NoteState::init` hands the array to `sp_oscmorph2d_init`. `destroy()` does not free them, so load once, outside the cycle |
| **A hang is not slowness.** Check CPU first | `auval` "running for 2.5 hours" was at **0.0% CPU** with no output — blocked, not busy. `ps`/`sample` answers it in one command. I guessed "slow because 150 parameters" and was wrong. ADR-021 |
| A running host holds the **old** plugin | macOS registers the AUv3 from `/Applications`, but a host that is already open does not rescan. A stale extension that crashed on load presents as **silence**, not an error — it cost a false "audio regression" on 2026-09-09. `Scripts/validate-au.sh` warns now; quit and relaunch the host after every install |
| An out-of-process AUv3 turns a **crash into a hang** | The extension segfaults, the host blocks forever on an XPC reply, and nothing in the host's output says the plugin died. **Always check `~/Library/Logs/DiagnosticReports/SynthOneAU-*.ips`**, not just the host's. ADR-021 |
| **The originator token does not cross the process boundary** | Out of process — Logic — the host sends every write the plugin's interface makes back into the extension's tree with no originator, so `token(byAddingParameterObserver:)` hears it as a host move. The in-process test passed throughout. `S1HostedSynth.echoWindow` suppresses it. Found by attaching lldb to the extension *inside Logic* (Debug builds carry `get-task-allow`) — the evidence that settled it in one run. ADR-030 |
| `scheduleParameterBlock` events never reach `internalRenderBlock` | The framework holds them; `AUAudioUnit.renderBlock` is what drains the list into `realtimeEventListHead`. Driving `internalRenderBlock` directly in a test delivers **no** scheduled parameters, and looks exactly like `startRamp` being a no-op. ADR-022 |
| `dependentParameters:nil` is not a safe default | `arpRate`/`tempoSyncToArpRate` re-drive four other parameters, so one host automation move changes five DSP values. A host that is not told keeps showing — and writing back — stale ones. ADR-022 |
| Localized `InfoPlist.strings` **override** `Info.plist` | Six of them hard-coded `CFBundleDisplayName = "Synth One"`. Renaming the product in `project.yml` alone leaves the old name in those languages. ADR-029 |
| The AU's `manufacturer`+`subtype` is **permanent** | A host stores that pair in its session, not the name. `aks1` → `ruin` was free only because nothing had shipped. ADR-029 |
| Ad-hoc builds are **rejected by Gatekeeper** | `spctl -a` says `rejected` even locally, and a downloaded copy fails as "damaged" with no dialog to click through. Public binaries need P5-2, or a documented `xattr -dr com.apple.quarantine` step. STATE.md |
| Mac-style controls **cannot be rendered in a test bundle** | `drawHierarchy` on a `.mac`-style control throws `NSInternalInconsistencyException` — there is no `NSApplication`. Assert `preferredBehavioralStyle`, and get the owner's eyes on the pixels. ADR-029 |
| **Listing button classes misses buttons** | ADR-026 fixed six classes; plain storyboard `UIButton`s with no `customClass` kept macOS chrome until a hierarchy walk found five more. Walk the view tree instead. ADR-029 |
| Signed `AUEventSampleTime` cast to unsigned `AUAudioFrameCount` | `eventSampleTime - now` is negative for `AUEventSampleTimeImmediate` — i.e. for *every* host automation move — and the cast makes it ~4 billion frames. Apple sample code, vendored by AudioKit, never executed in Synth One's history because the AU parameter tree was never implemented. ADR-021 |
| **The plugin must never open MIDI inputs of its own** | It did, through `Manager`'s CoreMIDI listener. In Logic one key played twice — as two different notes, on two threads — and a plugin on an unselected track answered a hardware keyboard. Host MIDI arrives in the render block and goes through `S1HostMIDI`, a render-thread port of `Manager` → `KeyboardView` → `SDSustainer`. **Change one, change the other:** `HostMIDIParityTests` compares them note for note. ADR-031 |
| **`x.take()` on an implicitly unwrapped optional is `Optional.take()`** | Swift type-checks an IUO as `Optional` first, and since 5.9 `Optional` has `take()`, which returns the value *and sets the property to nil*. A test recorder with its own `take()` emptied itself on first use and crashed one call later, far from the cause. Never name a method `take` on anything held in an IUO. ADR-031 |
| **A test run that executes 0 tests succeeds** | `xcodebuild test -only-testing:…` with a filter that matches nothing reports `TEST SUCCEEDED`, `Executed 0 tests`. A revert-and-fail check built that way proves nothing. The shell here is **zsh**, which does not word-split an unquoted `$VAR`, so `-only-testing` flags gathered into one variable became one argument that matched nothing — and a new test file added after `xcodegen generate` ran does the same. Write the flags out literally, and check `Executed N tests` with N > 0. ADR-032 |
| **Some UIKit controls throw under the Mac idiom, and only once they enter a window** | `UIPickerView` crashed the preset editor in both products. Loading it in the `.pad` test bundle is fine, so nothing caught it. UIKit's restricted classes are the ones with a `UICatalystMacIdiomUnsupported_Internal` category: `UIButton`, `UIPickerView`, `UIRefreshControl`, `UISlider`, `UIStepper`, `UISwitch`. `MacIdiomControlTests` walks every storyboard scene for them. **Driving the app from lldb Objective-C expressions has three traps.** Never call a variadic method such as `stringWithFormat:`: with no prototype, its arguments land in the wrong place. A breakpoint callback does not run inside an expression, because lldb's own exception breakpoint interrupts the expression first. And give every local a unique prefix: names like `table`, `S` or `context` collide with symbols in loaded images, and the expression does not compile. ADR-033 |
| **Dark appearance turns unset text colours white** | A storyboard control with a fixed light background and no text colour draws in `labelColor`, which is white in Dark. The preset and bank editors' name fields were white on `#F8F8F8`. Upstream had the same bug on a Dark-mode iPad. Pin such a control with `overrideUserInterfaceStyle = .light`, not the app: the rest of the design is only right in Dark. **To measure the running app, inject a library rather than typing lldb expressions**: the Debug build has no hardened runtime, so `open -g --env DYLD_INSERT_LIBRARIES=…` works. See `Scripts/debug/appearance_walker.m`. **In the test bundle an appearance override is not seen until a trait update**: with no window nothing triggers one, and an override set in `viewDidLoad` was invisible, so the test failed identically with and without the fix. Lay out and call `updateTraitsIfNeeded()`. ADR-034 |
| **A window-less view does not lay out after a constraint change** | Setting a constraint's `constant` and calling `layoutIfNeeded()` left the keyboard where it was in the test bundle. Call `setNeedsLayout()` first. The first shown-keyboard test failed that way with the layout correct; a diagnostic that printed frames settled it. ADR-035 |
| **The test bundle must never write the owner's files** | `Disk` resolves the real `~/Library/Application Support/SynthOne/` and `~/Library/Caches`, and the test bundle is not sandboxed. Until ADR-036, a test that fired the keyboard toggle saved a fresh `AppSettings` over the owner's `settings.json`, and `tunings_v1.json` and `currentPreset.json` were rewritten too. The bundle's principal class, `TestStorageIsolation`, now points `Disk` at a temporary folder before any test runs, and `StorageIsolationTests` checks it. **Any new file a test can reach must go through `Disk`**, or be redirected the same way. ADR-035, ADR-036 |
| **`sips -c` crops around the centre** | With `--cropOffset 0 0` it ignored the offset, so a mockup's panel image silently included the toolbar below it. Crop with PIL. ADR-035 |
| **A build signed by `xcodebuild test` is not the real plugin** | For the test runner, Xcode adds `temporary-exception.files.absolute-path.read-only` `/` and `testmanagerd` lookups. A following `xcodebuild build` with nothing to compile keeps that signature, so installs shipped it, and the plugin read the shared preset folder its real sandbox forbids. The first plain install loaded no presets and crashed on ▶. `Scripts/validate-au.sh` now refuses a plugin carrying `testmanagerd`. **Check `codesign -d --entitlements -` before believing anything about the plugin's sandbox.** ADR-038 |
| **In a sandbox, `fileExists` is not "can I read it"** | The plugin sees that `banks.json` exists and cannot read a byte of it. `Disk.exists` uses `isReadableFile`, so every caller falls back instead of taking a load that fails silently. ADR-038 |
| **A sandboxed plugin hanging at 0% CPU in `_libsecinit_appsandbox` is waiting for a person** | When the plugin's signature changed from ad-hoc to team-signed, `secinitd` found the new identity "not in ACL" for the existing `~/Library/Containers/…AUv3` container and put up a consent dialog, on a display nobody was watching. Every later launch queued behind it on a per-bundle serial queue, so a correct build looked broken. `sample` the per-user `secinitd`: a thread in `displaySharingConsentPrompt:` means ask the owner to look for the dialog. Separately, an App Group on macOS must be Team-ID-prefixed (`8RSH7U3222.…`); `group.…` is rejected without a profile listing it. In the Bash tool's zsh, `log` is a builtin: use `/usr/bin/log`. ADR-041 |
| **The standalone reopens at a remembered size, whatever `willConnectTo` sets** | After ADR-037 it kept reopening at 1024×900. Neither rewriting `NSWindow Frame MainSceneWindow` nor `requestGeometryUpdate` on activation changed that. Capping `sizeRestrictions.maximumSize` at the design size in `configure`, then raising it a second after launch, did. The revert check could not recreate the fault: after one capped launch, even the uncapped build reopened at 800, whether 900 had been set by a resize or by `requestGeometryUpdate`. So the cap is a guard, not a proven fix. **Measure the window with lldb (`UIWindow` and the interface's frame), not from a screenshot**: a screenshot with a sheet open suggested the interface had not followed the window, and it had. ADR-042 |
| **The standalone goes silent when the audio device changes, and the log blames the microphone** | AirPods taken out of an ear moved the default output. AVAudioEngine stopped itself ("iounit configuration changed > stopping the engine") and posted `AVAudioEngineConfigurationChange`, which nothing handled. In the same second tccd logged a refused microphone request under the hardened runtime: CoreAudio rebuilding its aggregate device, not the cause. `S1AudioEngine` now restarts an engine that should be running. **Read the app's own `avae` and `aqme` log lines before chasing TCC.** ADR-043 |
| **Apple's share sheet cannot be presented from the plugin** | `UIActivityViewController` crashed the plugin from both Share buttons. The Mac bridge places the sheet relative to the presenting view's window, and a plugin's view lives in the host's, so `_sceneViewRectFromUIWindowRect` fails an assertion. It is thrown after `present` returns, from UIKit's commit pass, so it cannot be caught at the call. Anything bridged to a Mac panel from the plugin is suspect until tried in a real host. The export `UIDocumentPickerViewController` does present there: confirmed in Logic. ADR-044 |
| **`pkill -f <app path>` also kills an lldb whose command line holds that path** | lldb died with its output unflushed, and the app was left stopped (state `T`) under a dead debugger. Kill the app with `pkill -x ArcadeRuins`, and never SIGTERM a debugged process: lldb stops it and waits. Regex breakpoints set before launch also slow startup past 12 seconds; attach to a running app instead. ADR-042 |
