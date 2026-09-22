# Build & test

## Prerequisites

- Xcode 16+ (full install; Command Line Tools alone are not enough)
- `brew install xcodegen`
- First time on a machine:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  xcodebuild -runFirstLaunch
  ```
  The last one is not optional — without it `xcodebuild` fails to load `IDESimulatorFoundation`
  because CoreSimulator is missing.

## Everyday commands

```bash
Scripts/fetch-references.sh    # pinned AudioKit 4.9.2 into .references/ (gitignored)
Scripts/build.sh              # xcodegen generate + build the SynthOne app
Scripts/build.sh SynthOneCore # just the shared framework
Scripts/validate-au.sh        # install to /Applications, register, run auval
```

Tests:

```bash
xcodebuild -project SynthOne.xcodeproj -scheme SynthOneCore \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath ./DerivedData test
```

Universal (arm64 + x86_64) check — Debug builds only the active arch:

```bash
xcodebuild -project SynthOne.xcodeproj -scheme SynthOneCore -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath ./DerivedDataRelease ONLY_ACTIVE_ARCH=NO build
lipo -info DerivedDataRelease/Build/Products/Release-maccatalyst/libSoundpipe.a
```

## Target graph

```
Soundpipe (static C) ─┐
S1Support (static)   ─┴─► SynthOneCore.framework ─┬─► ArcadeRuins.app  (Catalyst, standalone)
                                                   └─► ArcadeRuinsAU.appex (AUv3, aumu/ruin/BP03)
```

Static libraries link into the framework and leave nothing to embed or sign (ADR-008). Only
`SynthOneCore.framework` is embedded, by the app; the extension links it and uses the app's copy.

## Validating the Audio Unit

`Scripts/validate-au.sh` copies the app to `/Applications`, launches it once (the system registers
an AUv3 from its containing app — no host, including `auval`, sees it otherwise), waits for
registration, then runs `auval -v aumu ruin BP03`.

**The AU has passed `auval` since P1-1, so run this at every phase.** It is a regression check, not
a Phase 4 milestone (ADR-008).

## Release build and distribution

```bash
xcodegen generate
xcodebuild -project SynthOne.xcodeproj -scheme SynthOne -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath ./DerivedDataRelease build
```

This produces `DerivedDataRelease/Build/Products/Release-maccatalyst/ArcadeRuins.app` (~20 MB), with
`Contents/PlugIns/ArcadeRuinsAU.appex` inside. Verified 2026-09-09; `codesign --verify --deep
--strict` passes.

**Package it with `ditto`, not `zip`.** `SynthOneCore.framework` is a versioned bundle with three
symlinks (`Versions/Current`, `Resources`, `SynthOneCore`). `zip -r` without `-y` follows them and
stores copies, which breaks the sealed bundle.

```bash
ditto -c -k --keepParent DerivedDataRelease/Build/Products/Release-maccatalyst/ArcadeRuins.app \
  ArcadeRuins-<version>-maccatalyst.zip
```

**⚠️ Gatekeeper rejects this build.** It is ad-hoc signed (ADR-005):

```bash
codesign -dv ArcadeRuins.app            # Signature=adhoc, TeamIdentifier=not set
spctl -a -vvv -t exec ArcadeRuins.app   # rejected
```

A copy downloaded from the internet is also quarantined, and macOS calls it *damaged*, with no option
to open it. Until P5-2 (Developer ID plus notarisation), anyone installing a download has to:

1. Move `ArcadeRuins.app` to `/Applications` — the AUv3 registers only from there.
2. Run `xattr -dr com.apple.quarantine /Applications/ArcadeRuins.app`.
3. Launch the app once, so the system registers the plugin.
4. Quit and relaunch the host.

## Arcade Ruins (the JUCE build): validating and releasing

This file is Classic's — the Catalyst app and its AUv3. The cross-platform product is built by
CMake ([`Sources/S1Plugin/README.md`](../Sources/S1Plugin/README.md) is its guide), and **there is
no CI** (ADR-079): these scripts are the verification.

| | macOS | Linux (Docker, on the Mac) | Windows (the owner's machine) |
|---|---|---|---|
| **Validate** | `ctest` in `build/plugin`, `Scripts/validate-plugin.sh` (`--au` adds `auval`) | `Scripts/validate-linux.sh` (GCC, validators, RealtimeSanitizer) | `Scripts\validate-windows.ps1` — paste its block back |
| **Release** (ADR-094) | `Scripts/release-plugin.sh` — universal, Developer ID, one notarised `.pkg` | `Scripts/release-linux.sh` — a tarball built on Ubuntu 22.04 | `Scripts\release-windows.ps1` — Inno Setup, the C runtime linked in |

Every release script runs the whole suite on the binaries it packages and refuses a dirty tree.
Three things a release must not forget: the macOS package needs a **Developer ID Installer**
certificate (not the Application one); a Linux binary needs the glibc it was **built** on or newer;
and a Windows plugin that cannot find `VCRUNTIME140.dll` fails silently, so the runtime is linked in.

## ⚠️ Build settings that are load-bearing

Do not "tidy" these. Each was needed to make something work.

| Setting | Where | Why |
|---|---|---|
| `AdHocSigned` target template | every target | XcodeGen writes its own `CODE_SIGN_IDENTITY = "iPhone Developer"` at **target** level, which silently overrides `settings.base`. Ad-hoc signing must be applied per target |
| `GCC_C_LANGUAGE_STANDARD: gnu11` | project | TAAE uses `typeof()`. Strict `c11` rejects it |
| `CLANG_ENABLE_MODULES: NO` | **Soundpipe target only** | `oscmorph2d.c` includes `soundpipeextension.h` textually; with modules on Clang also supplies it via the module and `sp_oscmorph2d` is typedef'd twice. The module map still exists, for Swift consumers |
| `NO_LIBSNDFILE=1` | Soundpipe | `base.c`/`ftbl.c` guard file I/O we never use behind it |
| `SWIFT_INCLUDE_PATHS` incl. `S1Support/include` | project-wide | `S1Support` re-exports the `S1SupportC` module map, so anything importing `SynthOneCore` — the test bundle included — must be able to find it |
| `HEADER_SEARCH_PATHS` incl. `SynthOneCore/AudioUnitBase` | SynthOneCore | Lets ported kernel sources keep `#import "AudioKit/AKSoundpipeKernel.hpp"` verbatim |
| `.../Soundpipe/lib/dr_wav` on header path | Soundpipe + core | `soundpipe.h` declares `sp_wavin`, whose struct embeds a `drwav`. Declarations only — `dr_wav.c` is never compiled |
| `IPHONEOS_DEPLOYMENT_TARGET: 14.0` | project | XcodeGen ignores `options.deploymentTarget` when `supportedDestinations` is used, so it must be explicit or you silently get the current OS as the floor |

| `excludes: ["**/*.md"]` | Soundpipe, S1Support, SynthOneCore | Each vendored directory carries a `PORTING.md`/`VENDORING.md`. Without this they are copied in as *resources*, and two `PORTING.md` files collide in the framework's Resources folder |
| `headerVisibility: project` on the `Sources/SynthOneCore` entry, **listed last** | SynthOneCore | XcodeGen defaults every framework header to `public`, which shipped all 30 (C++ included) and produced 25 umbrella warnings a build. The per-file `public` entries must come **first** — XcodeGen keeps the first entry matching a file. Reversed, the framework ships **no** public headers and *still builds*, because Xcode's own header map resolves `<SynthOneCore/…>` inside the target. Only an external consumer fails. ADR-012 |

**Public framework headers get flattened** into `SynthOneCore.framework/Headers`, so they must use
`#import <SynthOneCore/Foo.h>` — and a **named include guard**, not `#pragma once`, since the copied
header and the source-tree original are two different files on disk. Only internal sources may use
the `"AudioKit/..."` relative paths.

The public set is exactly: `SynthOneCore.h` (umbrella), `AKAudioUnit.h`, `AKInterop.h`,
`S1TestToneAudioUnit.h`, `S1Parameter.h`, `S1AudioUnit.h`. **No `.hpp` may join the umbrella** —
Swift parses it as Obj-C.

## Rendering audio offline (P1-6)

`Tests/SynthOneTests/S1AudioUnitRenderTests.swift` is the reference for driving the synth with no
engine and no UI. The order is load-bearing:

```
S1AudioUnit(componentDescription:options:)   // AKAudioUnit's init calls createParameters
setBandlimitFrequency x13, setupWaveform + setWaveform x52   // BEFORE allocate — see DSP/PORTING.md
maximumFramesToRender = 512
allocateRenderResources()
startNote(_:velocity:)
internalRenderBlock(...)                     // pulled by hand, block by block
```

Two measurement rules learned there: estimate pitch by **autocorrelation, first strong peak** (the
default patch is a sawtooth, so zero-crossing counting overcounts and the tallest peak may be 2T);
and **wait ~1 s after `allocateRenderResources`** before measuring pitch, because the synth sweeps
into tune (ADR-013).

Running the suite writes `Renders/p1-6-first-sound.wav` (gitignored) — listen to it.

## Golden-WAV regression (P2-4)

```bash
# just the goldens
xcodebuild -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath ./DerivedData \
    -only-testing:SynthOneTests/GoldenRenderTests test

# regenerate them — ONLY for a change you intend to hear, and listen afterwards
Scripts/write-goldens.sh
```

20 shipped presets, rendered offline, compared against `Tests/Goldens/*.wav` (float32, ~10 MB).
Full detail in `Tests/Goldens/README.md`; the decisions are ADR-016.

Three things to know before touching it:

- **Every number in the rendering recipe is load-bearing.** Sample rate, block size, settle time,
  which notes at which times, capture length. Change one and all twenty files are invalid.
- **The goldens are float32 because four of the twenty presets render above full scale.** 16-bit
  clamps them and the suite fails on clipping rather than on DSP.
- **`SYNTHONE_WRITE_GOLDENS=1` in front of `xcodebuild` does nothing.** `xcodebuild` does not pass
  the shell environment to the test runner; it has to be `TEST_RUNNER_SYNTHONE_WRITE_GOLDENS=1`.
  `Scripts/write-goldens.sh` gets this right.

Measured sensitivity: a 0.24% change to one internal LFO smoothing constant fails 17 of the 20.

## The desktop layout (Phases 6–8)

The layout is built over the classic `Manager` at launch (`S1DesktopLayout.install(into:)`, ADR-045),
so nothing about the build changes. What changes is how a layout task is checked:

1. **Render it.** `DRIVER_OUT=/tmp/arcade-ruins-debug RENDER_TAG=desktop RENDER_SELECT="Brice Beasley,0: "
   xcrun lldb -b -o "command script import Scripts/debug/desktop_render.py"` writes
   `/tmp/arcade-ruins-debug/desktop.png` from the `./DerivedData` app (2880×1800, Retina). Read the PNG;
   read `desktop.stderr` for "Unable to simultaneously satisfy constraints" (there should be none).
   `RENDER_ARGS="-S1Skin neonRuins"` renders a skin, `RENDER_PRESS=Presets` opens the preset
   browser, `RENDER_SIZE=WxH` pins the window. `Scripts/debug/README.md` lists every variable.
2. **Its suites.** `-only-testing:SynthOneTests/DesktopLayoutTests` (the layout: every bound control
   on screen, sections at the design size, readouts, MIDI learn, the browser, the cards, hit zones),
   `SkinTests` (every skin lays every section out in the same place; Neon Ruins hangs its art and its sections have their accents; the Settings pickers) and
   `DesktopPluginTests` (the plugin's differences). Build them into `/tmp/SynthOneTestDD2` with
   `CODE_SIGNING_ALLOWED=NO`, never into `./DerivedData` (ADR-038).
3. **Install.** `Scripts/validate-au.sh` copies `./DerivedData`'s app to `/Applications` and runs
   `auval`. The owner's running copy keeps the old build until relaunched; so does Logic.

`Sources/SynthOneCore/Desktop/` is the whole layout: `S1DesktopLayout.swift` (shell, toolbar, preset
browser, play and status bars, the cards), `S1DesktopLayout+Rows.swift` (the four rows and every
control size — the file a layout request usually lands in), `S1DesktopStyle.swift` (Core Graphics for
the knobs, switches, steppers, faders and chips), `S1DesktopTheme.swift` (metrics, and colours read
from the skin), `S1Skin.swift` (the palette, the dress and the two skins), `S1SynthwaveArt.swift` and `S1NeonRuinsArt.swift` (the
decoration), `S1SectionView`, `S1ControlCell`, `S1SegmentedControl`, `S1PanelSheet`.
