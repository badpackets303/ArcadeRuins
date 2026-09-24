# STATE — resume point

> Update this at the end of every session. It is the first thing the next session reads.

## ▶ NEWEST (2026-09-24) — Dark Arcade, a third skin; and two things left open

**Dark Arcade (ADR-100) — built, verified on macOS, not released.** The owner's calmer painting
as a third skin, **Arcade Ruins (the plugin) only**, Cabinet still the default, on the owner's
CLEAN painting (`Scripts/branding/source/dark-arcade.png`, their second file of the day — the
first was a mockup with controls painted in). Its header has no painted buttons, so the plugin
draws them (`template.paintedButtons`). Installed in `~/Library/Audio/Plug-Ins/Components` for the
owner to try in Logic. Verified here: ctest **44/44** (the new
`EditorSnapshotDarkArcade` among them), Steinberg's validator **537/537**, pluginval strictness 10
**SUCCESS**, and the Xcode suite **344 run, 342 pass** — the two failures are Xcode 27's, not
this work's (below). **Owed:** Linux
(`Scripts/validate-linux.sh`) and Windows (`Scripts\validate-windows.ps1`) for this commit; the
owner's eye on it in a host; README/release notes when it ships.

**Open, the owner's to decide:**
- **Xcode 27 refuses Classic's macOS 11 deployment target** (CLAUDE.md gotcha): every Mac build
  fails until `project.yml` is raised, which changes Classic's minimum macOS. Tests and the spec
  writer run with `IPHONEOS_DEPLOYMENT_TARGET=15.0` on the command line meanwhile.
- **Xcode 27's UIKit breaks an upstream line in Classic:** `WheelSettingsViewController.swift:46`
  labels `modWheelSegment.subviews[2]`, a private subview a segmented control no longer has when
  the view loads — `NSRangeException`, so the mod-wheel settings popover would CRASH in a Classic
  built with Xcode 27 (0.5 as shipped was built before it). It fails `MacIdiomControlTests` and
  `TextInputAppearanceTests`, which load every scene. A `PORT FIX` guarding the count is the fix;
  not made, because it is a Classic change.
- **The public repository's RealtimeSanitizer job fails** (the emails the owner was getting —
  2026-09-23). Three findings: two engine tests rendered before making their voices (fixed in the
  working tree, uncommitted, unverified), `processBlock` reporting engine-driven parameter changes
  through JUCE's `sendValueChangedMessageToListeners` (a lock on the audio thread — exempt with an
  ADR, or redesign; the owner has not chosen), and **the local rtsan stage was blind**
  (`--output-on-failure` never shows a finding that does not fail its test; now `--verbose`,
  uncommitted). **ADR-079's "RealtimeSanitizer clean" was produced by that blind check.** The
  private repository's workflows were DISABLED by the owner (`gh workflow enable` restores them).
- **"The last used preset is not loading when using the AU in Logic"** (2026-09-24, JUCE AU) —
  investigation stopped at the owner's word; nothing changed. A saved state carries the preset and
  its name by design; a new instance deliberately starts at Init.

## ▶ RESUME HERE — the cross-platform track (rewritten 2026-09-21 after X3-8)

**Where things stand.** Branch **`main`**, clean, pushed to the private origin. The cross-platform
plan (JUCE VST3 + Standalone; plan page <https://claude.ai/artifact/9zr5fP3KeuYMt5kvcmcaDH>) has
**X0, X1 and X2 complete and verified on macOS, Linux and Windows; X3-1 (layout specification,
ADR-083), X3-2 (controls kit, ADR-084), X3-3 (the editor, ADR-085) and X3-4 (the preset browser,
ADR-086) done 2026-09-19, green on macOS and Linux. The plugin and the standalone now open the
real interface, and the preset browser works in it.**
**Windows: GREEN for X3-1 … X3-6, on the COMMITTED tree.** Their run of 2026-09-20 20:14 at
`8d12e71` — Windows 11 / i7-6700HQ / CMake 4.3.1-msvc1 / Visual Studio 18.10.1: **38/38 CTest**,
Steinberg's validator **537/537**, pluginval strictness 10 **SUCCESS**, denormals measured on x86
(a reverb-heavy tail at 1.01x a sounding block, 0 subnormal samples out). **No "+ uncommitted
changes" in the header** — the first Windows run of a tree carrying no patch of theirs, so the
whole of X3-1 … X3-6 builds and validates there from what is in the repository.
**Windows: GREEN for X3-1 … X3-9.** Their run of 2026-09-21 13:09 at `383d34d` — **42/42 CTest**, Steinberg's validator **537/537**, pluginval strictness 10 **SUCCESS**, and the x86 denormals measured (a reverb-heavy tail at 1.00x a sounding block, 0 subnormal samples out). Earlier that day: green at `a9d5b6a` too. Their run of 2026-09-21 10:12 at `a9d5b6a` — **39/39 CTest**,
Steinberg's validator **537/537**, pluginval strictness 10 **SUCCESS**, and the x86 denormal
measurement back in the block (a reverb-heavy tail at 0.99× a sounding block, 0 subnormal samples
out) because a step needs a fresh build rather than a green test run now. **The replaced border
check reads its own colour under all three renderers.** Their earlier run that morning, at
`c309e38`, built and validated cleanly and failed one CTest check — my crispness check, not the
interface (below).
**Nothing is owed on Windows.**

**What it took, worth remembering.** Three runs that evening; the first two failed on things no
compiler here can see:
- `5028b6e` did not build: two init-captures inside nested lambdas in X3-6's Settings card — **the
  same form the owner fixed by hand at X3-5, reintroduced hours after it was written into
  CLAUDE.md's gotchas.** The form is banned outright now and grepped by `NoNestedInitCapture` on
  every OS; a `SafePointer` is always a named local, captured by copy.
- Their own observation, twice over: the script reported `ok` for the tests and the validators
  **after the build had failed**, because the previous run's binaries were still on disk. Steps
  declare what they need now and report `not run` instead, and a skipped step blocks its own
  dependants. Verified in a real PowerShell before being sent (Docker,
  `mcr.microsoft.com/powershell`), on both the failing and the passing path.
- Earlier the same day: `.vs/` and friends were not gitignored, so "+ uncommitted changes" meant
  nothing. The block lists what is dirty now AND prints the diff, so a fix made there comes home
  with the run that needed it.

**X3-6, done 2026-09-20 — the skins, the typeface, and the cabinet made whole (ADR-088).**
**The owner used it and found one more:** leaned hard right the ball was cut off against the
console. **JUCE clips a component's painting to its bounds where UIKit does not** — the stick's box
is wider than its grab area now (`Joystick::kSwing`, 24 painting pixels a side) with `hitTest`
keeping the clicks in `reach`. `EditorSnapshot --lean <points>` draws it over.
- **Barlow Condensed ships** (SIL OFL, the owner's yes of 2026-09-20): `Sources/S1Plugin/Fonts/`,
  linked in, used wherever there is no Avenir Next Condensed. `PluginTypefaceTests` holds every
  label and section title to its measured frame IN THAT FACE, forcing it so macOS cannot pass by
  measuring Avenir. **Measure `Style::drawable(text)`, not the raw specification text.**
- **The skin is chosen in the window** (`applySkin`, in place), and Settings is a real card: a
  button per skin, X3-5's tuning switch, and the every-parameter list as one entry. The choice
  lives in `interface.json` beside the banks.
- **The cabinet's joystick is back and live** — the painting has it cut out, so without the two
  sprites the console is empty. Its boxes are MEASURED (`template.joystick`, the Swift writer);
  up is the mod wheel through a new interface path on the processor, sideways is the pitch bend,
  the 15% dead zone is the pitch's and not the picture's, and it springs back.
- **The pads throw their starfield** (upstream's emitter cell drawn, from the pad's CENTRE) and
  **wear their CRT frame** under Cabinet. A painted glow is not a layer's shadow: it must be
  clipped to outside what it frames.
- **The red power buttons are NOT done** — the owner agreed on 2026-09-20 that ADR-062's greyscale
  cycle is its own task. It is the obvious next easter egg if they want it.

**X3-7, done 2026-09-21 — the window scales (ADR-089).** Everything is built at the design size on
one `stage` component and the window puts a single `AffineTransform` on it: uniform, centred, and
letterboxed in the skin's own colour when the window is not the design's shape. Nothing is
re-laid out, so every frame the specification measured still holds and the cards go with it.
0.75× to 1.5×, the aspect ratio fixed in the constrainer, a corner resizer for hosts that draw
none — and **the plan's acceptance met: a 1280 × 800 laptop's 1224 × 765 window shows the whole
interface at 0.85× with none of the 125 controls clipped.** The standalone's window picks the
editor's own constrainer up, so it resizes the same way. Nothing new remembers the size: the host
and JUCE's standalone window each keep their own.
- **Two checks that could not fail, both found by reverting** (fifth and sixth in seven tasks): a
  component answers no clicks until something makes it **visible**, so the hit-test check compared
  0 with 0; and `createComponentSnapshot` makes an **RGB** image for an opaque component, so
  "every pixel's alpha is 255" passed with the letterbox fill deleted. They read 125 answering
  controls and the margin's colour now.
- **A revert that did NOT fail is worth as much:** buffering the whole stage changed nothing,
  because JUCE renders a cached component at the physical pixel scale, transforms included. Caching
  does not cost sharpness here; painting into a design-size image yourself would.
- **The owner's Windows run found the crispness check itself was wrong** (2026-09-21, `c309e38`:
  build, validator 537/537 and pluginval all green, one CTest check failed). It compared a native
  1.5× render with a 1× render put through `Image::rescaled` — 1.31× here, **1.07 there** against a
  threshold of 1.15 — and they settled the cause before reporting it: with the backdrop's buffering
  OFF the ratio was 1.0725, against 1.0711 with it on, so nothing is cached and stretched on
  Windows and the platforms' resamplers simply differ. **Anything measured against a rescaled image
  measures the platform.** It is ADR-084's absolute colour measurement now, taken through the
  window's transform — their own suggestion. And writing it took two goes: comparing the border at
  1.5× with the border at 1× passed a half-pixel offset, because the mutation moved both sides.
- **Their second finding, and they were right:** the Windows script gated the x86 denormal
  measurement on the whole CTest run, so one unrelated failure threw away a perfectly current
  measurement. A step needs a fresh BUILD, not a green test run; `-Needs $BuildStep` now.

**X3-8, done 2026-09-21 — the keyboard drawer, and the last of the play bar (ADR-090).**
**The interface plays MIDI.** A key in the drawer is not *like* a host note, it **is** one: the
message goes into a lock-free ring that the audio thread drains at the top of the next block, into
the same event array the host's MIDI goes into, before it. So the octave shift, white keys, hold,
mono, the arpeggiator and the held-key bookkeeping all happen once, in the router, where they were
already tested. **Measured as audio: the same note played from the interface and from the host
renders 12,288 samples with a worst difference of exactly 0.**
- **The drawer overlays and stops above the play bar** — it does NOT resize the window. The owner
  settled that at ADR-039 ("only elongates the virtual keyboard a bit"), and under ADR-089 a taller
  interface in a window a host refuses to grow would shrink everything. Hold, Octave, Transpose and
  Wheels stay visible beneath the keys. Command-K opens it; closed by default; remembered per
  instance in the session's state.
- **The keys are upstream's**, not a piano's: `s1plugin::Keybed` ports `KeyboardView`'s geometry
  (an octave is `width/n − width/(n²×7)`, black keys 55% of the length and two of the black band's
  28 slots wide) and its hit-testing. One PORT FIX: upstream sounds a **D** in the sliver of the C
  that closes the keyboard.
- **Hold, the octave, Wheels and musical typing** are all live now — the three buttons that have
  said "comes with X3-8" since X3-3, and the typing the status bar has promised for as long
  (A–K play, Z/X octave, C/V velocity, with the same octave the stepper moves).
- **A bug no test caught and a PICTURE did:** the first version moved the keys with the octave
  control *and* let the router shift the note, so a key sounded two octaves up. Every check passed
  — they asked where the keys were, not what they sounded. **Ask what a control SOUNDS.** The check
  that exists now reads 72 where the bug reads 84.
- **One rule of the owner's was amended, and they should know:** `Sources/S1Plugin/README.md` said
  the state fixture is never rewritten. It is rewritten now when a field is ADDED and the diff is
  purely additive (`window.keyboardShown`, four lines); a field that changes meaning still gets a
  new format version and a new file. What the rule protects — an older state still loading — has
  its own check.

**X3-10, done 2026-09-21 — the joystick pulls the bitcrusher down** (the owner, the same day: "as a
user pulls it can we also lower the bitcrusher rate"). The stick moves three things now: away is
the mod wheel, sideways is the pitch, **towards you is `bitCrushSampleRate`**, and each springs
back to where the sound had it when the stick was grabbed. Measured where the KNOB sits rather
than in hertz, so the fall is even — a full pull is 2,048 Hz, the floor; half a pull is half way
down the travel; a push leaves the rate alone. Revert-checked (five checks fail without it). **Verified 2026-09-21:** macOS 43/43 CTest; Linux arm64 42/42 under GCC 13, validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean 41/41. **Windows owed for this commit.** Heard, not assumed: the same note rendered with the stick at rest and pulled right down differs by a mean 0.021 against an RMS of 0.134, and the kernel holds 2,048 Hz at the next block. It is
in `docs/private/cabinet-extras.md` with the rest of the easter eggs, and **the Mac products are
untouched** (ADR-074) — say the word if it should go there too.

**The console is cleaned up — from the OWNER'S repaint, not an inpaint** (2026-09-21). The first
attempt (a Laplace fill) was refused: "it looks like black spots are left". They then painted it
themselves — `Scripts/branding/source/cabinet-fix.jpg`, the small cabinet at 4.154× with the three
yellow buttons and the small red one gone — and `generate.py`'s `clear_console` takes from it
**only where it differs from the painting** (the mask IS that difference, grown and feathered), so
the two power buttons, the joystick and every other pixel stay the painting's. Where the repaint
sits was measured by a search over scale and offset (mean difference 6 of 255 at the fit). The 2×
painting changed inside `(233,1694)…(358,1769)` and nowhere else. **This is the SHARED artwork, so
the Mac app and AUv3 show the clean console from their next build** — nothing of theirs was
rebuilt or installed; say the word if the Mac should keep the old console and it becomes a
plugin-only copy. Check: no yellow pixel above the red buttons (231 with the old painting), the
red ones still there. **And a click no longer draws a rectangle round a button** (the owner saw it
on the red ones): `ItemButton`'s focus ring is for focus that came by KEYBOARD; a click still takes
the focus, so Space and Return work. Revert-checked (208 pixels of ring without it). Only
`ItemButton` — the kit's knobs and switches still ring on a click, as they have since X3-2.
**Tightened the same day to TAB ONLY:** the owner then saw a rectangle round the app's title after
clicking the preset name twice. Closing a card makes JUCE hand the focus to the first thing in the
window that will take it — under Cabinet the invisible About button over the painted title — and
that arrives as `focusChangedDirectly`, which "not a click" let through. Revert-checked (208).
*Not reproduced in a window here* — a console test cannot hold real focus — so the owner's eyes
are the confirmation. macOS 43/43, validators green; Linux arm64 42/42 under GCC 13, validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean 41/41. **Windows owed.**
**Verified 2026-09-21:** macOS 43/43 CTest, validator 537/537, pluginval 10 SUCCESS; the Xcode
suite 343/343 (the painting is the Mac's too); Linux arm64 42/42 under GCC 13, validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean 41/41. **Windows owed for this commit.**

**The XY pads, at the owner's word** (2026-09-21: "the starfield/sparkle is barely visible … a
little bolder with smaller particles … let the focus follow the cursor on the pad … shrink the
target rectangle to half its current size"). **A departure from the Mac, in the JUCE plugin only**
(ADR-074: the Mac products are untouched). The stars keep upstream's MOTION (80 a second, 1.7 s,
190 ± 60 points a second, every direction) and lose its LOOK: one to three points across with a
hot core and nearly opaque while young, where the Mac's soft disc was ten points and more and under
a quarter opaque. **Each star leaves from where the touch was when it was born** — `XYPad` keeps
the touch's trail (`Style::PadTouch`) — so the field follows the cursor and streams behind it; the
CURSOR, not the target, because a tempo-synced pad's target steps between note values. The target
is half `TouchPointStyleKit`'s size (`Style::kPadTargetScale`). Stars and target both grey with
the power out now (they were the last orange left in a dark zone). Six checks in the pixels, all
revert-checked: brightest alpha 251 (141 before), median star width 2 (9), a fresh burst 5 points
from the touch (31 when emitted from the centre), flying stars stay on their way when the touch
moves, new ones leave from the new place, the target's block 12 pixels (22).
`EditorSnapshot <skin> out.png --pad 0.9` holds and sweeps the first pad for a picture.
**Verified 2026-09-21:** macOS 43/43 CTest, validator 537/537, pluginval 10 SUCCESS; Linux
arm64 42/42 under GCC 13, validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean 41/41. No Swift, Mac source or specification change: the Xcode suite was not needed.
**Windows owed for this commit.** *Not changed, and one number if wanted:* the birth rate is still
upstream's 80 a second — about 35 stars on a pad at once; doubling it is one constant.

**Studio's wordmark is the owner's artwork at the size it is shown** (2026-09-21: "the text on it
somehow seems misaligned"). It WAS their `Arcade-Ruins.png` — but through `s1_logo`, a 196 × 28 box
made for the iPhone header in which the letters are 13 pixels tall, stretched to the 240 pixels a
Retina window gives the wordmark's 120 points: edges between pixels, stems of uneven weight.
`generate.py`'s `plugin_wordmarks` now cuts it for the plugin at 120/180/240/360/480 pixels
(`Sources/S1Plugin/Art/`, linked as `ArcadeRuinsArt`), and the backdrop draws the smallest cut at
least as wide as the pixels it covers — pixel for pixel at the design size on a 1x or 2x display,
a reduction under 1.5 anywhere else (each platform's resampler is its own, ADR-089). Check,
ABSOLUTE: at 2x the solid pixels on the glass are the file's (mean difference 0.2 of 255; 11.5 with
a stretched cut). **The Mac still uses `s1_logo`** and is as soft there — untouched (ADR-074); the
same cuts would fix it if wanted. *A slip worth a line:* the revert was undone with `git checkout
<file>`, which threw away that file's UNCOMMITTED half of the change too — restore a mutation by
reversing it, or commit first. **Verified:** macOS 43/43, validator 537/537, pluginval 10; Linux
arm64 42/42 under GCC 13 (the pixel-for-pixel check holds on its renderer too), validator 537/537, pluginval 10, RealtimeSanitizer clean 41/41. No Swift or specification change. **Windows owed.**

**…and half as big again** (the owner, the same day: "a little bigger … it looks tiny" — its
letters were 8 points tall). `Backdrop::kWordmarkScale = 1.5`: 180 points, grown to the RIGHT from
where the specification starts it, about the same middle; the header is empty as far as the
preset's arrows. The cuts are 180/270/360/540/720 now. **Plugin only — the Mac's layout and the
specification stand** (ADR-074, ADR-083); it is one number, like the pads' target. *The check
earned its keep at once:* the 360-pixel cut is 23 rows tall, centring an odd height starts on a
half pixel, and every row was resampled (mean 14.6). The wordmark is placed by hand on the pixel
grid now (0.4). Still at x 78, the gap the Mac leaves for its window buttons — a plugin has none;
moving it left is the owner's call. **Verified:** macOS 43/43, validators green; Linux arm64 42/42 under GCC 13, validator 537/537, pluginval 10, RealtimeSanitizer clean 41/41.
**Windows owed.**

**▶ NEXT ACTION: X4 is UNDER WAY (ADR-094) — three things wait on the owner, in this order.**
(1) ~~A Developer ID Installer certificate; the release's version~~ — **DONE. The macOS release is
built at its own number: `build/release-plugin/release/ArcadeRuins-1.0.0-macOS.pkg`, 47 MB,
universal, notarised (Accepted in 60 s), stapled, `spctl -a -t install`: `accepted /
source=Notarized Developer ID`, SHA-256 beside it.** Read back out of the package: all three
bundles 1.0.0, the AU's component version 65536 (= 0x10000), and the VST3's class IDs unchanged by
the bump — a version is not part of the identity. **Not installed here; not published.** (2) **`Scripts\release-windows.ps1` on the
Windows machine** (needs Inno Setup 6) — written here and NEVER RUN; expect a first-run fault or
two; paste its block back. It also covers the owed validation of `7994dda`, since it runs every
test. (3) **The Intel half of the Mac build has never been run** — this Mac has no Rosetta.
**BOTH Linux tarballs are BUILT and proved, at 1.0.0** — `ArcadeRuins-1.0.0-linux-x86_64.tar.gz`
and `…-aarch64.tar.gz`, each 42/42 under GCC 11 / glibc 2.35 and each then taken to a clean
Debian 12 of its own architecture (glibc 2.36, only libasound2 / libfreetype6 / libfontconfig1
added): installs, `ldd` finds nothing missing, the plugin loads and exports `GetPluginFactory`,
`uninstall.sh` leaves 0 files. The x86-64 run is emulated here, which also puts the goldens
through arithmetic with no fused multiply-add (ADR-071) — they passed.
**Done 2026-09-21:** X4-1's three packagers (macOS pkg, Linux tarball, Windows installer script),
X4-2's macOS signing up to the package. **X4-4, the documentation pass — DRAFTED 2026-09-21, not published:** `README.md` presents TWO
products (a comparison table, one engine, Classic's download pinned to its `v0.5.0` tag because a
`latest/download` link breaks the day another product is the latest release; "no download yet" for
the cross-platform one, which is true until X4-5), both build routes, five new screenshots of the
JUCE plugin (four from macOS, one rendered on LINUX in the validation container — honestly
captioned as the plugin's own snapshot tool, not a DAW); `docs/release-notes.md` has an unreleased
section for each product; `NOTICE.md` names the AU and **Apple's AudioUnitSDK (Apache 2.0)**, which
the AU carries through JUCE; `docs/04-build-and-test.md` has the validate/release table.
**The Linux screenshot found a fault:** "Pitch Track" drew as "Pitch Trac" — a caption's frame is
as wide as the Mac's text in Avenir, and Barlow runs wider. `PluginTypefaceTests` measured the 33
labels and the section titles but NOT the 62 captions a skin has; it does now (with no room it
names "Pitch Track", 2.7 points over, and "Transpose"), and the backdrop gives captions the 12
points a side centred labels always had (`Style::kCaptionRoom`).
**The 1.0.0 artefacts were REBUILT at `ffcc2e6` (with ADR-099), 2026-09-22:**
`ArcadeRuins-1.0.0-macOS.pkg` `6c628753…` (notarised, stapled, `spctl` accepted),
`…-linux-x86_64.tar.gz` `1ec22edb…`, `…-linux-aarch64.tar.gz` `81cc6d8f…`.
**ALL FOUR ARTEFACTS NOW EXIST, past ADR-099:** the Windows installer was rebuilt by the owner at
`ebed4b6` (2026-09-22 10:35) — `ArcadeRuins-1.0.0-Windows-x64.exe`, 13.6 MB, `bfd06a04…`
(the pre-fix one was `761b33d4…`), the C runtime linked in, **42/42 CTest on those binaries**,
unsigned by decision (ADR-097). `ebed4b6` differs from `ffcc2e6` in STATE.md alone, so all four
are built from the same code. **Windows is GREEN and nothing is owed there** — that run covers
everything from `3ad9d87` on, ADR-096 and ADR-099 included. *A trap worth naming: the aarch64 tarball was left
behind in the first sweep, because `Scripts/release-linux.sh` and `--x86` are two runs and only
the second was started. Its checksum was unchanged, which is how it was caught — **compare the
checksum, not the timestamp**, when a rebuild is supposed to have happened.*

**THE PUBLIC REPOSITORY IS UPDATED — the cross-platform product is public** (2026-09-22, the
owner's word): `badpackets303/ArcadeRuins` at `faa1fd6`, exported from `ffcc2e6`. The previous
export was `4dd7e79`, which predated every bit of X3 and X4, so this published 212 files and
~56,000 lines at once — the JUCE plugin, its tests, the release scripts, the two-product README
and the six new screenshots. Checked before the push: no `docs/private`, no `upstream`, no App
Store assets, no email, and the only "password" matches are prose. Checked after: all 13 of the
README's images return 200 from `raw.githubusercontent.com`. **No tag and no release yet** — the
README says "no download yet", which is true until X4-5.

**⚠️ ADR-096 IS HALF FIXED AND THE REST IS NOT UNDERSTOOD.** The owner, 2026-09-22, on the rebuilt
Windows installer: *"The k in track is getting cut off. Transpose looks ok."* The extra room cured
Transpose. "Pitch Track" still loses its last letter, and **the width is not the reason**: there is
no ellipsis (JUCE's fitter inserts one when it drops glyphs), macOS renders it whole at the
owner's exact window size (1589 × 993, measured in the pixels), and the probe here shows it
measuring 46.2 in an area 84 wide with all 11 glyphs surviving the fitter. So something clips the
last glyph on that renderer, or does not draw it — and `k` draws in "Attack" on the same screen.
**The probe has now answered, and it rules out everything this project controls.** The owner's
run at `ab34455` (Windows green, 42/42, validator 537/537, pluginval 10) reported:
`"Pitch Track": measures 46.2 in an area 84 wide; fitted to 11 glyphs -> "Pitch Track"` — **the
same numbers as macOS to the decimal**, at 1920 × 1080 and 100% scaling. So the metrics match, the
room is ample, and JUCE's fitter keeps every letter: **the glyph arrangement is whole when it
reaches the renderer and the last glyph is simply not painted.** No amount of width or squeeze can
change that. **NEXT, and it is one cheap observation, not a rebuild: resize the standalone's
window** — if the `k` appears at some sizes and not others, it is the stage transform interacting
with Direct2D (the backdrop is `setBufferedToImage(true)`, and turning that off is then the
experiment); if it is cut at EVERY size, the transform is innocent and the glyph run itself is.
**Nothing further is changed from this side until that is known** — two attempts have been made
from here and one was wrong. It is one letter of one caption and **does not block a release**.

**The owner looked again at the Windows caption and said (2026-09-22): "No, it looks ok - let's
move ahead."** Recorded as their judgement of the interface, not as a fix: nothing changed between
the two looks, and the resize experiment was not run. ADR-096 stands as it is.

**X4-5 DONE — Arcade Ruins 1.0.0 IS PUBLISHED, 2026-09-22 15:40 UTC, on the owner's word
("publish"):** <https://github.com/badpackets303/ArcadeRuins/releases/tag/v1.0.0>, four assets,
not a pre-release. Public `main` at `703f44e`, tag `v1.0.0`. **Verified from GitHub's side, not
just from disk:** every asset downloaded back anonymously — all four SHA-256 match the notes
(including the owner's own Windows upload, so nothing was corrupted in transit), the `.pkg` still
answers `accepted / source=Notarized Developer ID` with its ticket stapled *as a downloader
receives it*, the `.exe` is a real PE installer and the tarballs carry their `install.sh`. All
four README links return 200 to a stranger.

**Permanent from this moment** (ADR-093): the AU's `aumu`/`ArRu`/`BP03` and the VST3 class IDs
`ABCDEF019182FAEB4250303341725275` / `ABCDEF011234ABCD4250303341725275`. Changing any of them now
orphans the plugin in every session that ever loaded it. Classic's `ruin` is untouched.

**Shipped with three things stated rather than hidden** — the Windows installer is unsigned
(ADR-097), the Intel half of the universal build is untested (ADR-095), and one Windows knob
caption can lose its last letter (ADR-096, cause found to be below this project: the arrangement
reaching the renderer is whole). All three are in the release notes and the README.

**EVERY DECISION IS SETTLED.**
~~one public repository or two~~ — **ONE** (ADR-098, 2026-09-22, overturning ADR-092's clause 3
before anything was built: the existing public repository is already named `ArcadeRuins` and
already exports this whole tree, and the two products share an engine, a measured layout, the
goldens and the MIDI fixture — a reader with half of it could not run the tests that hold the
halves together). `Scripts/publish-public.sh` is unchanged; there is no second script to write.
**Also settled:** ~~the easter eggs~~ — they stay in the records, user-facing
material stays clean (ADR-097); ~~the version~~ — 1.0.0 and 0.5.x, separate lines (ADR-095);
~~a Windows screenshot~~ — taken, in the README; ~~Windows signing~~ — ships unsigned (ADR-097).
**The Xcode 27 update cost two stumbles worth remembering** (both in CLAUDE.md): a CMake build tree
keeps the absolute path of the SDK it was configured against, so the release build failed on
`MacOSX26.5.sdk/usr/lib/libm.tbd` until the tree was deleted and configured again; and
`/usr/bin/python3` refused to run until the owner agreed the licence.
**ADR-096 — the captions, and a process failure of mine worth more than the bug.** The Windows
screenshot showed "Pitch Trac" and "Transpos". `drawText` CURTAILS (deletes the glyphs that do not
fit, silently) using the advances the renderer computes THROUGH the window's transform — so at
1.1035x Windows cut a letter while its own `PluginTypefaceTests` passed at 1x. Measured, not
guessed: "Semitones" and "Feedback" are identical to the pixel on Windows and Linux, so the face is
the same. Captions and labels are drawn `drawFittedText` now (they squeeze, they cannot be cut),
the room is 20 points a side, and the check measures at 0.75/1/1.1/1.5x and prints its margin.
**Unverifiable here — the owner's next Windows screenshot is the proof.**
**And the process failure:** `cmake --build ... | grep -E " error"` does not match `make: *** Error 2`,
so a FAILING link (the stale-SDK trap, in `build/plugin` this time) looked clean and `ctest` ran
the previous day's binaries — twice reported as 43/43. The tree was deleted, reconfigured and
rebuilt; 43/43 is now genuine. **Read the exit status, never grep the log** (CLAUDE.md).
**Still X4:** X4-3 the host matrix (the owner's hands);
X4-4 the docs — README for the one public repository, release notes, NOTICE.md's JUCE entry
checked, screenshots from three systems, and the Mac product called "Classic" everywhere;
X4-5 the release, **confirmed with the owner before any public push**. And from X3: the
side-by-side sign-off, the 0.75× question, and how the JUCE AU behaved in Logic.

**Before that — the X3 gate, decided and built:**
 The X3 gate is decided and
built (ADR-092, ADR-093, 2026-09-21): the Mac products are **"Arcade Ruins Classic"** (`ruin`,
name only), and the JUCE build ships **an AU of its own — `aumu`/`ArRu`/`BP03`**, installed for the
owner in `~/Library/Audio/Plug-Ins/Components` and passing `auval` and pluginval 10. **The plugin
code changed from `Ruin` to `ArRu` for EVERY format** (JUCE has one code), so the VST3's class ID
changed too — free, nothing had shipped. **auval found a real fault, in every format:** the plugin
reported the engine's note-value snapping from `prepareToPlay`, under the host; it is reported
from the first rendered block now (`PluginParameters`, in auval's numbers; reverted it reads
0.249022 for 0.308594). **Verified:** macOS 43/43, VST3 validator 537/537, pluginval 10 on both
formats, auval SUCCEEDED; Linux arm64 42/42 under GCC 13, validator 537/537, pluginval 10, RealtimeSanitizer clean 41/41. **Windows GREEN at `cd4f30a`** (the owner's run, 2026-09-21 15:24: 42/42 CTest, validator
537/537, pluginval 10 SUCCESS, denormal tail ≤ 1.00×) — so the scoped-Graphics fix holds there and
everything through X3-9 and the Classic rename has passed on all three systems. **Windows owed for
this commit only** (the `ArRu` code, and the snap reported from the block rather than prepare). **Then:** the owner's side-by-side sign-off and the 0.75× question; **Classic is INSTALLED** (the owner's word, Logic closed first: `Scripts/validate-au.sh`, AU VALIDATION
SUCCEEDED; `auval -a` lists `ArRu` "Arcade Ruins" and `ruin` "Arcade Ruins Classic" side by side; what it
replaced was a development build of 0.5.0, not the notarised one);
X4 — packaging (the AU signed and notarised with the rest), the public export, and
the README / release notes that still call the Mac product "Arcade Ruins".

**Windows at `f0075c3` (the owner's run, 2026-09-21 14:48): FAILED on one check, and it was the
TEST** — 41 of 42 CTest, validator 537/537, pluginval 10 SUCCESS, denormals measured (tail ≤ 0.97×).
"the pad's target is half the size it was (measured 0)": the check read the image while the
`juce::Graphics` drawing into it was alive, and on Windows the pixels are not there until it is
destroyed. The owner had hit it at `2d9a5e1` and fixed it there; that fix never arrived here.
Scoped now, and in CLAUDE.md's table. Everything else from `3d6629b` to `f0075c3` — the console,
the focus rings, the pads, the wordmark, the finished power buttons — passed on Windows.
**Windows owed again for the fix's commit** (one check to watch).

**X3-9 DONE 2026-09-21 — the cabinet's red buttons cut and restore the power, chrome and all**
(ADR-091, in `docs/private/cabinet-extras.md` with the rest of the easter eggs). The first cut
greyed the fifteen sections and left the chrome lit, and the handoff suspected the zone
rectangles or `paintDeadZones`. **Neither: a dark render showed the PAINTING grey under all four
chrome zones — what stayed lit was everything DRAWN over it**, each built with the editor's main
style instead of its zone's: the preset's name, the scope's line, the bar's buttons and stepper,
Snap, the status words; and three colours that never went through the style at all — the pads'
CRT frame, the oscillator's wave selector (PaintCode's orange, which the Mac greys by rendering
the control to an image) and the sequencer's playhead ring. `zoneOfItem` gives every header and
bar item its zone, they are built with `styleFor(zone)`, and the three colours go through
`dimmed()`. **The clock is injectable** (`advancePowerTo(seconds)`), as the Mac's is, so the
eight-second cycle is tested in none. Checks, in the PIXELS: nineteen zones; lit, every zone has
colour; cut, **no pixel in any zone has colour** (max − min of RGB ≤ 28); half way, 10 zones are
back and 9 are not; and **ADR-062's own — off and then on again is pixel-identical to never
darkened (0 of 1,296,000 differ)**. Revert-checked three ways: the main style for the chrome
(2,804 coloured pixels in the display, 904 in the bar, 696 in the screen), the wave selector's
orange (91), an envelope plot not handed its colour back (11,627 pixels differ after off-then-on).
**And a second thing only a picture showed:** in a dead section the knobs' CAPTIONS vanished — the
grey painting was laid over the words the backdrop paints, where the Mac greys them. It goes
under them now and the words are greyed by the zone they sit in (`Style::dimmedBy`,
`Backdrop::dimAt`). Check: all 62 captions are still there in the dark (62 vanish with the old
order). **Verified 2026-09-21:** macOS 43/43 CTest, validator 537/537, pluginval 10 SUCCESS; Linux
arm64 42/42 under GCC 13, validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean 41/41. No Swift, Mac source or specification change: the Xcode suite was not needed.
**Windows owed.** *The lesson:* the handoff reasoned about where the fault must be for a
paragraph; one render at 8.6 seconds showed where it was. **Look before deducing.**

**How the greying works, for whoever picks it up.** `s1ui::Style::setDim` greys everything a style
ANSWERS (`colour()`, `accentFor()`, `glow()`), and the editor keeps **one style per zone**
(`styleFor`), so a zone greys alone. But a control keeps the accent it was BUILT with rather than
asking at each paint, so `applyPower` also hands each one the dead colour — that is why the knobs
were still in colour after the first pass, and it is the same thing the Mac does by swapping held
colours (ADR-062). `ParameterControl::setAccent`, `ItemButton::setAccent` and
`EnvelopeView::setColours` exist for it.

**The specification now carries the power table** (`template.power`: the two buttons, the four
chrome zones, `frameReach` 11, the grey painting's name), emitted by the Swift writer — so
`Scripts/write-layout-spec.sh` has been run and **the Xcode suite is GREEN on it: 343 of 343,
2026-09-21** (the Swift writer gained the power table, so the suite was needed for the first time
since X3-6). Windows is green on it too.

**Before this:**
The owner asked for them on 2026-09-21, together with a clean-up of the console (below). What is
done and green: **`s1plugin::PowerCycle`** (the eight-second schedule as a JUCE-free model — zones
shuffled with a seeded generator so a cycle replays identically on every OS, the first settling a
second in and the last at eight, each blinking two to four times in the window before it settles),
and **`s1ui::Style::setDim`**, which is the whole lever: every control draws through `colour()` and
`accentFor()` (ADR-084), so blending those toward their own luminance greys a zone without any
control knowing. 15 checks in `PluginControlsKit`. Nothing is wired to a button yet, and the
default is 0, so nothing has changed on screen.

**What is left, in order:**
1. **The buttons' rectangles are not in the specification.** The Mac has them
   (`S1Skin.swift`: `power: S1TemplatePower(off: rect(128, 879, 158, 911), on: rect(159, 874, 190, 906) …)`).
   The Swift writer (`Tests/SynthOneTests/LayoutSpecFixtureTests.swift`) must emit `template.power`,
   then `Scripts/write-layout-spec.sh` (SDKROOT **unset**) regenerates `layout-spec.json` — which
   means **the Xcode suite is needed for this task** (343 tests), unlike X3-4 … X3-8.
2. **A Style per zone in the editor** (`styleFor(zone)`), with every control built from its own
   zone's style: a control's zone is its `section`; items go to "display" (the preset field),
   "buttons" (the toolbar), "screen" (the scope) and "bar" (the play and status bars).
   `tearDownSkin` clears them, `applySkin` rebuilds them.
3. **The backdrop draws the dark zones**: Cabinet from `s1_template_cabinet_dark@2x.jpg` (it is in
   the Mac's assets, 707 KB, NOT yet linked into `ArcadeRuinsArt` — one line in
   `Sources/S1Plugin/CMakeLists.txt`), cropped to the zone's rectangle and 11 points past its inner
   edge to take the frame and its glow; Studio by drawing that section's panel again with a dimmed
   style.
4. **The two buttons** as invisible hit areas over the painted ones, as the header's are, and the
   cycle driven by the editor's 30 Hz timer.
5. **Tests**: the zones' pixels measured dark and lit, and ADR-062's own check — **a render after
   off-then-on is pixel-identical to one never darkened**.

**And the console clean-up, which is the owner's to approve first.** They asked (2026-09-21) to
remove "the 3 yellow buttons that don't do anything" and fill with the cabinet texture around
them, and asked for a **mockup before implementing** — sent the same day (a detail pair at window
size and magnified, and the whole window). The fill was made with a Laplace solve from the console
pixels around the buttons plus the console's own speckle; the three buttons that STAY (the two
power buttons and the small red one above) are pixel-for-pixel untouched. **If they say yes, the
right home for it is the artwork itself** — `Scripts/branding/` and the `.imageset` — not a patch
in code, and the owner may prefer to repaint that patch by hand.

**After X3-9: X4 (packaging and release).** Read PORT_PLAN's X4 rows and the
plan page. Two pieces of X3-scope work are parked by agreement and are the obvious things to offer
first:
- **The red power buttons** (ADR-062's greyscale cycle), the last easter egg, its own task.
- **MIDI Learn** (deferred for 1.0, ADR-056) and the recorder are deliberately NOT in this
  interface; the play bar's MIDI Learn button is not built.
Also open: the owner's side-by-side sign-off of the interface against the Mac app (X3-3's, still
listed as open in PORT_PLAN), and whether 0.75x is a comfortable floor for the window (X3-7).

**X3-8, verified 2026-09-21:** macOS — 43/43 CTest (new: `PluginKeyboard`, 29 checks, and the two `EditorSnapshotKeyboard…`; `PluginEditor` is 147 now), Steinberg's validator 537/537, pluginval 10 SUCCESS. **Revert-checked three times**: letting the drawer shift the note as well as the router fails the "applied once" check at 84 where it should read 72; delivering the interface's events one sample later fails the sample-for-sample acceptance at 1.03e-4. The state's fixture was rewritten — purely additive, four lines — and a state with the field removed is held to loading. The third revert came from LOOKING at a render: the keys lit for a click and for nothing else, so a note the HOST plays now lights its key too, with a check that fails when the router's report is dropped. Linux arm64 in Docker — 42/42 CTest under GCC 13 (macOS has one more; the keys built, driven and drawn there), validator 537/537, pluginval 10 SUCCESS under xvfb, **RealtimeSanitizer clean (41/41 under Clang 20)** — the interface's MIDI queue and the held-key report allocate nothing on the audio thread. Windows — **owed for this commit**. No Mac product source, no Swift and no specification change: the Xcode suite was not needed.

**X3-7, verified 2026-09-21:** macOS — 40/40 CTest (new: `EditorSnapshotLaptop`, the 0.85× window painted; `PluginEditor` is 119 checks now, 14 of them the scaling's), Steinberg's validator 537/537, pluginval 10 SUCCESS **with its editor tests on a resizable window**. **Revert-checked four times.** Taking the transform out fails eleven checks — 55 controls outside the window, the geometry at 0.75×, 1.25× and 1.5×, the clicks, the centring, both cards, and the border at 1.5× (blue 13, where the interface is not drawn at all). Taking the letterbox fill out failed nothing until the check stopped counting alpha and started reading the margin's colour; six of six sample points fail now. And buffering the whole stage — the mutation that should have blurred a 1.5× window — changed nothing, which is the finding: JUCE renders a cached component at the scale it is drawn at. **And a fourth, after the owner's Windows run:** half a pixel of offset on the transform drops the measured border from blue 185 to 62 — which is what the replaced check reads, and what the first version of it could not see. Linux arm64 in Docker — 39/39 CTest under GCC 13 (macOS has one more; the scaled window is drawn there too, and the border reads its own colour at 1.5× under another renderer — run again after the check was replaced), validator 537/537, pluginval 10 SUCCESS under xvfb, **RealtimeSanitizer clean (38/38 under Clang 20)** — nothing about a window reaches the audio thread. Windows — 39/39 CTest, validator 537/537, pluginval 10 SUCCESS at `a9d5b6a`, with the x86 denormals measured again. No Mac product source, no Swift and no specification change: the Xcode suite was not needed.

**X3-6, verified 2026-09-20:** macOS — 38/38 CTest (new: `PluginTypeface`, 8 checks; `PluginControlsKit` is 81 and `PluginEditor` 105 now), Steinberg's validator 537/537, pluginval 10 SUCCESS, **343 Xcode tests green** (the Swift spec writer changed, so `layout-spec.json` was regenerated and its check-mode test had to agree). **Revert-checked twice, and one of them found a check that could not fail**: letting the bezel's glow paint inside the frame fails at 1,200 pixels (that bug was seen by eye first, in a render); applying the joystick's dead zone to the PICTURE as well as the pitch passed the first version of its check, because the check read back the number it had just written — it measures the pixels now and fails at 0. **Linux found a third**: the typeface test measured the raw specification text, not what the editor draws, and two labels did not fit there where a font-less container substitutes the Option sign. Linux arm64 in Docker — 37/37 CTest under GCC 13 (macOS has one more; the linked typeface, the bezel, the starfield and the joystick all built and drawn there), validator 537/537, pluginval 10 SUCCESS under xvfb, **RealtimeSanitizer clean (36/36 under Clang 20)** — the joystick's mod wheel goes through an atomic, not the kernel. Windows — 38/38 CTest, validator 537/537, pluginval 10 SUCCESS at `8d12e71` (their third run of the evening; the first two found the nested-lambda build failure and the script's stale passes). **The Xcode suite WAS needed this time** (Swift + specification).

**X3-5, verified 2026-09-20:** macOS — 37/37 CTest (goldens bit-exact; new: `PluginTunings`, 58 checks, and the two `EditorSnapshotTunings…`; `PluginEditor` is 80 checks now), Steinberg's validator 537/537, pluginval 10 SUCCESS. **Revert-checked twice**: stop applying a preset's tuning and four checks fail (the eleven-preset acceptance among them); stop A4 moving the table and four more fail, the heard one included. **Three measurement lessons, each after a check failed** — an interval is measurable where a pitch is not (a preset may sound an octave below the key); not under any sound (a preset with two detuned oscillators reads 292 cents where its scale says 315, so the scale goes under the shipped Init instead); autocorrelation locks to the octave below and a window at the note's start catches the glide. Linux arm64 in Docker — 36/36 CTest under GCC 13 (the tuning model, its card and the pitch wheel built, driven and painted there), validator 537/537, pluginval 10 SUCCESS under xvfb, **RealtimeSanitizer clean (35/35 under Clang 20)** — rebuilding a tuning table allocates, and it is never done on the audio thread. Windows — green at `8d12e71`, with X3-6. No Mac product source, no Swift and no specification change: the Xcode suite was not needed.

**X3-4, verified 2026-09-19:** macOS — 34/34 CTest (goldens bit-exact; new: `PluginPresetBrowser`, 101 checks, and the two `EditorSnapshotPresets…`; `PluginEditor` is 69 checks now), Steinberg's validator 537/537, pluginval 10 SUCCESS. **Revert-checked three times**: taking the uid dedupe out fails two checks (that is how the shipped banks' 23 repeated uids were found — a reorder moved a preset in another bank); dropping the banks' order file fails the reopened-browser check — **after the first version of that check could not fail**, because the twelve bundled names order themselves, so it now makes a thirteenth bank, renames it to sort first and reads it back; taking the view's reorder guard out fails four. Linux arm64 in Docker — 33/33 CTest under GCC 13 (the browser's model and its card built, driven and painted there), validator 537/537, pluginval 10 SUCCESS under xvfb, **RealtimeSanitizer clean (32/32 under Clang 20)**. Windows — owed (above). No Mac product source, no Swift and no specification change: the Xcode suite was not needed.

**X3-3, verified 2026-09-19:** macOS — 31/31 CTest (goldens bit-exact; new: `PluginEditor`, 38 checks, and the two `EditorSnapshot…`), Steinberg's validator 537/537, pluginval 10 SUCCESS **with its Editor, Open-editor-whilst-processing and Editor-Automation tests run on the real window** (260 ms to open). Revert-checked: Panic's test fails at 0.387 without the event — after its FIRST version passed without it (a preset that dies by itself; ADR-085). Linux arm64 in Docker — 30/30 CTest under GCC 13, validator 537/537, pluginval 10 SUCCESS under xvfb (the editor opened there), **RealtimeSanitizer clean (29/29) — the panic event and the scope's ring allocate nothing**. Windows — owed (above). No Mac product source, no Swift and no specification change: the Xcode suite was not needed.

**X3-2, verified 2026-09-19:** macOS — 28/28 CTest (goldens bit-exact; new: `PluginControlsKit`, 70
checks, and the two `ControlsKitSheet…`), Steinberg's validator 537/537 + pluginval 10 SUCCESS, **343 Xcode tests green** (the regenerated specification's check mode among them); revert-checked (a drag sensitivity of 0.004 and a border drawn off the half-point each fail their checks). Linux arm64 in Docker —
27/27 CTest under GCC 13 (the kit built, driven and painted there with no window and no fonts installed), validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean (26/26 under Clang 20). Windows — owed (above). No Mac product source changed: nothing rebuilt,
reinstalled or `auval`ed; the Swift spec writer changed and the JSON was regenerated.

**X3-1, verified 2026-09-19:** macOS — 25/25 CTest (goldens bit-exact), Steinberg's validator
537/537 + pluginval 10 SUCCESS, **343 Xcode tests green** (one new: the spec's check mode;
revert-checked — a frame moved 3 points in the JSON fails it, and fails the app comparison at
"3.00 points off"); no Mac product source changed, so nothing was rebuilt or reinstalled and
`auval` was not needed. Linux arm64 in Docker — 24/24 CTest under GCC 13 (the specification read and both wireframes drawn there), validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean (23/23 under Clang 20). Windows — owed.

**How work is verified now — THERE IS NO CI** (ADR-079's amendments: GitHub refuses to start this
private repository's Actions jobs over billing, the owner will not change that, and **the
repository must never be made public** — history with their email, `upstream/` with AudioKit's
Audiobus key, AudioKit's screenshots, `docs/private/`). Three scripts instead:
1. **macOS, here:** `export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)`, then
   `cmake -S . -B build/plugin -DS1_BUILD_PLUGIN=ON && cmake --build build/plugin -j 10 &&
   (cd build/plugin && ctest)` — 31 tests, the goldens bit-exact; `Scripts/validate-plugin.sh`
   (Steinberg's validator + pluginval strictness 10, built from pinned sources into
   `build/validation`). **Engine or Mac-source changes also need** the Xcode suite (342 tests;
   command in CLAUDE.md, run with `SDKROOT` UNSET), `Scripts/build.sh` and
   `Scripts/validate-au.sh` (signed build, install to /Applications, `auval`).
2. **Linux, here, in Docker** (Docker Desktop must be running):
   `Scripts/validate-linux.sh [all|tests|validate|rtsan] [--x86]` — GCC build, every test, both
   validators, the RealtimeSanitizer under Clang 20 (the test for "nothing allocates on the
   audio thread").
3. **Windows, on the owner's machine** (Windows 11, Visual Studio 2026 Community, from "Developer
   PowerShell for VS 2026" in their clone of the PRIVATE repo): `git pull`, then
   `powershell -ExecutionPolicy Bypass -File Scripts\validate-windows.ps1`; they paste back the
   block between the ===== lines. **Ask for one run at the end of each task; until it arrives say
   here that Windows is owed for that commit.**

**The working pattern for every X task** (the owner says "Proceed with X3-n"): branch → tests
first where a behaviour is measurable → macOS + Linux green → an ADR (next free: **ADR-086** —
check the end of `docs/01-decisions.md`) + `Sources/S1Engine/PORTING.md` / `Sources/S1Plugin/
README.md` / `CLAUDE.md` gotchas / `PORT_PLAN.md` / this file with a handoff for the next task →
`git merge --no-ff` to `main`, push to the private origin → republish the plan page (its HTML
source is kept at `docs/private/arcade-ruins-vst-plan.html` — version 32 as of 2026-09-19; edit
THAT file, publish it to the same URL with the artifact tool, and commit it; `docs/private/` never
reaches the public mirror) → the memory file → ask for the Windows run. Small scope calls: decide, then
tell the owner — they found multi-option menus confusing. Commits end with the
`Co-Authored-By: Claude …` line the session gives. Revert-check new tests (remove the fix, see
the test fail, restore — and rebuild the library target explicitly: make keeps stale objects).

**Lessons X2 paid for** (details in CLAUDE.md's gotcha table): test with sounds that USE the thing
(a no-sustain patch found the transport bug, short effects the denormals, the compressing Init
the compressors' sample-rate bug); the kernel's notes and the router's keys must be dropped
TOGETHER; a preset's fields are not its parameter values — load through a scratch kernel in
upstream's order, never field by field; never apply a preset to the rendering kernel; cross-OS
expected numbers must be exact decimals (FMA); timing assertions take the quickest of three
runs; pluginval SKIPS Steinberg's validator unless handed one and still says SUCCESS; never
leave test by-products in the owner's `~/Library/Application Support`.

**What changed in the Mac products during X2** (all from faults the new tests found; the signed
build in /Applications is current as of 2026-09-18, `auval` passed): values set just before
allocation survive it (ADR-073) · a transport stop is an all-notes-off and no longer eats the next
phrase's first note (ADR-077) · denormal protection in the render block (ADR-078) · voices made
before the first render, no allocation per arpeggio note (ADR-079) · compressors at the right
speed at 48/96 kHz — audible (ADR-080) · keys no longer swallowed after a re-prepare (ADR-081) · a
host's tempo change keeps note values (ADR-082). Goldens 20 of 20 bit-exact throughout.

---

## The macOS port (Phases 0–8) — as it stood at 0.5.0; untouched by the X work except as listed above

> **This header was last rewritten on 2026-09-14 and is kept as the port's record.** Since then: 0.4.0 and 0.5.0 shipped (the Cabinet skin replaced Neon Ruins, ADR-059–064; `MARKETING_VERSION` is 0.5.0), the work moved to **`main`**, and everything since 2026-09-17 has been the cross-platform track above. For the Mac port's own current facts read CLAUDE.md and the ADRs; for what to do next, read the section above.

**Last updated:** 2026-09-14 (0.3.0 released) · **Repo:** `~/Developer/SynthOne` →
[badpackets303/SynthOneMac](https://github.com/badpackets303/SynthOneMac) (**private**); public mirror
[badpackets303/ArcadeRuins](https://github.com/badpackets303/ArcadeRuins)
**Branch:** `desktop-ui` (version **0.3.0**, build 3; 0.2.0 was P6-8's release prep, commit `349e1cd`). `main` and tag `v0.1.0-classic-ui` are the classic
interface as shipped.
**Phase:** 8 — layout revisions at the owner's direction. P8-0 (preset drop-down, ADR-047) and P8-1 (LFO section, bigger knobs, OSC 2 spacing) done 2026-09-13; P7-4, the Neon Ruins skin (ADR-048), done 2026-09-14; the next task is whatever the owner asks. 0.2.0 and 0.3.0 both wait on the owner's release decisions. · **Track A (Mac
Catalyst)**, ADR-001 · **Product: Arcade Ruins** (ADR-029)
**Blockers:** none · **Health:** **no failing test on this branch.** Desktop suites (`DesktopLayoutTests` 22,
`DesktopPluginTests` 5, `SkinTests` 11) 38/38 on 2026-09-14 after P7-8, plus `UILoadTests` and `AudioUnitPackagingTests` — 54 green in one run. The 58-test run at P7-6 also covered `MacIdiomControlTests`, `StorageIsolationTests` and `LaunchPromptTests`. **The full suite has not been re-run since
P6-8** — run it once before a release (about 20 minutes; see the stall below). Full suite 2026-09-12: 284 test
cases passed, 0 failed; xcodebuild reports TEST FAILED only because the first `xctest` process was
killed by hand while `StorageIsolationTests.testCachesSavesIntoTheTemporaryFolder` sat inside an
`open()` on one of the owner's real support folders (`snapshotOfTheRealFiles`, sampled). xcodebuild
restarted, and the same test then took **18 minutes** in that `open()` before passing, so it is a stall
on a real folder (a group container or the legacy folder answering slowly), not a hang and not this
branch's code. Worth a look before it costs another session: time `contentsOfDirectory` on
`Disk.defaultSharedSupportURL`, `Disk.legacySharedSupportURL` and `Disk.defaultSettingsURL`. The 8 new
`DesktopLayoutTests` were run separately (project regenerated after the full run started) and pass;
`UILoadTests` 8/8. · Debug builds signed by team 8RSH7U3222 · `auval` not re-run on this branch yet
**Cross-platform track (X-tasks, PORT_PLAN.md §6, plan page <https://claude.ai/artifact/9zr5fP3KeuYMt5kvcmcaDH>) — **X1 COMPLETE 2026-09-18; X2-1 … X2-10 DONE 2026-09-18 (ADR-072–081); ▶ next: the X2 GATE — the owner's. ✅ 2026-09-18: the owner confirmed ADR-081's hands-on list ON WINDOWS (standalone opens, hardware keyboard plays with no setup, survives an audio device change, device and sound return after a quit). ✅ 2026-09-18 22:31: the Windows script's block for `main` @ `a57f59b` (X2-9 + X2-10 in it): 21/21 CTest, validator 537/537, pluginval 10 SUCCESS, RESULT: PASSED — **Windows owes nothing for X2.** ✅ 2026-09-18: the owner ran the JUCE standalone on the MAC — "Seems to work ok." ✅ and answered the tempo question: **"yes, the LFO and delay should match up with the tempo" → DONE, ADR-082** (branch `x2-tempo-keeps-note-values`, merged): a tempo change keeps the NOTE VALUE of what is synced — a host's tempo always (`handleTempoSetting` → `_setTempoKeepingNoteValues`; JUCE plugin AND Mac AUv3), the `arpRate` parameter where `kernel->tempoParameterKeepsNoteValues` is set (on in the JUCE plugin, off in the Mac products), `s1::Preset::apply` always switches it off while it runs (goldens bit-exact), and `loadPreset` under a host tempo moves a preset's synced values to the host's tempo by note value; a note value that does not fit the range at the new tempo falls back to the nearest that does. NOT done: the Mac STANDALONE app's own tempo control (its preset loading writes `arpRate` from three places — offered as a follow-up). Verified: 22/22 CTest, validators, **342 Xcode tests green, goldens 20/20 bit-exact, signed build installed 2026-09-18, `auval` passed**; Linux Docker 21/21 + validators + RealtimeSanitizer clean; ✅ Windows for ADR-082: the owner's run of 2026-09-19 09:31 at `ea8fd00` — 21/21 CTest, validator 537/537, pluginval 10, RESULT: PASSED. **Nothing is owed on any OS.** **STILL OPEN at the gate: ONE question — voice-freeing every frame for the Mac products too (ADR-074; 12 of 20 goldens rewritten)?** Not blocking: X3 can start; the answer only changes the Mac products. (2026-09-19: the owner was unsure and asked how the original handled it; explained — upstream frees once per buffer, so arpeggios vary with buffer size and there is no single original sound for them; **recommended: leave the Mac products as they are and decide at the X3 gate**, where the Catalyst products' future is decided anyway. Awaiting their word; do not change the Mac products without it.) (Windows: verified, see below.)** **X2-10 (ADR-081):** the standalone = JUCE's `StandalonePluginHolder` + `StandaloneFilterWindow` with OUR application object (`Sources/S1Plugin/S1StandaloneApp.cpp`, `JUCE_USE_CUSTOM_PLUGIN_STANDALONE_APP=1`, Standalone target only): **every MIDI input opens by itself, one plugged in later too** (JUCE opens none on a desktop), settings in `<application data>/BadPackets/Arcade Ruins/Arcade Ruins.settings` beside the banks (device, window, and the plugin's state, so it reopens on its sound); no audio input (no bus → no microphone prompt, no feedback notice); the internal tempo is the `arpRate` parameter (no play head, ADR-077). **`PORT FIX`: `prepareToRender` now empties the host-MIDI router's keys (`S1HostMIDI::kernelWasPrepared`)** — `init` dropped the voices but the router kept the keys, so a key held across an audio device change (or any host's re-prepare, the Mac AUv3's too) was swallowed when next played: ADR-077's fault through another door. **Checked live on this Mac:** opened at the device's 48 kHz, all MIDI inputs open unasked (IAC + the owner's M4 and SL GRAND ports), a virtual CoreMIDI keyboard created AFTER launch was picked up and its mod wheel reached the render thread (saved `cutoff` 2,000 → 360), quit wrote the version-1 state, a relaunch restored it; the file that check wrote was moved out of the owner's folder. `Tests/Plugin/PluginStandaloneTests` (new CTest): the processor in `juce::AudioProcessorPlayer` with a stand-in device — 48 kHz/512 → stops → 96 kHz/256 with a key held (settings kept, old note silent, **the same never-released key plays again** — 0 before the fix) → 44.1 kHz with callbacks of 1,024/37/480 frames → 25 more restarts, still in tune. **Verified:** macOS — 22/22 CTest, validator 537/537 + pluginval 10, **341 Xcode tests green, goldens 20 of 20 bit-exact, signed build installed 2026-09-18, `auval` passed**; Linux arm64 in Docker — 21/21 CTest under GCC (the standalone's app object compiles there), validator 537/537, pluginval SUCCESS, RealtimeSanitizer clean. **THE X2 GATE (the plan page has the owner's list):** (a) the Windows script's block for the current `main`; (b) by hand on macOS and on Windows — open the standalone (the script prints its path on Windows; here `build/plugin/Sources/S1Plugin/ArcadeRuins_artefacts/Release/Standalone/Arcade Ruins.app`), play a hardware keyboard without touching a setting, change the audio device or its sample rate while it sounds, quit and reopen; and the VST3 in a Windows host and (for the Mac AUv3's fixes) Logic; (c) THREE things to settle or hear: **voice-freeing every frame for the Mac products too?** (ADR-074; 12 of 20 goldens rewritten) · **tempo-synced values keep their note value across tempo changes?** (ADR-077; both products, an engine change) · **told, not asked:** the Mac AUv3 changed in four ways during X2 — transport stop is an all-notes-off and no longer eats the next phrase's first note (ADR-077), denormal protection (ADR-078, inaudible), voices made before the first render and no allocation per arpeggio note (ADR-079, inaudible), **compressors at the right speed at 48/96 kHz (ADR-080 — audible on presets that lean on them)**, and keys no longer swallowed after a re-prepare (ADR-081). After the gate: X3 (the interface), starting from the plan page's X3-1; `S1ParameterCatalog`, `isUsingHostTempo()`, `arpBeatCounter()`, `loadPreset(…, asEdit)`, `saveCurrentPreset`, `presetLibrary()` are what X2 left for it, and X3-8 owes MIDI program change, X3-5 the preset's tuning. **X2-9 (ADR-080):** `Sources/S1Plugin/S1PresetLibrary.hpp/.cpp` (no JUCE) — FACTORY banks = the Mac app's thirteen files linked in as JUCE binary data (`S1PresetData`), byte for byte, parsed on first use (never at a host's scan), in `S1FactoryPresets.bankOrder`; USER banks = `<name>.json` arrays (the Mac app's bank format) in `<user application data>/BadPackets/Arcade Ruins/Banks` (`S1SharedPresets::defaultUserDirectory()`; macOS `~/Library/Application Support/…`) — NOT the Catalyst App Group: side by side, neither writes in the other's; read at every listing, written whole beside then renamed, problems named, safe file names. **A host's programs = the 695 factory presets numbered and named as the Mac AUv3's**, held to `S1FactoryPresets` by a Swift-written fixture (`FactoryProgramFixtureTests` → `Tests/Plugin/Fixtures/factory-programs.txt`, `Scripts/write-factory-program-fixtures.sh`; lines only ever added at the end). `loadPreset(preset, asEdit)` — values through a scratch kernel in upstream's order (0.11 ms), wheel centred, name and routing, sequencer reset, **tuning table left alone (X3-5)**; `asEdit` = a gesture per changed parameter (X3-8's browser), a host's program change = reports without gestures; `saveCurrentPreset(bank, name)` via `PluginState::capturedPreset`; a session saved on a factory preset reopens showing it. JUCE changes programs on the controller thread, never in `process`. **MIDI program change stays unhandled until X3-8** (render thread; needs a "current bank"). **Found and changed: the plugin did not start with Init** — `s1::Preset()` (the model's bare defaults) is 28 parameters from the shipped Init (factory bank `User`, the golden "User--Init"): bend 0 vs ±12, compressors at their stops, cutoff 4 k vs 2 k, sync on; it starts with the shipped one now and shows a host "User: Init" (the last program). **`PORT FIX`: the three compressors were built in the kernel's CONSTRUCTOR at the constructor's sample rate and never again — 9% too fast at 48 kHz, 2.2× at 96 kHz, in the Mac AUv3 too; `init` re-makes them (`S1Compressor::prepare`).** Found because the shipped Init compresses: `PluginRender`'s plugin (constructed 44.1 k, prepared 96 k) stopped equalling its reference (constructed at 96 k); goldens bit-exact. New CMake target `S1AllTests` (every test executable; what the sanitizer stage builds). `Tests/Plugin/PluginPresetTests` (new CTest). **Verified:** macOS — 21/21 CTest (goldens bit-exact), validator 537/537 + pluginval 10 with 695 programs, **341 Xcode tests green, signed build installed 2026-09-18, `auval` passed**; Linux arm64 in Docker — 20/20 CTest under GCC, validator 537/537, pluginval SUCCESS, RealtimeSanitizer clean; nothing touched the owner's real `Application Support/BadPackets` folder. **HANDOFF — X2-10:** the standalone shell. JUCE's standalone wrapper already builds (`Arcade Ruins.app` / `.exe`), with its audio/MIDI settings dialog; the work is (1) **try it** — does it open, take a hardware keyboard, make sound, keep its device settings between launches (JUCE's `StandalonePluginHolder` saves them in a `PropertiesFile` under the same application-data folder — check the folder name it uses against ours); (2) **ADR-043's failure** — the Catalyst standalone went silent when the audio hardware changed (headphones, a sample-rate switch) and had to restart its engine: check what JUCE's holder does on a device change (`audioDeviceAboutToStart` → `prepareToPlay` again at the new rate — X2-9's compressor fix and X2-2's carried parameters are exactly what that path needs) — on macOS here and on Windows by the owner; (3) an internal tempo: with no play head the `arpRate` parameter IS the tempo (ADR-077) — confirm in the running standalone that the generic editor's Tempo moves the arpeggio; (4) decide the standalone's options (`JUCE_USE_CUSTOM_PLUGIN_STANDALONE_APP`? mute-input default, no audio input at all — the synth has none: `isBusesLayoutSupported` refuses inputs, check JUCE's "feedback loop" warning does not show); (5) what cannot be automated here is a manual check for the owner on both OSes — write them the three-line list. Acceptance per the plan page: opens, plays from a hardware keyboard, survives an audio device change on macOS and Windows. Then the **X2 gate** (two owner questions: voice-freeing for the Mac products; note values across tempo changes — and now a third thing to tell them at the gate: the Mac AUv3's compressors were rate-dependent and are fixed). **THERE IS NO CI NOW (ADR-079's amendments; the owner's decisions of 2026-09-18):** GitHub stopped starting this repository's jobs ("recent account payments have failed or your spending limit needs to be increased"), the owner will not change the billing and the repository must NEVER be made public for free minutes (history with their email, `upstream/` with AudioKit's Audiobus key, AudioKit's screenshots, `docs/private/`). **Verification is three scripts:** macOS here (`ctest` in `build/plugin`, `Scripts/validate-plugin.sh`, the Xcode suite; `Scripts/build.sh` + `Scripts/validate-au.sh` for engine or Mac sources), **Linux here in Docker** (`Scripts/validate-linux.sh [all|tests|validate|rtsan] [--x86]` — Ubuntu 24.04, GCC 13, every CTest test, Steinberg's validator, pluginval under xvfb, the RealtimeSanitizer under Clang 20; Docker Desktop must be running; build trees in the volume `arcade-ruins-linux-arm64`), **Windows on the owner's machine** (`Scripts\validate-windows.ps1`: VS 2022 C++, CMake, Git; prints a block to paste back). A task merges when macOS and Linux are green and says here whether Windows has been run. The workflows stay (macOS out of their matrices, pinned, the Linux fixes below applied) for the day jobs start again. **X2-8 (ADR-079):** pluginval `v1.0.4` at strictness 10 **passed on macOS, Linux and Windows on its first run** (CI run 35381919830, the last before the block) — but **pluginval SKIPS Steinberg's validator unless handed one and still prints SUCCESS**; the validator (built from the SDK pinned at `v3.8.0_build_66` / `9fad9770…`) then found the one fault: the host's single program had no name (536 of 537) — `getProgramName` is the sound's name now, "Init" when blank (checked in `PluginState`): **537 of 537 on macOS and on Linux**, pluginval SUCCESS on both with nothing skipped but what must be (on Linux pluginval cannot run the validator — it hands it the `.so` inside the bundle, which SDK 3.8 refuses for any plugin — so there the validator runs by itself; the SDK also needs `gtkmm-3.0` to configure on Linux). **The RealtimeSanitizer (`-DS1_RTSAN=ON`: `S1_NONBLOCKING` = `[[clang::nonblocking]]` on `process`, `processWithEvents`, `processBlock`, empty in every other build) found two allocations on the audio thread on its first run — both upstream's, both in the Mac products, both `PORT FIX`ed, goldens bit-exact after each:** (1) the voices were made lazily in the FIRST `process` call (seven note states × a dozen Soundpipe modules, each a `malloc`) — `prepareToRender` makes them now; (2) `S1Sequencer::sequencerLastNotes` was a `std::list<int>` — a node allocated per arpeggio note and freed when it is turned off — now a `std::vector<int>` at a fixed capacity (still RESIZED to 1,024 zeros by `reserveNotes`, upstream's oddity, kept). After both: every test under `-fsanitize=realtime`, no finding, parameter reports from the audio thread included. (The sanitizer stage leaves the test `Goldens` out: Clang 20 on arm64 Linux is 10/20 bit-exact and puts one preset at relative RMS 0.0042 vs the 0.0032 limit; not a product toolchain; GCC there is 20/20 within tolerance.) **Verified on the final tree:** macOS — 20/20 CTest, validator 537/537 + pluginval 10, **340 Xcode tests green, goldens 20 of 20 bit-exact, signed build installed 2026-09-18, `auval` passed**; Linux arm64 in Docker — 19/19 CTest under GCC, validator 537/537, pluginval 10 SUCCESS, RealtimeSanitizer clean; Linux x86-64 (emulated, `--x86 tests`) — 19/19 CTest under GCC, the goldens within tolerance without fused multiply-add. **HANDOFF — X2-9:** the preset library on disk — factory banks in the bundle (JUCE binary data or files beside the binary; 695 presets, 8 bank JSONs in `Sources/SynthOneCore/Presets/Data`), user banks in the platform's application-support folder; **load every preset through a scratch kernel in upstream's apply order (ADR-076)** and as an EDIT that tells the host (gestures), unlike `setStateInformation`; programs for the host (`getNumPrograms`/`setCurrentProgram` — the validator reads the list and wants every name non-empty); program change and bank select from MIDI arrive at `hostMIDIControlDidArrive` already (ADR-075). **X2-7:** denormal protection — **`juce::ScopedNoDenormals` is the first statement of `processBlock`**, and the Mac products' render block has the same (`S1ScopedFlushToZero` in `S1AudioUnit.mm`: `fegetenv` / `fesetenv(FE_DFL_DISABLE_DENORMS_ENV)` / restore); not in the engine itself — the mode is per thread and the host's to own (PORTING.md). **Measured first** (`Tests/Plugin/PluginDenormalTests`: chord 4 s + tail, per-second median block times, through the plugin, the bare engine, and the bare engine under the guard): the engine's effects run without notes and decay INTO subnormals and stay — output subnormal for 1.89 M samples of a minute and parked at 1.4e-45, same on three OSes; unprotected on the CI's x86 machines silence costs 1.25–1.5× per block on Linux, 1.15–1.8× on Windows, a long release on Windows 1.39× the held chord, ~5% on Apple Silicon; protected, no tail second above 1.01× the sounding part and the guard costs nothing while sounding. **Not heard:** `GoldenHarness --flush-to-zero` → 20/20 goldens still bit-exact (new CTest `GoldensFlushToZero`, Apple only); `PluginRender` still exact. **CoreAudio does not flush for us** (probe: 1e-20 × 1e-20 = 1e-40 on an `AVAudioEngine` render thread, macOS 27 arm64). `PluginDenormals` (new CTest): the mode seen from a play head inside `processBlock` (0) and handed back after (1e-40), zero subnormal samples out in 3 × 40 s × three sounds, dearest tail second ≤ 1.25× sounding on the quickest of three performances (the first CI run read 1.48× for one second on a busy runner — noise only adds time); revert-checked (mode check fails, 3.6 M subnormal samples). Swift `testTheRenderFlushesSubnormalsAndHandsTheModeBack` for the AU (revert-checked). 20/20 CTest; CI `plugin` run 35372776286 and `engine` run 35372776297 green on three OSes; **340 Xcode tests green, goldens 20 of 20 bit-exact, signed build installed 2026-09-18, `auval` passed.** **HANDOFF — X2-8:** validation. `pluginval --strictness-level 10` on the built `.vst3` on all three OSes in CI (pluginval releases have binaries for macOS/Linux/Windows — download a PINNED version by URL + checksum in `plugin.yml`, do not build it; Linux needs a display: `xvfb-run`; `--validate-in-process`, `--skip-gui-tests` only if the generic editor cannot open headless — try with it first; keep its log as an artefact) and Steinberg's VST3 `validator` (JUCE fetches the SDK sources: `juce_vst3_helper` is not it — check whether the bundled SDK builds `validator`, else build it from the pinned VST3 SDK in CI). **No `auval` for the JUCE build: it has no AU (ADR-055/058)** — the plan row's auval line is the Catalyst AUv3's, which `Scripts/validate-au.sh` already runs. Expect findings: level 10 fuzzes parameters from several threads, changes sample rate/block size repeatedly, calls `setStateInformation` with junk, runs `processBlock` with 0 samples and large blocks, and checks `getTailLengthSeconds`, bus layouts and editor lifetime — the places to look are `prepareToPlay` called repeatedly (it re-runs `prepareToRender`: leaks? X1-6 fixed the kernel's), a 0-frame block (`processWithEvents(0, …)`), blocks larger than the `maximumExpectedSamplesPerBlock`, state calls racing `processBlock` (`identityLock`, the atomics), and parameter notifications from the audio thread (ADR-073; pluginval may flag them — read what it says before changing anything). Fix what it finds with a test in `Tests/Plugin` for each. Still carried: **RTSan** (Clang 20) on `processBlock` — X2-8 is the natural place (a CI job with `-fsanitize=realtime` on the plugin tests). **X2-6:** host tempo and transport in the JUCE plugin = the play head read at the top of every `processBlock` (`readHostTransport`; valid nowhere else) into the kernel's own `handleTempoSetting` / `handleTransportState`, tempo then transport, before the block's first sample — the AUv3's order (ADR-025); no transport struct was needed. **While the host has a tempo it IS the tempo: `arpRate` is reported, not obeyed** — skipped when host parameters become events, read back after the render and put back to the host's tempo (an output parameter change, no gesture); a session saved at 90 BPM plays at the host's 120 from its first block; no play head / no position / no bpm / NaN → the parameter applies (the standalone). `isUsingHostTempo()` and `arpBeatCounter()` are there for X3. **Two `PORT FIX`es in `S1DSPKernel::handleTransportState`, both defects of our own P4-5 handler and both in the Mac AUv3:** (1) the stop left every key down — an arpeggio went on after it, and the host MIDI router (which does not press a key already down) swallowed the same key's next note-on when the host had sent no note-off: **a stop is an all-notes-off now** (`S1HostMIDI::transportDidStop` = CC123's lines; `stopAllNotes` without the router); (2) it released voices with two of `turnOffKey`'s FOUR lines — the envelopes never saw the gate fall, so a voice already under the release threshold (any sound with no sustain) was freed with its envelope held open and **the first note of the next phrase was silent**; the two `sp_adsr_compute` lines are added. Still not beat-locked (ADR-025): an arpeggio starts on the sample its keys arrive on. **Found, kept:** upstream's sequencer steps every `arpSeqTempoMultiplier` of a BEAT while the readout names it as a fraction of a bar — a sixteenth-note step is 0.25 and reads "1/4 note", in the Mac app too; and a tempo change re-quantises synced values by TIME, not name — 120→125 keeps a quarter-note delay a quarter note, 125→90 makes it a "1/4 triplet" (so does loading a preset made at another tempo). **Second open question for the owner at the X2 gate: keep the note value across tempo changes (both products)?** `Tests/Plugin/PluginTransportTests` (new CTest, a play head the test controls): **124.999 ms per step at 120 BPM measured from the rendered output, no step off by 0.5 ms**, 100 ms at 150, 125 ms at blocks of 64/1,024/37, 166.667 ms from the parameter's 90 with no host tempo, reports once and without gestures, out-of-range tempos settle, synced delay/LFO follow, restored session, stop/start cases; revert-checked four ways. `Tests/SynthOneTests/PluginTransportTests.testAPhraseAfterAStopBeginsWithItsFirstNote` holds the AUv3 to the same (revert-checked: 4e-05 against 0.22). 18/18 CTest; CI `plugin` run 35366014956 and `engine` run 35366014961 green on three OSes, first run. Mac side, because engine code changed: **339 Xcode tests green (one new), goldens 20 of 20 bit-exact, signed build installed 2026-09-18, `auval` passed**. **HANDOFF — X2-7:** denormal protection. `juce::ScopedNoDenormals` at the top of `processBlock` (and around `prepareToPlay`'s kernel work if anything renders there — nothing does); the engine has only run on Apple silicon and Intel Macs under Clang, and the reverb (`sp_revsc`), the delay feedback and the filters' tails are where x86 denormals would appear. Acceptance per the plan page: every render call wrapped; a 30-second silent tail after a reverb-heavy preset costs no more CPU than the sounding part, **measured on x86** — this Mac is arm64 with no Rosetta, so the measurement has to run in CI (the Linux and Windows runners are x86-64): a CTest that times blocks (sounding vs. tail, generous ratio, e.g. tail ≤ 1.5× sounding, medians not means) and, more robustly, one that counts subnormal samples/states — check what flush-to-zero does under MSVC (`_MM_SET_FLUSH_ZERO_MODE`/`_controlfp`) and that JUCE's guard covers SSE on all three compilers; check whether the engine needs a tiny DC offset anywhere instead (upstream has none). The Mac products are not touched unless the engine changes (arm64 flushes by default under the AU host? — verify, do not assume). Also still carried: **RTSan** (Clang 20) on `processBlock`. **X2-5:** plugin state = `S1PluginState`'s JSON text (`Sources/S1Plugin/S1PluginState.hpp/.cpp`, no JUCE): `parameters` (all 150 by permanent ID — the authority; unknown IDs ignored, missing ones kept, clamped, stepped ones snapped; **`pitchbend` never written, always restored centred**), `preset` (the engine's preset JSON with the values captured in — a preset the Mac app reads, proved by the Swift test `PluginStateFixtureTests` with both of the app's readers — carrying name/bank/uid/text/`tuningName`/`tuningMasterSet`/`modWheelRouting`), `tuning` (128 frequencies + NPO, as the AUv3's `fullState`), `midi` (the router's settings). **Threads:** `getStateInformation` reads host parameters and the processor's own copies, never the kernel; `setStateInformation` writes those exactly and `deliverPendingToKernel` (top of `processBlock` and `prepareToPlay`) writes the tuning table and the owed `resetSequencer`. **Found: a preset's fields are not its parameter values — upstream's apply ORDER decides some** (`delayTime` is quantised under the previous sync setting before the preset's own switch arrives: 0.599 s plays as 0.667 s), so a state without a full `parameters` map gets its sound by applying `preset` to a scratch kernel and reading 150 values back; **X2-9 must load presets the same way.** Also found: `frequencyA4` is inert in the engine, upstream included (saved, shown, read by nothing — X3-5 owns rebuilding the table). `s1::Preset::capture` gained a getter-function form. `Tests/Plugin/PluginStateTests` (25 checks: two-instance round trip to the bit, same text byte for byte before any audio, kernel has it after a block, load between blocks, five kinds of non-state, a "version 7" state, 18 factory presets as states = the engine's own apply, **the committed `Tests/Plugin/Fixtures/state-v1.json` — never to be rewritten** — read and re-written identically on macOS, Linux and Windows). 17/17 CTest; 338 Xcode tests, goldens 20/20 exact, signed build installed 2026-09-18, `auval` passed. **HANDOFF — X2-6:** host tempo and transport. The kernel has `handleTempoSetting(float)` and `handleTransportState(bool)` (the AUv3 calls them from its render block with `musicalContextBlock`/`transportStateBlock`, P4-5/P4-6 — read `S1AudioUnit.mm` around `_musicalContext` and the kernel's `+MIDI`/`+process` for what they do: tempo writes `arpRate` and re-drives the dependents; transport stop/start resets the sequencer). In JUCE: `getPlayHead()->getPosition()` inside `processBlock` (bpm, isPlaying); call the two handlers before the block's events, only on change; `arpRate` becomes engine-driven (add it to the read-back list) and **the host's tempo must not be fought by the `arpRate` host parameter** — decide who wins when the host has a tempo (the AUv3: the host; the parameter is reported, not obeyed — check ADR-022/P4-6 for the exact rule) and that a state's saved `arpRate` does not override a live host tempo on reload. With no play head or no bpm (standalone) the internal tempo applies. Acceptance per the plan page: at 120 BPM a 1/16 arp step is 125 ms measured from the output; stopping the transport stops the sequencer within one block, starting restarts from step 0; no transport info → internal tempo. **X2-4:** host MIDI in the JUCE plugin goes through the engine's router `S1HostMIDI`, as in the Catalyst AUv3 (ADR-031): `hostMIDI.enabled`, `beginRenderCycle` at the top of every `processBlock`, the processor is the kernel's `S1KernelListener`; its own velocity-0 conversion is gone (the router's rule). **The mod wheel runs on the render thread** (`Sources/S1Plugin/S1ModWheel.hpp`, the Mac wheel's arithmetic: cc/127 → cutoff `3 × scaleRangeLog2(1 − v, 120…7600)` or an LFO rate by `modWheelRouting`, which the processor holds for X2-5 to save); `pitchbend` and `cutoff` are read back after each render and reported to the host like the tempo-dependent rates. **Parity carried to Linux and Windows:** `HostMIDIParityTests`' scenarios are data now and a new test writes what the STANDALONE played, event by event, to `Tests/Engine/Fixtures/host-midi.txt` (check mode in the suite; `Scripts/write-host-midi-fixtures.sh`); `Tests/Engine/HostMIDITests.cpp` replays it through the router: **15 scenarios, 1,237 events, the same notes for every one**, 128/128 white keys; revert-checked both ways. `Tests/Plugin/PluginMIDITests` (21 checks): one key once, velocity 0, omni, the pedal (still sounding a second after the key is released), mono by host parameter, pitch bend heard (11.9997 of 12 semitones) and reported with no gesture, the mod wheel (360 Hz at the top), CC 123. Found: **Init's bend range is 0** (upstream's Init; 230 of 695 factory presets) — the wheel does nothing on Init, kept; the mono return re-presses with the note-off's velocity (often 0), the standalone's behaviour, kept. `PluginRender` still exact. 16/16 CTest, 337 Xcode tests (one new), goldens 20/20; no Mac product source changed, nothing reinstalled. **HANDOFF — X2-5:** plugin state. `getStateInformation`/`setStateInformation` are empty. The state is the preset as the engine's own JSON (`s1::Preset::capture` + `toJSON`, ADR-069) — so a session's state is a preset the Mac app can read — plus what is not a parameter: the tuning (`getTuningTableFrequency` ×128 + NPO, names if any), `modWheelRouting`, the router's settings, a format version; **not** `pitchbend` (a wheel position: restore it to centre, or a reloaded session plays bent until the wheel moves). Threads: `getStateInformation` is called on the message thread while audio runs — build the JSON from the HOST parameters' plain values (atomics), never from the kernel; `setStateInformation` sets host parameters (`setValueNotifyingHost`? no — quietly, then `updateHostDisplay`; see ADR-073 on what each path means to a VST3 host) and lets `processBlock`/`prepareToPlay` carry them in; the tuning table needs a render-thread-safe handover (a pending-table slot swapped in at the top of `processBlock`). Acceptance per the plan page: save, reopen, 150 parameters + tuning + pattern equal (round trip in a test, and across two processor instances); state saved on macOS loads on Windows (a committed state blob as a fixture, read on all three OSes). **X2-3:** measured first — `GoldenHarness --block-size N` plays the goldens' performance in N-frame blocks with the notes on the goldens' samples. **Upstream's path against the goldens: 20/20 exact at 512, but only 16/20 within tolerance at 64 (relative RMS up to 0.73), 17/20 at 1,024, 14/20 at 2,048** — not tail ends (ADR-072's reading, from Init alone) but whole arpeggios: `process()` frees released voices once per call and `turnOnKey` gives a still-sounding key its old voice back, so a retriggered note's voice depends on the host's buffer boundary (Missing Time, SubSonic Pad, Let's Play, Forth of Bass). **Decision (ADR-074): `S1DSPKernel::freeReleasedVoicesEveryFrame`, default off (the Mac products and the goldens, untouched), ON in the JUCE plugin** — the same check every frame, which is exactly upstream's path in 1-frame buffers. Proved by the new CTest `GoldensBlockIndependence` (`--check-block-independence`): all twenty presets render the same samples at 512/64/480/1,024/37 and equal upstream's path in 1-frame blocks; upstream's path moves with the block size for 11 of 20. Against the goldens the plugin is then 8/20 exact, 16/20 within tolerance, the four arpeggios outside — by decision. **Ramps = the engine's smoothing** (`startRamp` still ignores its duration): a 500→5,000 Hz cutoff change moves the filter ≤ 0.7073 Hz per sample, the `sp_port` bound; the unsmoothed continuous parameters (LFO rates, tempo, step length, compressors, delay input) step at the block's first sample; JUCE gives one value per parameter per block. **48/96 kHz:** no goldens there; `processBlock` = bare engine exactly at both rates, Init's A3 = 219.67 Hz at all three, level within 0.16 dB. A note-on at sample 300 of 512 first sounds at sample 300. `PluginRenderTests`' engine is now identical across six block sizes. **Open for the owner at the X2 gate, not blocking: should the Mac app and AUv3 take the option too?** A bounce would then equal playback at every buffer size; 12 of the 20 goldens would be rewritten. Mac side, because `S1DSPKernel+process.cpp` changed (the check moved into a function): **336 Xcode tests green, `GoldenRenderTests` 20 of 20 bit-exact, signed build installed 2026-09-18, `auval` passed.** **HANDOFF — X2-4:** MIDI through `S1HostMIDI`. The processor feeds raw MIDI to `handleMIDIEvent` with `hostMIDI.enabled` false, i.e. upstream's note-on/off + CC123 only (and the processor's own velocity-0 conversion). Turn the router on (`kernel->hostMIDI.enabled`), read `S1HostMIDI.hpp/.cpp` and ADR-031 for what it needs from its host (settings: channel, velocity sensitivity, octave, bend range; sustain/hold; what it reports back through `S1KernelListener`), port `HostMIDIParityTests`' cases to CMake (`Tests/Plugin` or `Tests/Engine`), check pitch bend and mod wheel reach the sound, drop the processor's velocity-0 conversion if the router covers it, and decide what `pitchbend` as a *host parameter* means once MIDI drives it (it becomes engine-driven: add it to `engineMayChange` or make it non-automatable). Acceptance per the plan page: parity tests green on three OSes; one key plays once. **X2-2:** the 150 parameters in the JUCE plugin. **IDs are generated by CMake from `S1Parameter.h`** (the enum case's name, version hint 1) — *not* the kernel's `presetKey`, which the AUv3 uses and which differs for 19 (spaces in the compressor keys, `compressorMasterMakeupGain` twice); `Tests/Plugin/Fixtures/parameter-ids.txt` freezes index/ID/hint (lines may be added, never changed; revert-checked). `S1ParameterCatalog` (JUCE-free; X3 will read it too): ranges/defaults read from a kernel, names/readouts/tapers from the desktop layout and the classic knobs, step names from the kernel's code, note-value readouts for the rates under tempo sync; `frequencyA4` is stepped because the kernel truncates it. `S1HostParameter` holds the plain value. **The kernel is touched only from `processBlock`/`prepareToPlay`:** changed values go in as `S1Event`s at the block start, sync switch and tempo first; the five parameters the engine rewrites (the four tempo-dependent rates, ADR-022, and the sequencer's step length) are read back after the render and reported to the host **from the audio thread** — in JUCE's VST3 wrapper an output parameter change, not the `performEdit` the message thread would send; no gesture. The parameters start as Init; `prepareToPlay` no longer re-applies it; tail length computed. **`PORT FIX` in `S1DSPKernel::prepareToRender`: it saved `parameters` across `init` — for the 45 smoothed parameters that is the glide's position, so a value set just before allocation (a host restoring a session) was lost: cutoff written 777 came back 20,000. It saves `getSynthParameter` now; equal whenever nothing glides.** The AUv3 has had this since upstream. Found by `PluginParameterTests` reading the kernel — the render test could not see it (plugin and reference lost the values identically). `PluginParameterTests`: 51 checks (identity, ranges, all 149+1 values reaching the kernel, dependents reported once with no gesture, nothing stale after eight idle blocks, sync-off-and-rate in one block, readouts, typed text, tapers, tail). `PluginRenderTests` still 12 of 12 exact (its reference applies Init before `prepareToRender` now, as the plugin does). CI: `plugin` run 35354695631 and `engine` run 35354695677 green on three OSes; the run before failed on Windows in X1-2's `HeldNotes` thread test (the writer finished before the reader was scheduled) — it now writes until the reader has read a thousand snapshots. Mac side, because engine code changed: **336 Xcode tests green, `GoldenRenderTests` 20 of 20 bit-exact, signed build installed 2026-09-18, `auval` passed.** **HANDOFF — X2-3:** sample-accurate events and ramps. JUCE hands `processBlock` one value per parameter per block, so the work is (1) `startRamp` in the kernel ignores its duration today (`(void)duration`) — decide whether ramps are the kernel's smoothing (45 parameters already glide with `portamentoHalfTime`) or a real linear ramp for the rest; (2) spreading a block's parameter change over the block (`rampFrames = frameCount`) versus a step at sample 0 — measure zipper noise on a cutoff sweep first; (3) the plan's acceptance: a note at offset 300 of 512 starts at sample 300 (already proved at +129 by `PluginRenderTests`), a cutoff sweep over one block has no step larger than the ramp allows, goldens at 48/96 kHz and blocks of 64/480/1,024 — which meets ADR-072's block-cut finding head on, so X2-3 is where that decision probably has to be taken. Read `Sources/S1Plugin/README.md` first. **X2-1:** `Sources/S1Plugin/` — JUCE **9.0.2 fetched by `FetchContent`, pinned by commit**, behind `-DS1_BUILD_PLUGIN=ON` (default OFF; the `engine` workflow is unchanged, a new `plugin` workflow builds and tests on three OSes and keeps the VST3 + Standalone as 7-day artefacts). Licence re-read at the tag: unchanged from ADR-054, no splash clause; EULA §1.17 forbids distributing JUCE on its own, so it is never vendored; the bundled VST 3 SDK 3.8.0 is MIT; `NOTICE.md` has the entry. `juce_add_plugin`: VST3 + Standalone, no AU, `BP03`/`Ruin`, company "BadPackets", **VST3 class ID `ABCDEF019182FAEB425030335275696E`**; JUCE has ONE bundle ID per plugin, so the `.vst3` carries `com.badpackets303.ArcadeRuinsStandalone` too (amends ADR-058). `S1PluginProcessor` hosts the engine in `makeEngine`'s order (Init applied in `prepareToPlay`; MIDI → `S1Event`s in a fixed array of 512, a fuller block rendered in pieces; note-on velocity 0 → note-off; generic editor; stereo only). Wavetables = the 54 JSON files as JUCE binary data, decoded once per process (31 ms here; 5.5 MB per binary — the float blob is not worth a generator yet). **`Tests/Plugin/PluginRenderTests`: `processBlock` equals a bare kernel cut the same way, sample for sample — 12 of 12 renders (blocks of 512, 64, 1024, 441, 37, 1; notes at +0 and +129) on macOS, Linux and Windows** (`plugin` run 35350332737; the first run failed on Linux for want of `libxi-dev`, new with JUCE 9); tables from the binary equal the repository's 52 of 52. **Found: the engine's render depends on where `process()` calls are cut** — a released voice is freed at the top of a call (envelope under 0.01), so a release tail ends up to a block earlier or later: Init vs the 512-block render, ≤ 1,024 samples differ by ≤ 0.0019 (≤ 206 over 0.001). Upstream's, in the goldens, in every AU host's render; not changed. **The X2 gate (goldens at odd block sizes) must decide: a criterion that covers tail ends on all twenty, or free the voice on its sample and rewrite goldens.** The standalone launches on this Mac; nothing was installed and the Mac products are untouched (no reinstall, no `auval` needed). **HANDOFF — X2-2:** 150 `juce::AudioProcessorParameter`s generated from `S1Parameter.h` (ID = case name, version hint 1, ADR-058), ranges/defaults/units from the kernel's `s1p` table (`minimum`/`maximum`/`defaultValue`), the tapers from `S1DSPKernel+tapers.cpp`; discrete/boolean ones marked so; a test that the count is 150, every ID equals its enum name, and the list order is frozen; parameter changes reach the kernel as `S1EventKind_Parameter` events (X2-3 makes them sample-accurate and ramped) — no `setSynthParameter` from the message thread while rendering; then Init stops being re-applied in `prepareToPlay` (the parameters ARE the state), and `getTailLengthSeconds` can be computed. Read `Sources/S1Plugin/README.md` first. **The X1 gate:** with the X1-7 signed build installed (app and AUv3 on `Sources/S1Engine`, `auval` passed) the owner was asked to try the app and the plugin in Logic, and answered **"We're good so far."** (2026-09-18) — taken as the gate passed; they then asked for the records to be brought up to date and will continue in a new session. X1-8 needed no code: the Mac products have compiled the engine since X1-3 and prepare the kernel through `prepareToRender` since X1-7. **HANDOFF — start X2-1 here:** (1) read `Sources/S1Engine/PORTING.md` ("The golden harness" gives the engine's hosting order; `GoldenHarness.cpp`'s `makeEngine`/`render` are the reference host) and ADR-054/055/057/058/071; (2) branch `x2-juce-project`; (3) `Sources/S1Plugin/` with its own `CMakeLists.txt`, JUCE **9.0.2 by `FetchContent`, pinned by tag** (not a submodule), behind an option (e.g. `S1_BUILD_PLUGIN`, default OFF so the engine CI stays fast) — **re-read the JUCE 9 EULA/Starter terms at that tag and confirm the no-splash reading before anything ships** (ADR-054); (4) formats **VST3 + Standalone only, no AU** (ADR-055/058), manufacturer `BP03`, plugin code `Ruin`, standalone bundle ID `com.badpackets303.ArcadeRuinsStandalone`, version from the root `project()`; (5) a first processor that hosts the engine exactly as `makeEngine` does (construct → `s1::Wavetables::apply` → `prepareToRender` in `prepareToPlay` → `setOutput` + `processWithEvents` in `processBlock`), host's generic editor, no parameters yet (X2-2); the wavetable JSON has to reach the plugin — `s1::Wavetables::load(Source)` takes any name→text callback, so JUCE BinaryData works; 5.5 MB of JSON vs an 852 KB generated blob is X2-1's packaging call (ADR-070); (6) a second workflow (or job) that builds the plugin on the three OSes — Linux needs JUCE's apt dependencies; (7) acceptance per the plan page: builds on three OSes, loads in a host/standalone and makes sound with the Init patch. Carry into X2: **RTSan** (Clang 20, `[[clang::nonblocking]]` on the render entry, our own `S1KernelListener` behind it), goldens at 44.1/48/96 kHz and odd block sizes (the X2 gate), the transport struct (X2-6), flush-to-zero (X2-7). Local traps: CMake needs `SDKROOT` (CLAUDE.md); no Rosetta on this Mac; `build/`, `build-nofma/` are local and ignored. **X1-7** (ADR-071)**:** `Tests/Engine/GoldenHarness.cpp` renders the twenty goldens through `Sources/S1Engine` alone (kernel + `s1::Wavetables` + `s1::Preset` from the bank JSON; `GoldenRenderTests`' recipe; `WavFile.hpp` reads `Tests/Goldens`). **macOS arm64: 20 of 20 bit-exact** (`--require-exact`, enforced by CMake on Apple Silicon). **Linux and Windows: 20 of 20 within tolerance**, worst relative RMS 6.9e-4 (−63 dB) — criterion there is relative RMS ≤ 3.16e-3 and ≤ 1 sample in 200 over 0.001, because the plan's 1e-4/1e-5 was wrong: without FMA the bit-crusher's sample-and-hold lands a sample over now and then (one sample off by ~0.02; found by reproducing with `-DS1_FP_CONTRACT=off` and reading samples). **`-ffp-contract=on` now, explicitly** (amends ADR-065): it is Xcode's default, so the product's sound; `off` gave 3 of 20. `S1DSPKernel::prepareToRender` = the AU's allocate sequence moved into the engine, the AU calls it. `GoldensReject-*` self-checks prove the tolerance rejects a filter 1% sharp (19/20), 1 cent of detune (20/20), a late note (7/20). New `sanitizers` CI job (ASan/LSan/UBSan, Clang/Linux): clean. CI run 35347661117, four jobs green. 336 Xcode tests, goldens 20/20, signed build installed 2026-09-18, `auval` passed. RTSan deferred to X2 (needs Clang 20; the boundary that matters is JUCE's `processBlock`). **X1-8 / the X1 gate:** the Mac app and AUv3 already run on the engine (since X1-3; `prepareToRender` since today) — what remains is the owner trying the installed app and the plugin in Logic; then X2-1 (JUCE by FetchContent, re-read the licence terms, `Sources/S1Plugin`). **X1-6:** `Sources/S1Engine/Wavetables/S1Wavetables` — `load(Source)` (a name → JSON text callback; `loadFromDirectory` today, linked-in data at X2) and `apply(kernel)`, the Swift loader's three calls in its order; stricter than the Swift (a short index, table or frequency list is refused by name). The JSON stays in `Sources/SynthOneCore/DSP/BandlimitedWavetables`. `WavetableFixtureTests` writes `Tests/Engine/Fixtures/wavetables.txt` (`Scripts/write-wavetable-fixtures.sh`; check mode fails when stale); `WavetableTests`: **52 of 52 tables (212,992 floats) and 13 of 13 band frequencies bit-exact** on macOS/Linux/Windows (run 35344520512), ten kernels made and destroyed all hold exact tables and render the same samples. **Found with `leaks`: the kernel never freed anything** — 79.6 MB over eleven kernels (`= default` destructor, `init()` dropping the note states' modules, the tables never freed). `PORT FIX`: the destructor calls `destroy()`, frees the note states, then the tables; `init()` frees the note states it replaces; 0 leaks. Nothing on the render path changed: 336 Xcode tests green, 20/20 goldens exact, signed build installed 2026-09-18, `auval` passed. **X1-7 next:** the C++ golden harness — the engine alone (kernel + `s1::Preset` from the bank files + `s1::Wavetables` + tunings) renders the 20 goldens by `GoldenRenderTests`' recipe (44.1 kHz, 512-frame blocks, A3 at 0.75 s, E4 +0.4 s, release at 1.0 s, 1.5 s captured) and compares with `Tests/Goldens/*.wav`; tolerance 1e-4 max / 1e-5 relative RMS, exact expected on macOS; needs a small WAV reader; the place for the deferred RTSan pass and a Linux ASan/LSan job. **X1-5:** `Sources/S1Engine/Presets/S1Preset` — the 114 fields, `fromJSON` with the Swift's `as? … ?? default` bridging, `toJSON` (JSONEncoder's key set), `apply` in upstream's order, `capture`; transcribed by a script from `Preset.swift` / `Preset+Synth.swift` / `saveValuesToPreset`. nlohmann/json 3.11.3 vendored (MIT, NOTICE.md). `PresetFixtureTests` writes `Tests/Engine/Fixtures/factory-presets.txt` (`Scripts/write-preset-fixtures.sh`; check mode fails when stale); `PresetTests`: **695 of 695 presets decode and apply bit-exact** on macOS/Linux/Windows. **Found by the Linux job:** `abs(float)` in `S1Rate.hpp` was `abs(int)` under libstdc++ — 2,513 wrong tempo-synced values; `std::fabs` now (PORT FIX; the Mac always computed fabs, goldens 20/20 after). **X1-6 next:** the wavetable loader — `S1Wavetables.swift` (100 lines) reads `bandlimitedWaveforms.json` + `bandlimitedWaveformFrequencies.json` from `DSP/BandlimitedWavetables/` and calls setupWaveform/setWaveformValue/setBandlimitFrequency; port with nlohmann, fixture = a checksum/first-values dump from Swift, acceptance: table floats equal exactly, tables survive ten engine create/destroy cycles. Then X1-7 the C++ golden harness (the 20 goldens through the engine alone). **X1-4:** **X1-4:** `Sources/S1Engine/Tunings/` — `S1TuningTable` (AKTuningTable's table, line for line), `S1Scala` (the `.scl` parser the product uses, quirks kept), `S1FactoryTunings.cpp` **generated from the Swift** by `TuningFixtureTests` (write mode = `Scripts/write-tuning-fixtures.sh`; check mode in the normal suite fails when stale — revert-checked). `TuningTableTests` reads the Swift-written fixture: **194 of 194 tables bit-exact**, six Scala cases equal, on macOS/Linux/Windows (run 35293220508; CI runs `ctest --verbose` now so the counts are in the log). Trap: LLVM rewrites `pow(2, x)` to `exp2(x)`, one bit off libm's `pow` — `s1::powerOfTwo` blocks it. **X1-5 next:** the preset model in C++ — `Preset.swift` (411 lines: keys, defaults, the upgrade paths incl. `Tunings+UpgradePaths`), the 8 factory bank JSONs; needs a JSON parser (nlohmann/json single header, MIT, is the plan — NOTICE.md entry); acceptance: every preset's 150 values equal to the Swift loader's (dump a fixture the same way), a preset saved by the new code reloads in the Mac app. **X1-3:** **X1-3:** the kernel (`Kernel/`, `Note State/`, `Sequencer/`, `Rate/`, `S1Parameter.h`) lives in `Sources/S1Engine` as `.cpp`, compiled by the Xcode framework (project.yml lists the directory) and by CMake; `S1EngineTypes.h` (own address/value/frame-count/MIDI-event/unit types, `S1Event`, the message structs out of `S1AudioUnit.h`); `S1KernelBase.hpp` instead of AudioKit's bases; `S1KernelAUAdapter` in `S1AudioUnit.mm` keeps the AU path byte-identical; `processWithEvents(frames, S1Event[])` for JUCE. **The `engine` workflow is green on all three OSes** after two rounds of compiler-found fixes (`nil`, `BOOL`, transitive standard headers, an include guard, `M_PI` on MSVC — tabled in `Sources/S1Engine/PORTING.md`). `Tests/Engine`: 4 tests, 25 checks, including a note played from a MIDI event at sample 128 of 256 on Windows and Linux. 94 Xcode tests green, 20/20 goldens bit-exact, installed 2026-09-17 evening, `auval` passed. **X1-4 next:** tunings in C++ — `AKTuningTable` and its builders (`S1Support/Microtonality`, ≈1,100 lines) plus `Tunings+TuneUp`; acceptance: every built-in tuning's 128 frequencies within 1e-9 relative of the Swift code (dump a fixture from the current build first), `.scl` import equal. **X1-2:** **X1-2:** the kernel's held keys are `S1HeldNotes` (128 `NoteNumber`, most recent first, seqlock-published snapshots; no allocation) and its seven messages go through `S1KernelListener`, which `S1AudioUnitKernelListener` in `S1AudioUnit.mm` implements with the same queue-to-relay calls; `__weak S1AudioUnit *audioUnit` is gone from the kernel. 74 tests green, **`GoldenRenderTests` prints 20 of 20 goldens bit-exact**, installed 2026-09-17 evening, `auval` passed. **X1-3 next:** own typedefs for parameter address/value/frame count, the message structs and `S1_NUM_MIDI_NOTES` out of `S1AudioUnit.h` into a plain header, `AudioToolbox` out of `S1HostMIDI.hpp`, a sample-positioned event struct, then `git mv` the kernel into `Sources/S1Engine` and compile it there (`.mm` → `.cpp`); `S1HeldNotes` gets its own CMake test. **X1-1:** The plan is rebased on 0.5.0: the engine is untouched since the survey, X3 draws from the Cabinet skin, X2's release takes the next free version. X1-1: root `CMakeLists.txt`, `Sources/S1Engine/` (`soundpipe` compiled in place + `s1engine`, C++17, no fast-math), `Tests/Engine/` (measured behaviour; `sp_rand`/`sp_noise` bit-exact from seed 0; a guard against Apple headers, revert-checked), `.github/workflows/engine.yml`. **The `engine` workflow is green on Clang/macOS, GCC/Linux and MSVC/Windows** (run 35284384744). Its first run failed on Windows, as it should have: `revsc.c` did arithmetic on `void *`, a GNU extension — now `char *`, a `PORT FIX` recorded in `Sources/Soundpipe/VENDORING.md`; `GoldenRenderTests` 4/4 in the Xcode build after it, so the reverb is unchanged. CMake needs `SDKROOT` pointed at Xcode's SDK here (CLAUDE.md). **X1-2 next:** replace `AEArray`/`NSMutableArray` held notes and `AEMessageQueue` in the kernel with C++ (fixed-capacity array, SPSC ring), `HostMIDIParityTests` green, goldens exact. Work on a branch and merge, as the skin work does. XcodeGen, `Scripts/build.sh` and the installed products are untouched by X1-1.

**Last change — ADR-064 (2026-09-17, unreleased): Cabinet is the default skin** (`S1SkinChoice.default`; an explicit Studio stays; the test suite sets Studio in its scratch suite). **And the owner's rule: the Cabinet extras are not revealed on GitHub** — README, release notes, the 0.5.0 release page and the screenshot cleaned; ADR-061/062 and their STATE/plan entries moved to `docs/private/`, which the public export leaves out. The source stays as it is. The owner confirmed the ADR-063 mod-wheel fix in Logic.

**Before that — ADR-063 (2026-09-17, after 0.5.0, unreleased, not installed): the standing mod-wheel test failure was a real read-after-write race in the plugin** — `S1HostedSynth.getSynthParameter` now answers with a write still on its way to the kernel; the test renders while it waits. **Full suite 333/333, the first all-green since before Phase 6.** Which commit turned the test red was not established.

**Before that — 0.5.0 RELEASED (2026-09-17):** P7-10, P7-11 and P7-12 — Cabinet replaces Neon Ruins, and two Cabinet extras that are not published (`docs/private/cabinet-extras.md`). Notarised and stapled (submission `0fbb9fab-2f19-4f20-85f9-abb933db6419`), `ArcadeRuins-0.5.0-macOS.zip` SHA-256 `6e91ffded945efc51e05c467476dec6df205bbe14009594b8037186a766f3c60`, <https://github.com/badpackets303/ArcadeRuins/releases/tag/v0.5.0>. Full suite 333 run, 1 failure: the standing `testAHostModWheelMovesTheWheel` (fails on untouched code too; the owner's physical wheel works).

**Before that — P7-10 (2026-09-17, after 0.4.0, unreleased): Cabinet replaces Neon Ruins (ADR-060).** Skins are Studio | Cabinet; `S1NeonRuinsSkin` → `S1CabinetSkin`, the Neon-only art and the `s1_wordmark_neon` asset deleted, a stored `neonRuins` opens Cabinet. README, screenshots (`cabinet-skin`, `cabinet-presets`, `settings-pickers`) and notes updated. `SkinTests`, `DesktopLayoutTests`, `DesktopPluginTests`, `UILoadTests`, `AudioUnitPackagingTests` 57/57. **The mod-wheel test (`HostMIDIInterfaceTests.testAHostModWheelMovesTheWheel`) still fails on `main`; the owner reports a physical wheel works in Logic under Cabinet, so suspect the test or the OS (Darwin 27), not the product — still worth a session.**

**Before that — 0.4.0 RELEASED (2026-09-17): <https://github.com/badpackets303/ArcadeRuins/releases/tag/v0.4.0>, public `main` at b25351a, downloaded anonymously and verified (SHA matches, `spctl` accepted); the notarised build is what is in /Applications. notarised and stapled (submission `043fb22e-ab8f-44b9-a13a-9dc104ab8c88`, Accepted in about a minute), `ArcadeRuins-0.4.0-macOS.zip` SHA-256 `43e9d2903ed4d4082be335e12d7eea55691b1a0f02b09a2929b1b853796d2f4b`. Before it: P7-9, the Cabinet skin, merged to `main`, version 0.4.0 (build 4), release notes written; `Scripts/release.sh` started — see `DerivedDataRelease/release/submission-id`, resume with `RESUME_ID=<id>`. Installed and `auval` passed on the Debug build; the owner tried it in Logic ("looks great") and asked for the LFO knobs to hold still, done (fixed-width cells).** P7-9 (ADR-059). A third skin: the owner's painted window (`Scripts/branding/source/ar-template.png`) under Neon Ruins' controls. `S1SkinTemplate` gives each section and toolbar control a rectangle in the painting; `S1DesktopLayout+Template.swift` pins them there after the normal build. `generate.py` cleans the mock's painted controls off and writes `s1_template_cabinet`. Settings ▸ Skin and View ▸ Skin list it (both read `allCases`). Rendered at 1440×900 with the preset card and Settings open; `SkinTests` all green with two new tests. **Full suite 327 run, 1 failure that is not this branch's: `HostMIDIInterfaceTests.testAHostModWheelMovesTheWheel` fails identically on untouched `main`** (wheel reads 0.03 for 1.0) — new since the last full run, worth its own session. Not installed, `auval` not re-run. **Untested by hand:** clicks on the painted buttons in a real window, and the plugin in Logic.

**Before that — 0.3.0 IS RELEASED (2026-09-14).** <https://github.com/badpackets303/ArcadeRuins/releases/tag/v0.3.0>, `ArcadeRuins-0.3.0-macOS.zip` (9.9 MB), SHA-256 `6368c2b595ccae6cbfac51a9c160768a36f18b6d5b9e191b37a52d76da780348`. **Notarised and stapled**; `spctl` says `accepted / source=Notarized Developer ID`. Submission `c8a969f8-7b1d-47dc-941b-e2b6ed147782`, Accepted after about two hours. One release covering Phases 6–8 at the owner's word ("Ship it as one release and merge it"); `main` carries the work, tagged `v0.3.0` in both repositories, and the public mirror is pushed at `0e7e653`. Full suite before it: 325 tests, 0 failures. **Still to do: the owner's Logic screenshot** — `docs/screenshots/logic-plugin.png` is 0.1.0's — and trying the plugin's Settings popover inside a host.
**Before that (P7-8, 2026-09-14):** **classic is the default layout, and the app has an icon** (ADR-052). A fresh install opens the classic interface — `S1ClassicLayout` absent now means classic, so `S1Layout.current` asks `object(forKey:)`, the only way to tell unanswered from an explicit `NO`; anyone who has chosen keeps their choice, and Settings ▸ Layout changes it. The icon is the owner's artwork (`Scripts/branding/source/Arcade-Ruins-Icon.png`) as **`Sources/SynthOne/ArcadeRuins.icon`**, an Icon Composer bundle, with `ASSETCATALOG_COMPILER_APPICON_NAME: ArcadeRuins`. **The app had no icon of any kind before this.** A mac-idiom `.appiconset` was built first and looked fine in the catalog — but asking macOS what it draws (`NSWorkspace.icon(forFile:)` on the installed app) showed the owner's rounded square nested inside the system's, on a white plate: macOS 26 shapes every icon, so the artwork has to be what is shaped. The `.icon` bundle's one layer is the body cropped full-bleed; `actool` emits a legacy `.icns` beside it for older systems. **Second pass the same day, from the owner's eye:** "the icon appears to fade to white in the lower half" — macOS 26 lights an icon's layers like glass, and on dark artwork that reads as a wash. Measured on the installed app, the keyboard's dark bezel climbed 27 → 106 down the image; `specular: false` and `translucency: {enabled: false}` on the group flattened it to a steady 17–28. 55 tests green, including packaging tests on both plist keys and on those two settings. Installed, `auval` passed.
**Before that (P7-7, 2026-09-14):** **the Arcade skin is gone** (ADR-051), at the owner's word — "Remove the 'Arcade' skin as an option." Neon Ruins is the same genre done properly and nothing had shipped with Arcade, so the skin, its header and browser art, its drawn wordmark and its grunge tile are deleted rather than hidden; `S1SkinChoice` is `studio | neonRuins` and both menus build from `allCases`. **`S1ArcadeArt` is now `S1SynthwaveArt`** — the seeded generator, sun, mountains, grid, starfield, joystick, scanlines and `S1CRTFrame` were always shared, and Neon Ruins draws with all of it. A stored `S1Skin = arcade` opens Studio (unknown values always did; a test holds it). `git show bf8a08a` has the skin if it is ever wanted. 45 tests green. Installed, `auval` passed.
**Before that (P7-6, 2026-09-14):** **the layout is chosen in Settings too** (ADR-050), at the owner's request — "I would still like to access the original iPad-based interface by changing the setting. Can we include that in the release?" `S1AppearanceSettings` carries Layout (Desktop | Classic) above Skin, and **installs from `MIDISettingsViewController` rather than the desktop layout**, so the classic layout carries it as well: without that, Classic was a one-way trip in a host, which has no menu bar. Under Classic the skin picker dims and its title reads `SKIN · DESKTOP ONLY` (the caveat rides in the title so the note stays one line — a second line runs into the scene's buffer paragraph). **Also fixed: the test bundle was writing the owner's real settings.** P7-5's tests chose a layout and a skin through `UserDefaults.standard`, which in the test host is `com.badpackets303.ArcadeRuins`; both defaults now go through `S1Preferences.store`, pointed at a scratch suite by `TestStorageIsolation` (ADR-036's hazard, preferences edition). 58 tests green, the owner's defaults byte-identical before and after. Rendered the popover in both layouts. Installed, `auval` passed.
**Before that (P7-5, 2026-09-14):** **the skin is chosen in Settings** (ADR-049), at the owner's request — "going through Terminal is not a feasible option". `S1SkinPicker` (Studio | Arcade | Neon Ruins + a note) sits in the Settings popover's empty right column, added by the desktop layout in `dressPresented` for `SegueToMIDI`, so no ported file changed and the classic layout never sees it. **This is the only way to re-skin the plugin**, which has no menu bar; its note reads "the next time the host loads Arcade Ruins". View ▸ Skin stays. Still next-launch, for the reason in ADR-046. `SkinTests` 11, `DesktopPluginTests` 5, desktop suites 38/38. Rendered the popover under Neon Ruins. Installed, `auval` passed.
**Before that (P7-4, 2026-09-14):** the **Neon Ruins** skin (ADR-048), View ▸ Skin ▸ Neon Ruins / `-S1Skin neonRuins`. Built from the owner's second synthwave reference through four rounds on the design canvas (<https://claude.ai/code/artifact/e6ae9c83-3b9b-4ac2-98d1-7b25f2d048cb>): one neon per section — OSC 1/2 orange, Mix mint, Filter pink, Voice violet; Filter Env pink, Amp Env gold, LFO violet; Reverb cyan, Delay mint, Phaser violet, Bitcrusher pink, Master orange; Sequencer orange, Pads cyan (Mix mint like Delay at the owner's word) — 2-point neon borders with a bloom and an inner rim over near-black worn-metal panels, halo'd knobs with a bright core and a white pointer, lit fader tracks, accent-coloured envelope curves, cyan readouts and outlines, a sunset header with the owner's wordmark lit (new asset `s1_wordmark_neon`, 220×24: the artwork is ~14:1 trimmed), nebulae and a magenta floor under a translucent play bar. Plumbing: `S1Skin.sectionAccent(for:)`, `S1SectionView.accent`, `UIView.s1Accent`, an `accent:` argument on every `S1DesktopStyle` drawing (eleven ported call sites, one argument each), `S1SkinDress`, `makeBackdropArt()`, palette entries `chipText` and `knobPointer`. **Studio's render is byte-identical to 2026-09-13's** (`cmp`), Arcade rendered. `SkinTests` 10 (4 new), desktop suites 36/36. Rendered Neon Ruins closed and open; `docs/screenshots/neon-ruins-skin.png`. Installed, `auval` passed. Not built: the canvas's marquee in the preset browser (a layout change). Not yet seen by the owner in the running app.
**Before that (P8-1, 2026-09-13):** LFO & Mod Targets rebuilt as two columns (LFO lines with 40-point knobs beside their pickers; a 3 × 4 target grid; section ×1.25); effects knobs 48, envelope knobs 46, cutoff 68 with 52s, Mix and Glide 52; OSC 2's knobs each take half the section. Row heights unchanged (158/220/122). Rendered both skins; suites 32/32; reinstalled, `auval` passed.
**Before that (P8-0 follow-up, 2026-09-13):** the owner asked "Where did the preset editor go?" — the selected preset row's rename (→ editor), duplicate and share buttons had been off the right edge since the P6-6 sidebar (storyboard x 324…487 in a 499-point cell, flexible right margin); `PresetCell.layoutSubviews` now lays the four buttons out from the trailing edge in the desktop dress and clamps the name. Test added. Reinstalled.
**Before that (P8-0, 2026-09-13):** the preset browser drops down from the toolbar's preset name (chevron; ⌥⌘P; View ▸ Preset Browser; closes on a click outside, Escape, or a card presentation) and the sidebar is gone — the same re-homed column in `S1DesktopLayout.presetPanel`, a 380×720 card over the rows, a subview of the root rather than a presentation so the browser's own editors and Search present as before and the plugin needs no window (ADR-047). The rows have the whole 1440 and were re-spaced: OSC 1/2 184/204 with wider selectors, Filter 236 (cutoff 60), Voice 156, 44-point knobs, LFO section ×1.12 with 70-point chips and 30-point knobs (its readouts no longer overlap), pads 400; rows one and two 158/220 tall, so row four has 247 at 900 tall. Sidebar notification and narrower minimum removed; Find menu removed (the ⌘F conflict). `RENDER_PRESS` presses by accessibility label too. Desktop suites 32/32. Rendered both skins closed and open. Installed, `auval` passed.
**Before that (Phase 7, 2026-09-13):** skins. `S1Skin`/`S1Palette`/`S1SkinChoice` (`S1Skin` default; View ▸ Skin ▸ Studio | Arcade, next launch; `-S1Skin arcade` launch argument), `S1DesktopTheme` reads the palette with its names kept, `S1DesktopStyle`'s colours are palette entries with Studio exact to 0.2.0 (pixel-diffed: only run state differs). Arcade: neon palette, glow ×2.2, orange section glow over grunge, `S1ArcadeArt` header/sidebar art, neon wordmark, CRT frames on the sidebar lists and XY pads — all Core Graphics, seeded. `SkinTests` 6/6 (both skins lay every section out in the same place), desktop suites 32/32. Rendered both skins at 1440×900 and 1180×900; `docs/screenshots/arcade-skin.png`. Installed, `auval` passed. Also found: XcodeGen rewrites both `Info.plist`s on every generate with `1.0`/`1`, so the version keys now live in `project.yml`'s `info.properties` as `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` (the P6-8 hand edit lasted one generate).
**Before that (P6-8, 2026-09-13):** release prep. Final README screenshots rendered from a factory bank (`RENDER_SELECT`), README rewritten around the desktop layout, `docs/release-notes.md` written (0.2.0 and 0.1.0), both `Info.plist`s read the build settings so the app and plugin report 0.2.0 build 2. Found and fixed: a desktop-drawn control kept its stretched bitmap after a bounds change (a smeared Steps stepper after hiding the sidebar in an 1180-wide window) — every desktop dress now sets `contentMode = .redraw`. `DesktopLayoutTests` + `DesktopPluginTests` 26/26. Reinstalled, `auval` passed.
**Before that (P6-7, 2026-09-12):** About, the preset editor, the bank editor and Search present as centred cards over a dimmed backdrop (`S1DesktopLayout.dressPresented`, from the two `prepare(for:)`s); Settings and Wheels stay popovers. The sidebar's preset rows centre their content (`PresetCell.centresContentVertically`) — the owner saw the highlight off-centre. `desktop_render.py` performs a segue (`RENDER_SEGUE=SynthOneCore.Manager:SegueToAbout`) and renders the presented view. Reinstalled.
**Before that (P6-6):** the preset sidebar. The classic browser's tables, cells, buttons and notes field are re-homed into a 260-point column (search ⌘F · categories and banks · the presets of the selection · category and notes · New/Import/Reorder/Import Bank/New Bank); every callback is the classic one. Presets (toolbar), ⌥⌘S and View ▸ Show/Hide Sidebar collapse it and the window's minimum width drops to 1180. The Presets sheet is gone. Rendered with and without the sidebar, no constraint warnings. `DesktopLayoutTests` 20/20, `DesktopPluginTests` 4/4, `UILoadTests` 8/8. Reinstalled.
**Before that (a crash the owner hit):** `~/Library/Logs/DiagnosticReports/ArcadeRuins-2026-09-12-195648.ips`, from the first installed desktop build, seven minutes after the install: `S1PanelSheet.viewDidLoad` → `addChild` raised, out of `presetsPressed`. The exact gesture was not recovered (the report carries no reason string; a second Presets press while the sheet was up did **not** reproduce it under the driver), so the fix is structural: a sheet adopting a panel first makes any other sheet release it, the hand-back is idempotent (`releasePanel`), and the Presets and Tuning buttons close an open sheet instead of presenting over it. Driven: Presets,Done,Presets,Done,Presets and Presets,Presets,Presets both run clean (`RENDER_PRESS` takes a comma list now). Reinstalled.
**Before that (P6-5):** the plugin shows the desktop layout, sidebar included: 1440×900 asked for and honoured by `Scripts/debug/auhost.swift` (a 1440×932 window); the scope shows in the plugin; the panel sheets are `overCurrentContext` overlays there, since a Catalyst form sheet needs the presenting view's own window (ADR-044); the plugin view is pinned Dark. `AKTouchPadView` no longer sets a NaN layer position when a hosted synth's dependent parameters are read before render resources exist. **Not yet seen in Logic** — the owner must quit and relaunch Logic, which holds the previous plugin, then open AU Instruments ▸ BadPackets ▸ Arcade Ruins. Things to look at there: does the window come up at 1440×900; do Presets and Tunings open as overlays with a Done button; does the sequencer follow the transport. `DesktopPluginTests` 4/4, `DesktopLayoutTests` 17/17, hosted suites green.
**Before that (owner's layout change):** the owner found the Mix section's last knob barely visible with its label cut off, and asked what could leave the top row. **Master moved to the end of the effects row** (Volume, Anti-alias, Widen, Arp/Seq — the output stage), so row one is OSC 1 · OSC 2 · Mix · Filter · Voice and Mix has ~450 points at 1440 (knobs 40 px). The owner also confirmed the **preset sidebar is wanted** ("very useful … to quickly shift between presets"), which settles P6-6's direction. Reinstalled; `DesktopLayoutTests` 17/17.
**Before that (P6-4):** the minimum window is the design size 1440×900 (row one needs 1,416 points with the sidebar; the faders starve below 900 tall) until the sidebar collapses in P6-6; above it the fourth row grows and the flexible sections spread, rendered at 1680×1100. The layout and the window are pinned Dark. The launch-time constraint noise is gone (the hidden classic hierarchy's explicit constraints are deactivated; OSC 2 was a point too narrow for its selector). `DesktopLayoutTests` 17/17, `KeybedTests`, `ScalingContainerTests`, `UILoadTests` green. Reinstalled.
**Before that (after P6-3):** the Presets and Tunings sheets had no visible Done button — the owner reported "no controls". A `UIButton(type: .system)` draws nothing in a Catalyst sheet under the Mac idiom; the toolbar's `.custom` buttons do, so `S1PanelSheet` uses one, and Escape and ⌘W also close the sheet. Seen fixed in a render of the presented view (`RENDER_PRESS=Presets RENDER_PRESENTED=1` with `Scripts/debug/desktop_render.py`; a Catalyst form sheet is its own AppKit window, so the main-window render never shows it). Reinstalled. `DesktopLayoutTests` 14/14.
**Before that (P6-3):** the sequencer row in the desktop dress — ticked faders with a capped handle, glowing note-on bars, an Arp | Seq two-way switch, arrow cells for direction, `[−] value [+]` steppers and a draggable tempo display. Three controls hit-tested against storyboard-sized rectangles (`Stepper`, `TempoStepper`, `ArpDirectionButton`); in the desktop dress the zones follow the bounds. Rendered and reinstalled. `DesktopLayoutTests` 13/13, `PointerInputTests` 19/19, `UILoadTests` 8/8.
**Before that (P6-2):** the rate knobs read musical rates under tempo sync ("3 bars", "1/16 note") and Hz/seconds otherwise, refreshed from `Manager.updateUI` and `dependentParameterDidChange` through `S1DesktopLayout.parameterDidChange`; the Filter header has a Low/Band/High picker driving the classic button; LFO chips and wave pickers draw in the desktop style; `LFOToggle`'s hit-test now splits at the real width (it split at a constant 100, so LFO 2 was 8 points wide in a 58-point chip). Rendered and reinstalled. `DesktopLayoutTests` 11/11.
**Before that:** the desktop layout exists and runs (P6-0, P6-1, ADR-045). The owner chose a
single-screen Mac layout from the design canvas
(<https://claude.ai/code/artifact/4623edc1-39b7-4667-a58d-eb810d176f41>, page 1) and asked for it as a
**new version that keeps the old one recoverable**. `S1DesktopLayout` (`Sources/SynthOneCore/Desktop/`)
builds a toolbar, sidebar, four rows of titled sections, a play bar and a status bar over the classic
`Manager`, and **moves the storyboard controls** into them: nothing is rebound, so every knob keeps its
range, taper, callback, MIDI learn and VoiceOver. Knobs draw an arc and brushed cap
(`Knob.drawsDesktopStyle`) with a value readout under each (`S1ControlCell`); toggles draw as switches.
The preset browser and the Tunings panel open as sheets (`S1PanelSheet`) until P6-6 and P6-7. The
classic layout stays behind `S1ClassicLayout` (View ▸ Classic Layout, next launch). **Rendered from the
running DerivedData app** at 1440×900 with `Scripts/debug/desktop_render.py` (new: it asks for a
standard-range image, because the HDR path in `standalone_driver.py`'s render stalled in Metal).
**Installed** 2026-09-12 19:49 with `Scripts/validate-au.sh`: `auval` passed, the installed framework matches the build (md5), no `S1ClassicLayout` override, and the app was opened for the owner to try. Not yet tried in Logic. The plists' version strings were literal 1.0 until P6-8; both now read `$(MARKETING_VERSION)`.
**Before that:** the standalone restarts its engine when the audio hardware changes (ADR-043). The owner
found the standalone silent. Its log showed a Bluetooth headset going out of ear 10 seconds after launch.
macOS moved the default output, and AVAudioEngine stopped itself and posted
`AVAudioEngineConfigurationChange`, which nothing handled. A microphone refusal logged in the same second
was a red herring. `S1AudioEngine` now restarts an engine that should be running, off the main thread,
up to five tries. Tested: 283 green, with two revert checks, each failing exactly its own test. Checked
live on the DerivedData standalone: stopped with the notification it restarted, and without it, it did
not. **Installed** 2026-09-11 14:54 with no host running: `auval` passed, and the installed app dylib,
framework and plugin binary match the build. **The owner confirmed** that audio works, including after
switching outputs.
**Before that:** no pop-ups at launch, and the standalone opens at its design size (ADR-042). The owner
saw upstream's "Synth One + Share One!" card clipped in the standalone, and the window reopening at
ADR-037's 1024×900 with empty space around the interface. At their choice, every launch-count prompt is
gone from both products: the rating alert, the review request, the Share card and the push request.
`LaunchPromptTests` covers it; with the old code, exactly 3 of its 4 tests fail. The window's maximum
size starts at 1024×800 and is raised a second after launch, and measured with lldb it opens at 1:1.
The revert check could not recreate the 900 reopening, so the cap is kept as a guard rather than proven
necessary. Tested (279 green). **Installed** 2026-09-11 14:38 with no host running: `auval` passed on the
first attempt, and the installed app dylib, framework and plugin binary match the measured build. At the
owner's request, the unused `group.com.badpackets303.ArcadeRuins` container from ADR-041's first signed
build, a byte-identical copy of their files, was moved to the Trash (not emptied). Not yet seen by the
owner.
**Before that:** the plugin saves presets (ADR-041). The owner joined the Apple Developer Program, so
the app and the plugin are signed by team 8RSH7U3222 and share banks, presets, favourites and tunings
through the App Group `8RSH7U3222.com.badpackets303.ArcadeRuins`. Settings stay each product's own.
On first launch the standalone copies the owner's files from `~/Library/Application Support/SynthOne`
into the group, once. A `group.`-style name was rejected by macOS. The first signed plugin launch also
raised a one-time consent prompt for its ad-hoc-era container, and every launch waited behind it until
the owner clicked Allow. **Installed** 2026-09-11 11:16. Seen in Logic: the plugin starred "Synthwave
1974" and `BankA.json` in the group changed by exactly that. Signed builds need
`-allowProvisioningUpdates -allowProvisioningDeviceRegistration` (in `Scripts/build.sh`).
`validate-au.sh` no longer reports success after failed `auval` attempts.
**Before that:** About and the header trimmed (ADR-040). The About screen loses "World's First Free &
Open-Source Pro iOS Synth" and the "How Synth One was made" video link, and the credits move up into the
space. The header loses More: with the mailing list stubbed out, it only re-added the 94 bonus presets
to BankA, duplicating them in the owner's. Factory BankA now includes them, so a fresh install or the
plugin still gets them. Tested (271 green, with a revert check). **Installed** 2026-09-11 08:53 with
no host running, together with ADR-039. `auval` passes, and the installed binaries and the About,
Header and Main storyboards match the plain build. In the scratch host the plugin loaded its presets
at launch. Not yet seen by the owner.
**Before that:** one view and no Show/Hide (ADR-039). The owner kept the compact look: upstream's
1024×768, with whole 88-point shaded keys at 4 octaves running to the bottom edge. They dropped the
toggle, because Show only lengthened the keys. ADR-037's window resizing is reverted; those files are
back to b7a9313. The button is hidden, and a saved "shown" is ignored. Tested (269 green, with a
revert check). Installed with ADR-040.
**Before that:** the plugin's presets panel is no longer empty, and ▶/◀ no longer crash it (ADR-038).
A plain build of the plugin cannot read the shared preset folder, but `Disk.exists` said the files
were there, so the load failed silently and ▶ indexed an empty bank. Unreadable now counts as absent,
so the plugin loads the factory banks. Every earlier install had shipped a test-signed plugin with
read access to `/`, and `validate-au.sh` now refuses one. Tested (274 green, revert checks both ways).
**Installed** 2026-09-11 08:30 with no host running. The installed plugin is plain-signed, and in the
scratch host it loaded BankA and wrote its current preset at launch, which it had not done since the
first plain install. Not yet seen in Logic.
**Earlier, now reverted:** Show and Hide resize the window (ADR-037, P3-6c). The owner found Show's keyboard
"absolutely massive" in Logic. Shown is now 1024×868, with the keys filling the space under the
panels. Hidden is 1024×768, with whole 88-point keys. It opens hidden, and the keyboard never covers
the lower panel. Tested (271 green, with a revert check). In the running standalone, a saved "shown"
grew the window from 800 to 900 points with its top edge fixed. **Installed** 2026-09-10 21:25 with
Logic quit: `auval` passes, and the installed framework, plugin binary and compiled `Main.storyboard`
match the tested build. Not yet tried in Logic.
**Earlier:** the test bundle no longer writes the owner's files (ADR-036). Its principal class
points `Disk`, `.caches` included, at a temporary folder before any test runs. A full run (266 tests,
0 failures) left the owner's `settings.json`, `tunings_v1.json` and `~/Library/Caches/currentPreset.json`
unchanged in md5 and mtime. **The revert check was not run**: the permission classifier refused the
edit that removes the redirect. Test-only, so there is nothing to install.
**Earlier:** the keybed (ADR-035, P3-6c; its Show was superseded by ADR-037), the owner's choice from mockups. The interface is
1024×868. The keyboard is hidden by default at 4 octaves, its keys fill the space under the panels
instead of running off the bottom of the window, and they are shaded. Tested (262 green, with a
revert check). **Installed** 2026-09-10 21:01 with Logic quit, by `Scripts/validate-au.sh`. `auval`
passes, and the installed framework's md5 and compiled `Main.storyboard` match the tested build. Not
yet seen by the owner, in the standalone or in Logic.
**Earlier:** the preset and bank editors' name fields are readable in Dark appearance (ADR-034).
Tested and checked in the running standalone. Installed with the keybed.
**Earlier still:** the preset editor no longer crashes the app and the plugin; its bank picker is now a
table (ADR-033). Tested, checked in the running standalone, and **installed** 2026-09-10 18:49 with
Logic quit. Not yet tried in Logic.
**Also:** the header wordmark is now the owner's own artwork (ADR-029, amended), kept after the owner
saw it in Logic. It was installed 2026-09-10 19:00. The About and mailing-list logos followed; they are
committed but not yet installed or seen in the running app.

## Where things stand

**Phases 0–3 are complete, Phase 4 is done apart from the host matrix (P4-7), and P5-4 was pulled
forward.** The owner has run the plugin in Logic Pro and confirmed sound, automation, host tempo,
the animated waveform and the new wordmark.

**The plugin is the whole instrument.** The extension hosts all 12 panels (P4-6). `Conductor.synth`
is `S1SynthControlling`, so one interface drives `AKSynthOne` in the app and `S1HostedSynth` in the
plugin. Control moves go through the `AUParameterTree`, so a host records them, and host moves reach
the controls through an observer token without echoing back. Host tempo is authoritative over
`arpRate` (ADR-027); transport stop releases voices (ADR-025); `fullState` carries the tuning table
(ADR-024); all 695 presets are offered as factory presets. The Generators waveform is fed from the
render block through a lock-free seqlock ring, because a plugin has no node to tap (ADR-028). The
Record controls are hidden in the plugin, since recording is the host's job.

**The standalone** runs at Optimize-for-Mac 100% (ADR-023), plays from CoreMIDI and the typing
keyboard, resizes 0.5×–3× (ADR-019), and treats `Octave:` as one global octave that also shifts
hardware MIDI. Recordings go to `~/Music/Arcade Ruins`.

**Every `UIButton` has to opt out of Mac drawing.** Under the Mac idiom a button never receives
`touchesBegan` (ADR-026), and it is painted with macOS chrome and accent colours. Six custom classes
opt out in `init`; the header's five plain storyboard buttons are covered by a hierarchy walk,
`useDesignedButtonAppearanceThroughout()` (ADR-029). **If a control looks boxed, turns blue, or does
nothing, check this first.**

**It is called Arcade Ruins now** (ADR-029). `LICENSE` (MIT), `NOTICE.md` and `README.md` exist. The
display name, bundle IDs (`com.badpackets303.ArcadeRuins`, `.AUv3`), `.app`/`.appex` names and the AU
identity **`aumu`/`ruin`/`BP03`** all changed, and the subtype is now permanent. The header wordmark
is the owner's own artwork, `Scripts/branding/source/Arcade-Ruins.png`: orange ARCADE and grey RUINS,
fitted and centred in the header's `Title Button` and in the About and mailing-list logos. The icon is
a synthwave horizon. `Scripts/branding/generate.py` builds all of them.
Internal targets, the `SynthOneCore` module and the repo directory are **deliberately** still
`SynthOne*` (ADR-009). The owner chose **not** to retheme the panels.

## ▶ Next action — the owner's next layout request; the release decisions stand

**Resume here.** `git checkout desktop-ui`, `Scripts/build.sh`, then look at the layout:
`DRIVER_OUT=/tmp/arcade-ruins-debug RENDER_TAG=desktop RENDER_SELECT="Brice Beasley,0: " xcrun lldb -b -o "command script import Scripts/debug/desktop_render.py"`
writes `/tmp/arcade-ruins-debug/desktop.png` from the DerivedData app with a factory preset loaded
(`RENDER_SELECT` picks table rows by label text; without it the owner's own banks show).
`RENDER_ARGS="-S1Skin arcade"` (or `neonRuins`) renders a skin; `RENDER_PRESS=Presets` opens the browser.

**How a layout task goes (P6–P8, every time):** edit `Sources/SynthOneCore/Desktop/S1DesktopLayout+Rows.swift`
(sizes, sections) or `S1DesktopLayout.swift` (toolbar, browser, play/status bars) → `xcodebuild … build`
into `./DerivedData` → render (command above; `RENDER_ARGS="-S1Skin arcade"` for the skin, `RENDER_PRESS=Presets`
for the browser) → read the PNG and `*.stderr` for "Unable to simultaneously" → desktop suites into
`/tmp/SynthOneTestDD2` with `CODE_SIGNING_ALLOWED=NO -only-testing:SynthOneTests/DesktopLayoutTests
-only-testing:SynthOneTests/SkinTests -only-testing:SynthOneTests/DesktopPluginTests` → `Scripts/validate-au.sh`
(installs to /Applications, runs `auval`; the owner's running copy keeps the old build until relaunched) →
`docs/screenshots/` from the renders → PORT_PLAN task entry, STATE header + log, ADR if a decision → commit.
New Swift files need `xcodegen generate` first, and that rewrites both `Info.plist`s from `project.yml`.

**Before any release: run the full suite once** (Phases 7 and 8 have only had the desktop suites):
`xcodebuild … -derivedDataPath /tmp/SynthOneTestDD CODE_SIGNING_ALLOWED=NO test`, ~20 minutes, and the
`StorageIsolationTests` stall on a real support folder may recur (it passes; it is slow).

**Next layout task: whatever the owner asks.** P8-1 covered the LFO section, knob sizes and OSC 2.
Still visible in the renders: the sequencer's faders have 84 points of travel at 900 tall (100 before
P8-0's taller rows); `MorphSelector` is classic-drawn; Voice is mostly empty; OSC 1's single knob is
44 because the selector above it bounds the row.

**The release decisions (unchanged):**

1. **Try 0.3.0** — Settings ▸ Layout and ▸ Skin (relaunch), the drop-down preset browser in the
   desktop layout, and Logic after relaunching it. **The plugin's Settings popover has not been
   opened inside a host yet**: it anchors to a view in the host's window, which is where Apple's
   share sheet failed (ADR-044) — worth being the first thing tried there. Take the new
   `docs/screenshots/logic-plugin.png` while you are in Logic; the README's is 0.1.0's.
2. **Merged.** The owner's word on 2026-09-14: "Ship it as one release and merge it." `desktop-ui`
   is merged into `main` and tagged `v0.3.0`; `docs/release-notes.md` is one 0.3.0 entry covering
   Phases 6–8, with 0.2.0 folded in (it was prepared and never released).
3. **Publish.** `Scripts/publish-public.sh` exports HEAD into `../ArcadeRuins-public` and commits there
   but never pushes; **confirm with the owner before pushing anything public.** `Scripts/release.sh`
   builds, signs and notarises. **Notarisation works** (ADR-053): the three 0.1.0-era submissions that
   looked hung were all **Accepted** — the service simply took hours. `notarytool submit --wait` may
   sit for a long time, and abandoning the wait loses nothing; `notarytool history` and `log` fetch
   the verdict by id afterwards. The stale processes from that attempt are gone.

**Small things noticed, not fixed:** `MorphSelector` keeps its classic drawing under both skins. The
preset list's selected-row highlight is the classic grey under Arcade too (`PresetCell`, classic
code). The drop-down's category list opens scrolled to wherever the classic panel left it.

**Done in P8-0, kept for reference:** `S1DesktopLayout.presetPanel` / `presetFieldButton` /
`setPresetPanelVisible(_:animated:)`; `Manager.desktopTogglePresets(_:)` / `desktopClosePresets(_:)`;
`S1DesktopTheme.presetPanelWidth/Height` (380 × 720, the height yielding to the play bar).

**Done in P7, kept for reference:** `S1Skins.current` is read while views are built (tests set it
and put it back in `tearDown`); a new layout colour is a new `S1Palette` entry, which the compiler
demands for both skins; `S1ArcadeArt.Seed` is the seeded generator behind every random element.

**Done in P6-7, kept for reference:** card sizes live in `S1DesktopLayout.cardSizes`, keyed by segue
identifier; a wrapped view carries `S1DesktopLayout.dressedTag` so it is never wrapped twice.

**Done in P6-6, kept for reference:** `PresetsViewController.rowHeight` and
`PresetsCategoriesViewController.rowHeight` (44 classic; 30 / 28 in the sidebar);
`Manager.desktopToggleSidebar(_:)` / `desktopSearchPresets(_:)` are the menu and key-command
targets; `S1DesktopLayout.setSidebarVisible(_:)` posts `SynthOneApp.desktopSidebarDidChange`.

**Done in P6-5, kept for reference:** `Scripts/debug/auhost.swift` (compile with
`xcrun swiftc -O … -o /tmp/auhost`) loads the *installed* plugin out of process and sizes its window
to `preferredContentSize`; the scratchpad `winlist` tool read 1440×932. Rendering inside the
extension is still not possible from here; Logic is the visual check.

**Done in P6-4, kept for reference:** `RENDER_SIZE=1680x1100` pins the scene's size restrictions
(the geometry-preferences API threw); `RENDER_PRESS=Presets RENDER_PRESENTED=1` renders a sheet.

**Done in P6-3, kept for reference:** the sequencer controls draw through `drawsDesktopStyle` flags
set in `sequencerRow()`; the hit zones are `Stepper.hitZone(for:)`, `TempoStepper.hitZone(for:)`,
`ArpDirectionButton.cellWidth`.

**Done in P6-2, kept for reference:**
- The LFO rate, delay time and auto-pan rate knobs are *dependent* parameters normalised 0…1
  (`EffectsPanelController` lines 111–140); their readouts show a percentage. Show the rate the header
  display strip shows (`Rate.fromFrequency`, `Rate.fromTime`) when tempo sync is on, Hz/s otherwise.
- Detune reads raw (`morph2Detuning`); the storyboard called it detune, upstream's strip prints the
  decimal. Decide the unit from `S1DSPKernel+parameters.mm`.
- Filter type: `FilterTypeButton` sits in the Filter header as a plain button; a segmented Low/Band/High
  would match the canvas. `GeneratorsPanelController.updateUI` still relabels two hidden labels.
- `LFOToggle` and `LFOWavePicker` still draw with their classic kits (chips at 58×22 are legible but
  small); `MorphSelector` too. Either restyle by flag, as `Knob` and `ToggleButton` were, or accept.
- The sequencer's `VerticalSlider`, `SliderTransposeButton` and `ArpButton` draw with their classic
  kits at 40 points wide. They work; P6-3 restyles them.
- Constraint noise: the hidden classic hierarchy logs unsatisfiable autoresizing constraints at launch.
  Harmless; P6-4 silences it.

**What to check with the owner before P6-5:** whether the plugin should get this layout at once
(1440×900 in Logic is large) or a sidebar-less variant.

**Traps met this session, for the next one:**
- A presented form sheet is an AppKit sheet window under Catalyst: `scene.windows` does not list it and rendering `NSApp.windows` gives blank layers. Render `presentedViewController.view.layer` (`RENDER_PRESENTED=1`) instead. `UIButton(type: .system)` draws nothing in such a sheet; use `.custom`.
- `screencapture -l` needs Screen Recording permission the tool does not have ("could not create
  image from window"); render in-process with the lldb driver instead.
- macOS restored the classic 1024×800 window frame over the desktop's `window.frame`, and the 1280×820
  minimum then produced a 1280×820 window. `SceneDelegate` pins min = max = 1440×900 for one second
  (ADR-042's trick) and then frees the range.
- `Manager.viewDidLoad` loads every panel except Tunings, so their controls can be moved right after
  `loadViewIfNeeded()`. The Tunings panel and the developer panel are not moved; the bound-controls test
  excludes them by panel view.
- The test bundle registers `S1ClassicLayout = true` (`TestStorageIsolation`), so
  `makeRootViewController()` still returns the scaling container in the 20-odd tests that cast to it.

---

## ▶ Next action — publishing waits on the owner; then P4-7

### The plugin's presets (ADR-038): check in Logic, then decide whether it reads the owner's presets

- **Installed** 2026-09-11 08:30. `auval` passes, the installed binaries and storyboard match the
  plain build, and the plugin has no test-runner entitlements. In `Scripts/debug/auhost.swift` it
  rewrote `currentPreset.json` two seconds after launch, with BankA position 0, "Synthwave 1974".
- **The owner checks in Logic:** the list shows the factory banks, ▶/◀ step through them, and Favorites
  is empty (the plugin cannot save favourites).
- **The owner's decision:** should the plugin list the owner's own presets and favourites? That needs
  read access to `~/Library/Application Support/SynthOne`, either through a read-only
  temporary-exception entitlement (not measured under ad-hoc signing; ADR-018 found the read-write
  kind denied) or through ADR-020's user-picked folder bookmark. Until then the plugin shows the
  factory banks only, which is what ADR-020 intended.

### The keyboard strip (ADR-035, ADR-039): one view, no Show/Hide

- **The owner kept the compact view and dropped Show/Hide** (ADR-039). The interface is upstream's
  1024×768, with whole 88-point shaded keys at 4 octaves. ADR-037's window resizing is reverted.
  Installed 2026-09-11 08:53, with ADR-040.
- **The toolbar's right end is empty** where the button was (x 934–1009). Ask the owner whether to
  re-space Transpose and Octave into it.
- **The test suite no longer writes the owner's files** (ADR-036). What earlier runs wrote is still in
  the owner's `settings.json`: `keybedVersion` 1, so the one-time switch will not run on it again, and
  every MIDI-learn CC at 255. It was not restored, since there is no copy from before. The owner may
  want to re-learn any CCs they had.
- **Revert check for ADR-036, not run.** The classifier refused the edit that removes the redirect.
  With the owner's approval, point `Disk.defaultSharedSupportURL` and `defaultCachesURL` at a scratch
  folder, drop the two assignments in `TestStorageIsolation.init`, and run only
  `StorageIsolationTests`. All four should fail.

### 0. The plugin's two MIDI routes — fixed (ADR-031) and checked live in Logic

**Implemented 2026-09-10 with the owner's approval.** The host is now the plugin's only MIDI source:
`S1HostMIDI` ports the standalone's MIDI chain to the render thread, controls and held keys come back
to `Manager`, and the plugin opens no CoreMIDI inputs. 242 tests green; **installed** by
`Scripts/validate-au.sh` with no host running (auval passed, and the installed framework's md5 matches
the tested build).

**Checked live in Logic, 2026-09-10, 14:21 launch.** The owner opened Logic with Arcade Ruins on one
track and another instrument on a second. The measurement below was repeated with the same driver
and stimulus — no CC1 this time, so the patch was not touched:
- **Before any note:** the extension's log has no `S1MIDI: opened` or `midi setup change` lines,
  although its interface had loaded. The system MIDI list no longer contains an
  "AudioKit Synth One" source or destination. No new crash reports.
- **Arcade Ruins' track selected:** one host note-on became exactly one `startNote(60, 127)` on
  `AUOOPRenderingServer`, and the kernel rendered it (mono voice; the preset's arpeggiator played 67
  and 72). The note-off gave one `stopNote(60)` on the same thread. CoreMIDI, `S1HostedSynth.play`
  and main-thread note breakpoints: **zero hits**. Logic's extra note-off about 3 s later, seen last
  session too, now does nothing, because the key was already released.
- **The other track selected:** all nine breakpoints resolved, and **none fired**. Nothing reached
  Arcade Ruins. The previous capture, minutes earlier with the same stimulus, is the control that
  shows those breakpoints do fire.

**Velocity sensitivity, decided by the owner:** always on, in the plugin and the standalone. Every MIDI
note plays at the velocity it arrives with, and the switch in MIDI settings is locked on in both
(ADR-032). Installed 2026-09-10 14:46; `auval` passes.

What led here, kept for the record:

**Asked 2026-09-10 to answer with evidence and report before changing anything.**
Measured with lldb on the extension inside the owner's running Logic. The stimulus was one C4, one
CC1 and one centred bend sent to `IAC Driver Bus 1` — a source both Logic and the plugin listen to,
which puts it in the same position as a hardware keyboard. The trace, in order:

```
COREMIDI     90 3C 40          CoreMIDI thread
KERNEL-MIDI  90 3C 40          AUOOPRenderingServer   (Logic's routing, via the render block)
startNote    note=60 vel=64    AUOOPRenderingServer
hosted.play  note=48 vel=127   main thread            (the plugin's own CoreMIDI input)
startNote    note=48 vel=127   main thread
mgr.CC 1=64 → wheel setVerticalValueFrom(64) → setSynthParameter(cutoff, 2818.5)   main thread
KERNEL-MIDI  B0 01 40          render thread — nothing happens
KERNEL-MIDI  E0 00 40          render thread — nothing happens
```

- **Doubled — as two different notes.** One key press started two voices: Logic's note as sent, and
  the CoreMIDI copy after the plugin's `Octave:` shift (one step down → 48) and its velocity setting
  (`velocitySensitive` defaults to off → 127). Both note-offs arrived, so nothing stuck.
- **Two threads entered `S1DSPKernel::startNote` for one key.** Upstream documents it as "not called
  by render thread", and it mutates an `NSMutableArray` — a crash risk, not only a sound bug.
- **CC1: confirmed.** Hardware CC1 moves the wheel and writes cutoff *through the parameter tree*, so
  to Logic it is a plugin parameter move. The same CC1 arriving from Logic reaches the kernel, which
  ignores it. By the code, CC64 (sustain), pitch bend, program change and bank select are
  CoreMIDI-only in the same way.
- **Unselected track: confirmed — it plays.** A second capture had another track selected, Arcade
  Ruins' R and I off and its window closed. Logic delivered **nothing** to the render block, and the
  plugin's CoreMIDI input still ran `startNote(48, 127)`. Read from the kernel's voices on the render
  thread, it sounded: mono voice, amp 0.74, notes 55 then 60, which looks like the preset's
  arpeggiator/sequencer playing the held 48. A closed window changes nothing — `S1MIDI` holds
  `Manager` strongly.
- **Controllers bypass routing the same way.** A centred bend reached `setDependentParameter` — on
  **CoreMIDI's own thread**, because `receivedMIDIPitchWheel` never hops to main.
- **Real hardware did it too.** During that capture, three events the test did not send (D4 off, G3
  on at velocity 1, G3 off) reached the plugin and not the render block. The plugin played that G3
  an octave down at velocity 127. Probably a brushed key; to be confirmed with the owner.
- **The two "AudioKit Synth One" sources in the original log were two processes**, the standalone
  and the extension, not two `Manager`s. `S1MIDI` allows one virtual endpoint per process.
- **`Conductor.isHosted` is the switch.** `startHosted` sets it before `makeRootViewController`, so
  it is already true in `Manager.viewDidLoad`.

**The proposal, as approved.** What was built is ADR-031, which records where it departs from this.
1. When `conductor.isHosted`, `Manager.viewDidLoad` does not touch `S1MIDI`: no client, no inputs, no
   virtual endpoints. The standalone's path does not change.
2. **Notes stay in the render block.** An offline bounce renders faster than real time, and only the
   render block is sample-accurate. The kernel takes over what the CoreMIDI route added: `Octave:`
   shift, velocity sensitivity, MIDI channel, white-keys-only, hold, the sustain pedal (CC64 —
   upstream's own TODO in `Manager+MIDIListener`) and pitch bend. The interface pushes those settings
   in as atomics. Optionally, on-screen keys also go through `scheduleMIDIEventBlock`, so only one
   thread ever calls `startNote`.
3. **Control-rate MIDI is copied out of the render block** into a lock-free ring (the `S1Scope` shape,
   ADR-028). The main thread drains it into `Manager`'s existing `AKMIDIListener` methods for the mod
   wheel, MIDI learn, program change and bank select. Notes arrive there display-only, to light keys.

Rejected:
- *Play host notes from the main thread through `Manager` unchanged* — loses sample accuracy and
  breaks offline bounce.
- *Keep CoreMIDI for controls only* — the pedal, wheel and program change still bypass Logic's
  routing and reach every instance.
- *Only stop opening CoreMIDI* — fixes the doubling, and silently drops pedal, wheel, bend,
  `Octave:`, MIDI learn and program change from a controller, which breaks requirement 2.

### 1. Publish to GitHub — **the repository is public, 2026-09-11 21:00**; the download waits on Apple

**Live: <https://github.com/badpackets303/ArcadeRuins>** — public, 706 files, two export commits, both
authored `311791666+badpackets303@users.noreply.github.com`. Verified on the site: no `upstream/`, no
`docs/reference/appstore/`, all three screenshots present, README showing the notarisation note.
`Scripts/publish-public.sh` re-exports; the working copy is `~/Developer/ArcadeRuins-public`.

**The release is not published yet, and notarisation is not the reason** (ADR-053, corrected
2026-09-14). All three submissions that looked hung — `a44b54bd…` and `99f2afe8…` (the 0.1.0-era app)
and `05f72def…` (the 12 KB `hello` control) — are **Accepted**; `notarytool log a44b54bd…` reads
"Ready for distribution", with ticket contents for the app, the framework and both architectures.
The service took hours rather than the minutes `--wait` suggests, and each attempt was abandoned
before its verdict landed. **No developer-support ticket is needed and the packaging was never in
question.** A run that appears to hang should be checked with `notarytool history` before anything is
changed or resubmitted.

The packaging, for the record: `ditto -c -k --keepParent`; Developer ID Application (8RSH7U3222) on
the app, the appex, the framework and the binary, each with the hardened runtime and a secure
timestamp, no `get-task-allow`; `codesign --verify --deep --strict` passes; universal x86_64 + arm64.

**The owner's decisions, 2026-09-11** (asked again, answered):
- **A new public repository, `badpackets303/ArcadeRuins`, with a clean start.** `SynthOneMac` stays
  private with the full history. The export leaves out `upstream/` (AudioKit's Audiobus key) and
  `docs/reference/appstore/`, and has no old commits carrying the owner's personal email.
  `Scripts/publish-public.sh` makes it, committing without pushing.
- **Notarised downloads.** `Scripts/release.sh` archives, exports with Developer ID, checks the
  signature, notarises, staples and zips. **It needs the owner to create a Developer ID Application
  certificate and store notarisation credentials as keychain profile `ArcadeRuins`.** Neither existed
  at 16:40.
- **Screenshots:** the standalone rendered from the running app with `Scripts/debug` (window layer,
  top 64 px cropped), and the owner's capture of the plugin in Logic. Both are in `docs/screenshots/`.

Prepared (commit 98380b9 and after): the release and export scripts, `ENABLE_HARDENED_RUNTIME: YES`,
the wavetable test reading the shipped bundle, NOTICE and README updates. The About links were
re-pointed from the private `SynthOneMac` to `ArcadeRuins`, and the preset browser's leftover
"SYNTH ONE PRESETS" heading became "ARCADE RUINS PRESETS". **Before pushing, confirm with the owner
once more: going public is effectively irreversible.**

The audit notes below are the original questions, kept for the record.

The audit is done (2026-09-09), and nothing was changed.

**a. What goes public.** A full-history secret scan (`git log --all -p`) is clean for our own code.
Two things in the repo are not ours:
- **AudioKit's live Audiobus API key** in `upstream/AudioKitSynthOne/Private.swift`. It is already
  public in AudioKit's own repo. It is also in our history, so editing the file now would not remove
  it from the past.
- **`docs/reference/appstore/`** — 9.5 MB of AudioKit's App Store screenshots, wordmark included.

Options offered:
- **(recommended)** Stop tracking `upstream/` and the screenshots, and fetch them with
  `Scripts/fetch-references.sh` the way `.references/` already works (update CLAUDE.md to match).
- Blank the key line, which breaks the `upstream/` read-only rule (record the exception), and drop
  the screenshots.
- Publish as-is.

**b. Whether downloads are usable. Measured, not assumed:**

```
codesign -dv /Applications/ArcadeRuins.app           →  Signature=adhoc, TeamIdentifier=not set
spctl -a -vvv -t exec /Applications/ArcadeRuins.app  →  rejected
```

Gatekeeper rejects the build even locally. A downloaded copy is also quarantined, and macOS reports
it as "damaged and can't be opened" with no dialog to click through. The user workaround is
`xattr -dr com.apple.quarantine /Applications/ArcadeRuins.app`. The real fix is P5-2 — Developer ID
plus notarisation, which means reversing ADR-005.

Options offered:
- **(recommended)** A release zip, with that instruction stated plainly.
- Source only until P5-2.
- A zip plus an `install.sh` that strips the quarantine.

**Ready once the answers are in.** The Release build works; `docs/04-build-and-test.md` →
*Release build and distribution* has the exact commands. Also raise with the owner that the GitHub
repo is still named **SynthOneMac**.

### 2. P4-7 — host validation matrix

Logic Pro, GarageBand, Live, Reaper, Bitwig: instantiate, sound, UI, automation, state
save/restore, multiple instances, offline bounce. Fill in the table under *Host validation matrix*.
Logic is the owner's and has been partly exercised already.

### Owner to-dos

- **Open the preset editor on a preset in Logic** (ADR-033, installed 2026-09-10).
- **Decide on the Developer account.** Its App Group would give the plugin a shared folder it can
  write, so the star, rename, duplicate, reorder and Save could work in the plugin. Preset saving and
  Share stay as they are until then.
- **Delete `/Applications/SynthOne.app`.** It still registers the pre-rename `aumu`/`aks1`/`BP03`, so
  hosts list two plugins. The sandbox blocked me from removing it.
- **Visual sign-off** on the Mac idiom against `docs/reference/appstore/`, including the header
  buttons after the chrome fix. The test can only assert the style that was *set*, because Mac-style
  controls cannot be rendered in a test bundle.
- **ADR-020's user-preset route** — document picker plus security-scoped bookmark, inside the
  sandboxed extension — is still untested.

### Verify

```bash
Scripts/build.sh
xcodebuild -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath ./DerivedData test
Scripts/validate-au.sh          # installs to /Applications; quit and relaunch any host afterwards
```

---

## Task board

Legend: `[ ]` todo · `[~]` in progress · `[x]` done & verified · `[!]` blocked · `[–]` dropped

### Phase 0 — Feasibility & foundations — **COMPLETE**
- [x] **P0-1** Xcode 26.6 selected and licensed; XcodeGen 2.46.0 installed; `-runFirstLaunch` done
- [x] **P0-2** Repo at `~/Developer/SynthOne` (out of iCloud — R-7 closed), git initialized, `main`
- [x] **P0-3** `upstream/` vendored @ `6466a37` as read-only plain files
- [x] **P0-4** ⚑ Catalyst AUv3 spike — **PASSED. Track A.** auval clean; loads in- and
      out-of-process; storyboard confirmed loading inside the extension. See ADR-001.
      Also settled ADR-006 (no App Groups ad-hoc) and ADR-007 (77% Catalyst scaling).
- [x] **P0-5** Reference baseline acquired **without an iPad**: the upstream repo has no
      screenshots, so full-resolution captures came from the live App Store listing
      (`docs/reference/appstore/`, 2048×1535). 8 of 12 panels covered; the other 4 are
      trivial/debug/slated-for-removal and specified by their storyboards.
      Two caveats recorded in `docs/reference/README.md`: the shipping app is **v1.9.2** vs our
      source **v1.4.1**, and the six shots span **more than one app version** (only `ipad-06`
      matches our source's storyboard labels).

### Phase 1 — Build system + AudioKit excision — **COMPLETE**
- [x] **P1-1** `project.yml` / XcodeGen target graph — all 6 targets build; `SynthOneCore` and the
      full app both green; 2 unit tests pass including a Soundpipe→Swift link self-test; app bundle
      verified (`platform MACCATALYST`, `minos 14.0`, framework embedded, appex in PlugIns, no
      stray `.a`); **and the AU stub already passes `auval`**. See ADR-008.
- [x] **P1-2** Soundpipe vendored. ⚠️ **Re-done at P1-5**: originally taken from canonical
      upstream, now from **AudioKit's fork** — canonical lacks the band-limited `sp_oscmorph2d`
      that is Synth One's anti-aliasing. See ADR-011 and `Sources/Soundpipe/VENDORING.md`.
- [x] **P1-3** `S1Support`: `AKInterop.h`/`AK_ENUM`, `AKLog`, `AKSettings`, `AKTypes`, `AKHelpers`
      written; `AKTable` + all 9 Microtonality files ported from AudioKit 4.9.2 (`03fecf80`, MIT).
      **AudioKit 4.9.2 does not compile under modern Swift** — 3 integer/float narrowing fixes
      required, each with a regression test. 16 tests green incl. Scala import and decoding a real
      shipped wavetable. Names kept per ADR-009. See `Sources/S1Support/PORTING.md`.
- [x] **P1-4** AudioUnitBase: `DSPKernel`, `AKDSPKernel`, `AKSoundpipeKernel`, `AKOutputBuffered`,
      `BufferedAudioBus`, `AKAudioUnit` ported from AudioKit 4.9.2/Apple sample. Headers live under
      `AudioUnitBase/AudioKit/` **so P1-5's `#import "AudioKit/..."` lines need no edits.** Proven by
      `S1TestToneAudioUnit`, a structural rehearsal for `S1AudioUnit`, rendering a 440 Hz tone to
      ±3 Hz. 22 tests green. One upstream bug fixed (`init` self-assignment). See
      `Sources/SynthOneCore/AudioUnitBase/PORTING.md` and ADR-010.
- [x] **P1-5** DSP ported: `S1DSPKernel` (12 `.mm`), `S1AudioUnit`, `S1NoteState`, `S1Sequencer`,
      `S1Parameter.h`, TAAE, 54 wavetable resources. **The kernel compiles on macOS.** Only 8 lines
      of edits across 8 files (7 vestigial imports + ADR-010's 3 `AKSettings` reads). Forced a
      correction to P1-2 — see ADR-011. `Sources/SynthOneCore/DSP/PORTING.md`.
- [x] **P1-6** ⚑ Headless render harness → **first sound on macOS.** `S1AudioUnit` rendered
      offline with no engine and no UI: audible, in tune, polyphonic, releasing. 10 new tests.
      Required making `S1AudioUnit.h`/`S1Parameter.h` public and fixing our `AK_ENUM` shim, which
      had been spelled `NS_ENUM` and only compiled because it was reached from Obj-C++ (ADR-012).
      Found and pinned the post-allocation pitch sweep (ADR-013).

### Phase 2 — Audio engine & regression safety net — **COMPLETE**
- [x] **P2-1** `S1AudioEngine` replaces the AudioKit engine — an object, not a global (ADR-014).
      `AKNode`/`AKPolyphonicNode`/`AKMixer`/`AKComponent` + `AKSynthOne.swift` ported.
      `Conductor.swift` deferred to Phase 3 (it is a UI controller; its audio half is now
      `S1AudioEngine`). Found ADR-015 — the `outputNode` ordering rule, worth 90s a test.
- [x] **P2-2** `S1AudioSession` protocol; `S1SystemAudioSession` (app) and `S1HostedAudioSession`
      (plugin, no-op). The no-op is the **default** — the dangerous mistake is the silent one.
- [x] **P2-3** `S1NodeRecorder` — an `AVAudioFile` tap writing WAV directly, so AudioKit's
      asynchronous CAF→WAV export step is gone. `AudioRecorder.swift` ported onto it.
- [x] **P2-4** ⚑ Golden-WAV regression tests — 20 shipped presets, all 13 banks, float32 goldens.
      Ported the preset model (`Preset.swift` + `Preset+Synth.swift`, 695 presets decode) to get
      there. Catches a 0.24% LFO-constant change in 17 of 20. ADR-016.

### Phase 3 — Standalone Catalyst app — **COMPLETE**
- [x] **P3-1** 12 storyboards + **153** Swift files compile and load under Catalyst; the app
      launches and every panel renders. `SynthOneApp` façade (ADR-017); `Conductor` ported. Found
      four real bugs, including a Debug-only trap that killed the Tunings panel on launch.
      **Idiom still undecided** — moved to its own line below (ADR-007)
- [x] **P3-1b** **Optimize Interface for Mac** — the owner's decision (ADR-023). The switch is
      `TARGETED_DEVICE_FAMILY: "2,6"`; family 6 is Mac. Measured: a launched build reports
      `userInterfaceIdiom` **5 (`.mac`)**, was 1 (`.pad`). Pinned by
      `testBothBundlesUseTheMacIdiom`. **Owner's visual sign-off against
      `docs/reference/appstore/` is still outstanding**, and the plugin's half is unverified
      until P4-6
- [x] **P3-2** `S1PlatformServices` no-op protocol; call sites preserved. Stripped AudioKit's
      live Audiobus credential from `Private.swift`
- [x] **P3-3** `Disk` on `FileManager` → `~/Library/Application Support/SynthOne/`, with a
      once-only migration out of the old sandbox container (verified: 15 files). App unsandboxed —
      the temporary-exception entitlement is **denied under ad-hoc signing** (ADR-018). The AUv3
      cannot see these files and **now provably cannot**, whatever we do without a Team ID
      (ADR-020) — so the scope is settled rather than open: plugin gets factory presets
- [x] **P3-4** `S1MIDI` over CoreMIDI — enumeration, connect by name, virtual endpoints, hot-plug,
      UMP parsing into `AKMIDIListener`. Verified against real hardware. Bluetooth button opens
      Audio MIDI Setup. **Fixed a 72-second launch**: `.playAndRecord` was prompting for the
      microphone (ADR-015 correction)
- [x] **P3-5** Knobs: scroll wheel + ⌥ fine drag. **Computer-keyboard notes** (Musical Typing).
      Touch pads and ADSR already single-pointer. Fixed a latent upstream bug: `Knob` only wired
      its gestures in `init?(coder:)`
- [x] **P3-6** `SceneDelegate` — window title, size bounds, hidden title bar. Menu bar that
      removes what a synth cannot use and adds **Panic (⌘.)**
- [x] **P3-6b** Resizable window: `S1ScalingContainer` scales the fixed layout uniformly instead of
      relayouting it. Opens 1:1, resizes 0.5×–3×, hit-testing follows. ADR-019
- [x] **P3-6c** Keybed, at the owner's request: 1024×868, keyboard hidden by default at 4 octaves,
      hidden keys fill the space under the panels, shaded. Tested; installed 2026-09-10 21:01. ADR-035.
      Then Show and Hide resize the window: shown 1024×868, hidden 1024×768 with 88-point keys.
      Tested; installed 2026-09-10 21:25. ADR-037
- [–] P3-7 Ableton Link — **DROPPED** by owner (ADR-004). Also removes `AKLinkButton` and the
      Link UI in the header panel.

### Phase 4 — AUv3 plugin — P4-7 left (the owner's host checks)
- [x] **P4-1** Extension target + `AudioComponents` verified and guarded by tests. **Answered
      ADR-018:** an unsandboxed AUv3 will not load (`OpenAComponent: result: 4`), and a sandboxed one
      cannot *implicitly* read the app's presets but can read the framework bundle. A user-selected
      route (picker + security-scoped bookmark) should carry user presets; entitlements added,
      **verification is P4-6's**. ADR-020
- [x] **P4-2** Plugin vends the real `S1AudioUnit`; `S1Wavetables` shared with the standalone.
      **Fixed a render-thread segfault** in `DSPKernel::processWithEvents` — an unsigned cast of a
      signed difference, which every host automation move would have triggered (ADR-021)
- [x] **P4-3** ⚑ Host automation reaches the DSP. `S1DSPKernel::startRamp` was `{}` upstream, so
      every parameter event was received and discarded. Implemented, with three judgement calls
      recorded in **ADR-022** — apply whole (ignore `duration`, the kernel smooths with `sp_port`),
      keep `notifyMainThread` (the eight dependent parameters are *quantized*, and that is the only
      channel saying which value took effect), and bounds-check the host-supplied address.
      `arpRate`/`tempoSyncToArpRate` now declare their four dependents. 7 new tests, `auval` clean
- [x] **P4-4** `fullState` save/restore + all 695 factory presets + user presets. The parameter
      tree already carried the 48 sequencer values; the **tuning table** did not, and
      `allocateRenderResources` was silently resetting it to 12-ET — found by comparing rendered
      audio rather than dictionaries. ADR-024
- [x] **P4-5** Host tempo drives `arpRate` — settled by upstream's *own* Ableton Link listener,
      which did exactly that. Transport stop releases voices and rewinds the sequencer. Fixed the
      message-queue lifetime crash along the way, and found that `S1Sequencer::reset` never
      rewound and `S1DSPKernel::reset` clicks rather than releases. ADR-025
- [x] **P4-6** The plugin draws the real interface and is fully automatable. `Conductor.synth` is
      `S1SynthControlling`; `startHosted(audioUnit:)` builds no graph; the extension hosts the 12
      panels; and control moves go **through the `AUParameterTree`** so a host records them, with
      an observer token so host moves reach the controls without echoing back. Host tempo now
      reaches the tempo control too, and the waveform display is fed from the render block
      (ADR-028). **Left for the owner:** the visual sign-off inside a host and
      the ADR-020 preset route
- [ ] P4-7 ⚑ Host validation matrix

### Phase 5 — Packaging
- [ ] P5-1 Entitlements, shared container, hardened runtime
- [–] P5-2 Signing + notarization — deferred, local-only for now (ADR-005). **Needed before public
      downloads are usable:** Gatekeeper rejects the ad-hoc build (measured 2026-09-09)
- [–] P5-3 Installer — deferred (ADR-005)
- [x] **P5-4** Licensing, attribution, naming — **Arcade Ruins**; `LICENSE`, `NOTICE.md`,
      `README.md`; AU subtype `ruin`; wordmark and icon replaced and generated from code. ADR-029
- [ ] P5-5 Localization pass (8 languages) — the About panel has been English-only since P5-4
- [ ] P5-6 Accessibility pass

### Phase 6 — The desktop layout (ADR-045) — **COMPLETE** 2026-09-13, on `desktop-ui`
- [x] **P6-0** Tag `v0.1.0-classic-ui`, branch `desktop-ui`, 0.2.0 (2), `S1Layout`, View ▸ Classic
      Layout, window sizing per layout, tests pinned to classic
- [x] **P6-1** Shell and four rows over the classic `Manager`; presets and tunings as sheets; rendered
      from the running app 2026-09-12
- [x] **P6-2** Readouts, formats, filter picker, LFO chips and pickers in the desktop style
- [x] **P6-3** Sequencer faders, step controls, switch, direction, steppers and tempo in the desktop style
- [x] **P6-4** Minimum = design size, fluid above it, always Dark, constraint noise gone
- [x] **P6-5** The plugin's view: full layout at 1440×900, overlays for sheets, scope, Dark — owner to confirm in Logic
- [x] **P6-6** The preset sidebar: the classic browser re-homed, collapsible, ⌘F search — *superseded by P8-0: the same column now drops down from the toolbar*
- [x] **P6-7** About, editors and Search as centred cards; Settings and Wheels popovers as they were
- [x] P6-8 Screenshots, README, release notes for 0.2.0 (2026-09-13)

### Phase 7 — Skins (ADR-046) — **COMPLETE** 2026-09-13, version 0.3.0
- [x] **P7-0** `S1Skin` / `S1Palette` / `S1SkinChoice`; View ▸ Skin ▸ Studio | Arcade (next launch); theme reads the palette
- [x] **P7-1** Arcade's controls: neon palette, glow ×2.2, orange section glow over grunge, cyan readouts
- [x] **P7-2** Arcade's art in code: header sunset/grid, browser starfield, neon wordmark, CRT frames
- [x] **P7-3** `SkinTests` (6), renders of both skins, README, release notes, installed

### Phase 8 — Layout revisions at the owner's direction ← current, on `desktop-ui`
- [x] **P8-0** The preset browser drops down from the toolbar's preset name; sidebar gone; rows re-spaced for
      the full width; Find menu removed (ADR-047). Follow-up: the preset row's rename/duplicate/share buttons
      had been clipped since P6-6 — `PresetCell` lays them out from the trailing edge
- [x] **P8-1** LFO & Mod Targets as two columns; effects 48 / envelope 46 / cutoff 68 / Mix and Glide 52 knobs;
      OSC 2's knobs each take half the section
- [ ] **P8-n** Whatever the owner asks next. Seen in the renders, not yet raised: the sequencer's faders have
      84 points of travel at 900 tall (100 before P8-0); `MorphSelector` is classic-drawn; Voice is mostly empty


### Cross-platform plugin (PORT_PLAN.md §6) — X0, X1 and X2 complete, X3 under way
- [x] **X0-1** JUCE 9, Starter licence (ADR-054) · **X0-2** Catalyst products kept through X2 (ADR-055) ·
      **X0-5** desktop layout only for 1.0 (ADR-056) · **X0-3** repo shape (ADR-057) · **X0-4** identity `BP03`/`Ruin` (ADR-058)
- [x] **X1-1** CMake build of Soundpipe + `s1engine`, behaviour tests, Apple-header guard, 3-OS CI green (ADR-065)
- [x] **X1-2** `S1HeldNotes` and `S1KernelListener` replace the NSMutableArray/AEArray/AEMessageQueue plumbing;
      74 tests green, 20/20 goldens bit-exact, installed, `auval` passed (ADR-066)
- [x] **X1-3** The kernel is plain C++ in `Sources/S1Engine`, compiled by Xcode and CMake; `S1EngineTypes.h`,
      `S1KernelBase.hpp`, `S1KernelAUAdapter`, `processWithEvents(S1Event[])`; green on Clang/GCC/MSVC; 94 Xcode tests,
      20/20 goldens bit-exact, installed, `auval` passed (ADR-067)
- [x] **X1-4** `S1TuningTable`, `S1Scala`, generated `S1FactoryTunings.cpp`; 194/194 tables bit-exact against the
      Swift fixture on 3 OSes; Swift check-mode test guards the generated files (ADR-068)
- [x] **X1-5** `s1::Preset` transcribed from the Swift; nlohmann/json vendored; 695/695 factory presets decode and apply
      bit-exact against the Swift fixture on 3 OSes; `abs(float)` → `std::fabs` in S1Rate.hpp (ADR-069)
- [x] **X1-6** `s1::Wavetables`; 52/52 tables bit-exact on three OSes; the kernel frees what it allocates (79.6 MB → 0 under `leaks`) (ADR-070)
- [x] **X1-7** Golden harness: 20/20 bit-exact on Apple Silicon, 20/20 within −50 dB (measured −63 dB) on Linux and Windows; `-ffp-contract=on`; `prepareToRender`; sanitizer job (ADR-071)
- [x] **X1-8 / X1 gate** The Mac app and AUv3 run on the engine (since X1-3; `prepareToRender` since X1-7); 336 tests, goldens exact in
      both harnesses, `auval` passed; owner tried the installed build, 2026-09-18: "We're good so far."
- [x] **X2-1** JUCE 9.0.2 by FetchContent (pinned commit, `S1_BUILD_PLUGIN`), `Sources/S1Plugin/`, VST3 + Standalone on three OSes; `PluginRenderTests`: processBlock = the bare engine,
      sample for sample, 12/12 on 3 OSes; found the engine's block-cut dependence (release-tail ends) for the X2 gate (ADR-072)
- [x] **X2-2** 150 parameters: IDs generated from `S1Parameter.h` and frozen by a fixture, ranges from the kernel, values in as events, the engine-driven rates
      reported back as VST3 output changes; `PORT FIX`: `prepareToRender` carries what parameters were set to (ADR-073)
- [x] **X2-3** Measured: upstream's render depends on the host's buffer size (arpeggios; 16/20 within tolerance at 64 frames). The plugin frees released voices every frame
      (kernel option, off for the Mac products): same samples at every block size on all twenty presets; ramps = the engine's smoothing; 48/96 kHz exact vs the engine (ADR-074)
- [x] **X2-4** Host MIDI through `S1HostMIDI`; mod wheel on the render thread; the router = the standalone's notes for 1,237 events on three OSes, from a Swift-written fixture (ADR-075)
- [x] **X2-5** State as JSON text: parameters by ID, the engine's preset (Mac-readable), tuning table, router settings; off-thread build, on-thread delivery; v1 fixture read on three OSes (ADR-076)
- [x] **X2-6** Host tempo and transport from the play head into the kernel's own handlers; the host's tempo wins (the tempo parameter is reported, not obeyed); 124.999 ms per sixteenth at 120 BPM from the output;
      `PORT FIX`es in the stop handler, the Mac AUv3's too: a stop is an all-notes-off, and the first note after a stop is no longer silent on sounds without sustain (ADR-077)
- [x] **X2-7** Denormal protection: every render call flushes subnormals to zero (the Mac render block too); measured on x86 in CI — unprotected silence 1.15–1.8× per block, protected tail ≤ 1.01× the sounding part; goldens bit-exact under it (ADR-078)
- [x] **X2-8** Validation: pluginval strictness 10 + Steinberg's validator (537/537 after naming the host's program) on macOS and Linux; the RealtimeSanitizer found and fixed two upstream allocations on the audio thread (voices made in the first render call; a list node per arpeggio note); **no CI any more — three scripts (macOS, Linux in Docker, Windows on the owner's machine), all three green on `9cb5531`** (ADR-079)
- [x] **X2-9** The preset library: factory banks linked in (the Mac app's files), user banks in a per-user folder, 695 host programs = the AUv3's, presets as recordable edits; the plugin starts with the SHIPPED Init; `PORT FIX`: compressors re-made at the prepared sample rate (2.2× too fast at 96 kHz, the AUv3's too); Windows verified by the owner at `a57f59b` (ADR-080)
- [x] **X2-10** The standalone: JUCE's holder with our application object (every MIDI input open by itself, settings beside the banks), checked live on the Mac and through JUCE's player across device changes; `PORT FIX`: a re-prepared engine clears the router's keys; Windows verified by the owner (script + hands-on); **the Mac hands-on check is the owner's** (ADR-081)
- [x] **X3-1** The layout specification: `Sources/S1Plugin/Layout/layout-spec.json` generated from the Mac desktop layout by a Swift test (frames, 125 bindings, fonts, both palettes, Cabinet's table), `s1plugin::LayoutSpec`, held to the running app — 144/144 frames per skin at 0.00 points; 26 parameters have no control (ADR-083)
- [x] **X3-2** The controls kit: `Sources/S1Plugin/UI/` — the Mac drawing on `juce::Graphics` function for function, a component per kind editing its host parameter by gesture, reset / wheel / keys / Alt-fine / focus / accessibility in the base class, 125/125 controls and 4/4 displays per skin built and painted at 1× and 2× with no window; matches the Mac render side by side (ADR-084)
- [x] **X3-3** The editor: `S1PluginEditor` — both skins from the specification and the kit at 1440 × 900, the painting under Cabinet, Every parameter behind Settings (all 150 reachable), previous / next, Panic, Mono, Snap, the scope, the playing step, the host-owned tempo; dependent knobs by note value; measured against the Mac on the same preset (Studio 3.3, Cabinet 5.9 of 255 over the window). **The owner's parity sign-off is open** (ADR-085)
- [ ] ← next: **X3-4** the preset browser. (Below: the X2 gate's record.)
- [x] the owner's: **X2 gate** goldens at 44.1/48/96 kHz and odd block sizes on all three OSes — block sizes and rates answered by ADR-074; **owner's questions there: the same option for the Mac products (12 goldens rewritten)? and: tempo-synced values keep their note value across tempo changes (ADR-077)?**

---

## Decisions settled

- **Repo** → `~/Developer/SynthOne`, remote on GitHub under `badpackets303`. R-7 closed.
- **Apple Developer account** → not needed; local-only distribution. ADR-005.
- **Manufacturer code** → `BP03`. Was a placeholder; since P5-4 it is part of the permanent AU identity.
- **Ableton Link** → dropped. ADR-004.
- **Product name** → **Arcade Ruins** (2026-09-09). ADR-029.
- **AU identity** → `aumu`/`ruin`/`BP03`. Permanent from here, because hosts store it in sessions.
- **Visual theme** → unchanged. The owner rejected a synthwave palette on the wordmark and kept the
  panels' orange-on-grey; only the wordmark and the icon changed.
- **DCO waveform selector** → works as designed, leave it (owner, 2026-09-09). See *Known issues*.
- **Velocity sensitivity** → always on, and not switchable, in the plugin and the standalone (owner,
  2026-09-10). ADR-032.
- **Favourite star** → grey when set, as upstream, not orange (owner, 2026-09-10). Starred presets are
  listed by the *Favorites* entry in the Presets panel's list.
- **Preset saving and Share in the plugin** → unchanged for now (owner, 2026-09-10). The owner is
  deciding whether to get a Developer account, whose App Group would give the plugin a writable
  shared folder.
- **Cross-platform plugin framework** → **JUCE 9 under the free Starter licence** (owner, 2026-09-16).
  ADR-054. The plan (phases X0–X4, acceptance criteria) is at
  <https://claude.ai/artifact/9zr5fP3KeuYMt5kvcmcaDH>; PORT_PLAN.md §6 summarises it. Nothing is built.
  X0-5 settled too (ADR-056). X0-3 and X0-4 are drafted as ADR-057 and ADR-058 (proposed, standing
  unless the owner objects); X0 is complete once the owner has glanced at them. Then X1-1.
- **Catalyst app and AUv3** → **kept through X1 and X2**; whether they ship at X4 is decided at the X3 gate
  (owner, 2026-09-16). ADR-055. Until then the JUCE build releases VST3 + standalone only, no AU, so the
  AU subtype question (`ruin` inherited or a new code) is not pre-empted.
- **JUCE build 1.0 scope** → desktop layout only (the classic iPad layout is not rebuilt for now — owner,
  2026-09-16); preset file export/import kept; MIDI learn deferred; Dev panel dropped. ADR-056.
- **Cross-platform repo shape** → one repository: `Sources/S1Engine/` (CMake `s1engine`, C++17, Soundpipe
  compiled in place), `Sources/S1Plugin/` (JUCE), JUCE via `FetchContent` by tag, XcodeGen untouched as the
  Xcode source of truth. ADR-057 (proposed).
- **JUCE build identity** → manufacturer `BP03`, plugin code `Ruin`, parameter ID = `S1Parameter` case name,
  standalone bundle `com.badpackets303.ArcadeRuinsStandalone`; the JUCE AU would be `Ruin`, a different plugin
  from the AUv3's `ruin`, so the X3-gate call is "second AU or not", never a drop-in. ADR-058 (proposed).

## Still open

- **App icon: on hold (owner, 2026-09-11).** The Mac app has **no icon at all**. The bundle has no
  Resources folder, no `Assets.car` and no icon keys, because ADR-029's generated icon went into
  SynthOneCore's iOS `AppIcon` set, which the app never reads. The owner offered a detailed artwork
  (`~/Desktop/Arcade-Ruins-Icon.png`), then judged it too detailed at icon sizes. What was found:
  - Xcode 26.6's `ictool`, inside Icon Composer.app, renders a `.icon` bundle exactly as macOS 26 draws
    it, so previews can be real.
  - A minimal `icon.json` is accepted: one group, one layer named `art.png`,
    `"supported-platforms": {"squares": ["macOS"]}`.
  - An image with its own rounded frame leaves black crescents in the bottom corners unless they are
    filled.
  - Nothing was added to the project.

- **Publishing** — two owner decisions; see *Next action*.
- **ADR-030 in Logic** — the mod wheel fix is installed and `auval` passes; the owner has not yet
  relaunched Logic and tried it. Knobs received the same echoes, so they are worth a look too.
- **Try ADR-033 in Logic.** It was installed 2026-09-10 18:49. The plugin's crash has only ever been
  seen inside Logic, so the editor needs opening there.
- **Owner's report, 2026-09-10 evening, from Logic.** Every crash was in the old `/Applications`
  build: the reports' `procPath` names it.
  - *Edit still crashes.* ADR-033 had not been installed. It is now.
  - *The star does nothing in the plugin.* `favoritePressed` saves the bank to
    `~/Library/Application Support/SynthOne`. The sandboxed plugin can only read that folder: its
    entitlement is `absolute-path.read-only` `/` (ADR-020). **Corrected by ADR-038:** that
    entitlement came from installing a build signed by `xcodebuild test`. The real plugin cannot
    read the folder at all. The save throws, and the list is redrawn
    only after a successful save. **In the standalone it works:** checked under lldb, the star fills
    (`ak_favfilled`) and `BankA.json` gains `isFavorite`. The file was restored byte-identical. By
    the same code path, **rename, duplicate, reorder and Save also fail silently in the plugin.**
    Upstream's design: the star toggles a flag and fills **grey**, the preset stays in its bank, and
    it is listed under the *Favorites* category. It is not moved to User.
  - *Share crashes the plugin.* `UIActivityViewController` throws inside UIKit's Mac share-sheet
    bridge (`UINSShareSheetController` → `_sceneViewRectFromUIWindowRect`) when presented from the
    extension. The standalone presents it without error.
  - **The owner's decision, 2026-09-10: no changes to preset saving or Share for now.** They are
    deciding whether to get a Developer account, whose App Group would give the plugin a writable
    shared folder. The star stays grey, as upstream.
  - Driving the extension under lldb in a scratch AU host found no `UIWindow`s, so that route is not
    working yet.
- **The editors' name fields in Dark appearance are fixed (ADR-034) but not installed.** Install
  when the owner says so, then open the preset editor in Logic in Dark appearance.
- **Three things look wrong only in Light appearance** (ADR-034, seen with a window override, not the
  system setting): the preset editor's category rows turn white, the chosen bank's highlight turns
  pale with pale text, and `SynthButton` titles draw dark on the dark buttons. All three are as
  designed in Dark. Offered as a separate task.
- **A host selecting a user preset crashes the plugin.** It happened in the field twice, in
  `SynthOneAU-2026-09-08-222323.ips` and `ArcadeRuinsAU-2026-09-09-215217.ips`, each about 1 s after
  launch. That looks like a host restoring a saved selection, which is not confirmed. The stack is
  `-[S1AudioUnit setCurrentPreset:]` → `presetStateFor:`, throwing on the XPC thread.
  **Reproduced 2026-09-10 without Logic** by a scratch host loading the installed plugin out of
  process:
  - a factory preset was fine;
  - user preset −1 named "Missing Preset", with no file behind it, was ignored;
  - **user preset −2 with an empty name killed the extension** with the identical stack.

  `setCurrentPreset:` is unchanged in HEAD. Offered as a separate task with the reproduction.
- **Owner's visual sign-off** on the Mac idiom, on the header after the chrome fix, and on the preset
  editor's bank list (ADR-033), which is now a table where the picker was.
- **ADR-020's preset route** is untested inside the extension.
- **The About panel is English-only** until P5-5 (seven stale translations were deleted at P5-4).
- **`SpikeAU.app`**, the P0 spike's plugin: if it is still in `/Applications`, delete it. The
  confirmation it existed for was overtaken by the real plugin drawing in Logic.

## Blockers

- None.

## Known issues

### ✅ Fixed, not installed: the editors' name fields were unreadable in Dark appearance (ADR-034)

Found 2026-09-10 while verifying ADR-033. In Dark, both editors' name fields drew white text on their
fixed `#F8F8F8` background: a contrast of 1.05, and not one glyph pixel differed from an empty field.
Both fields are now pinned to Light, the appearance Interface Builder draws them in. On the fixed
build, opened from a preset cell's Edit and from a bank's Edit, they measure 14.3 in Dark and in
Light, including while being edited.

**The rest of the interface is only right in Dark.** With the window overridden to Light, the
editor's category rows turn white, the bank highlight turns pale, and `SynthButton` titles go dark
on dark. That is why the fix pins two fields rather than the app. See *Still open*.

**The easier way to measure the running app without a mouse:** inject
`Scripts/debug/appearance_walker.m` with `open -g --env DYLD_INSERT_LIBRARIES=…`. Its header has the
commands. It needs no lldb, and it drives the click paths from compiled Objective-C.
- **Copy `settings.json` and `tunings_v1.json` first.** Every launch rewrites them.
- **Restore them only if nothing else has launched the app since.** On 2026-09-10 another session
  launched it between two walks, and restoring the pre-session copy overwrote that launch's version.

### ✅ Fixed and installed: opening the preset editor crashed the app and the plugin (ADR-033)

Found in the extension's crash reports: three crashes in Logic on 2026-09-10, two at 11:52 and one
at 14:53. `UIPickerView` throws as soon as it enters a window under Optimize Interface for Mac, and
the editor's bank picker was one. The crash was reproduced in the standalone by driving the real click
path under lldb. The picker is now a table in the same frame, showing the same rows.

**A sweep of the running app found nothing else.** Every storyboard scene was loaded into the
Mac-idiom window, and only this one threw. `MacIdiomControlTests` repeats the walk in the test bundle,
using UIKit's own record of restricted classes.

**Driving the standalone from lldb without a mouse:**
- Use Objective-C expressions. Swift expressions have no module context in a stopped `mach_msg`
  frame.
- Never call a variadic method.
- Give every local a unique prefix, because short names collide with loaded symbols.
- Dismiss the launch pop-up first, or every presentation is refused.

### ✅ Fixed: the plugin's mod wheel would not stay where it was dragged (ADR-030)

Owner-reported 2026-09-10 in Logic: "jittery and doesn't remain at the position it's dragged to"; on
release it drifts back.

**Two bugs, stacked**, found with a debugger attached to the extension running inside Logic:
1. **Out of process, every parameter write the interface makes comes back from the host** without
   our originator token, so `observeHostChanges` reported it as a host move — 574 times in a
   two-minute drag. `S1HostedSynth.echoWindow` now treats a host report within 0.5 s of our own
   write as an echo, and reconciles against the DSP once the control goes quiet. This reached
   **every** control, not just the wheel.
2. **Upstream's cutoff → wheel placement did not invert the wheel's own write**, so hearing its own
   value moved the wheel: dragged to the top, it was redrawn at 0.58. Now the exact inverse.

⚠️ **In-process tests cannot see (1).** `testOurOwnWritesAreNotEchoedBack` passed the whole time.
`HostEchoTests` simulates the echo by setting `AUParameter.value` with no originator, which is what
actually arrives.

**How the evidence was got — reuse it.** Debug builds of the extension carry `get-task-allow`, so
lldb can attach to `ArcadeRuinsAU` in a live Logic session without restarting anything. A Python
driver (`PYTHONPATH=$(lldb -P) xcrun python3 …`) with auto-continuing regex breakpoints, reading
arguments through `frame.GetValueForVariablePath`, recorded who moved the control and with what
value. Two traps: anchor closure regexes to the exact enclosing function (the first attempt also
matched the waveform's 30 Hz pull closure, and it buried everything), and the owner has to perform
the gesture *during* the capture — say when it starts, and allow a couple of minutes.

A third trap, 2026-09-10: **in async mode, never wait on an event to learn that the attached process
has stopped.** `AttachToProcessWithID` did not deliver one, and the plugin sat suspended in Logic for
four minutes. Poll `process.GetState()`, track `GetStopID()` so a stop is not handled twice, and
detach in `finally`. Test the driver on a throwaway process before attaching inside a host.

### ⏸ Declined by owner: the DCO waveform selector's highlight plate

**Owner, 2026-09-09: "I didn't realize it was a morph. It works as designed. No need to change
anything."** Do not fix this unasked. It is recorded here so the next session does not rediscover it.

`MorphSelector` is a **continuous** morph (0–1 across four wavetables), so dragging between icons is
the design. The owner first reported the plate as clunky and not sitting on the icon. Three upstream
defects are real, and all three are still in the code:

1. PaintCode generated `MorphSelectorStyleKit` for 240×53. It emitted the plate with absolute numbers
   (`width: 39, height: 36, y: 7`), while every icon path is frame-relative. The real selectors are
   214×52 and 194×52; on DCO 2 the plate is about 24% oversized, and at full value it reaches x≈196.6
   in a 194pt view.
2. Touches set `value = x / width`, but the plate is drawn at `value × 0.79 + 0.104` of the width.
   The two agree only mid-control, so clicking the sawtooth draws the plate about 15pt to its left.
3. `touchesBegan` guards on `if touch != touches.first`, so a single click sets nothing; only
   `touchesMoved` moves the morph.

A fix was written and tested at both real widths, then **reverted at the owner's request** —
nothing was committed. If it is ever wanted:
- express the plate as fractions (39/240, 36/53, 7/53 — identical at PaintCode's own size);
- route touches through the inverse of the plate mapping;
- handle `touches.first` in `touchesBegan`;
- extract `setValue(atX:)` so it can be tested the way `Knob` exposes `setPercentagesWithTouchPoint`.

### ⚠️ `/Applications/SynthOne.app` still registers the pre-rename plugin

Installed before P5-4, it still registers `aumu`/`aks1`/`BP03`, so a host lists both it and Arcade
Ruins. `Scripts/validate-au.sh` only replaces `ArcadeRuins.app`. The owner needs to delete it
(`rm -rf /Applications/SynthOne.app`) and relaunch the host.

### ⚠️ A running host holds the previous build — and a stale plugin sounds like silence

**Not a bug in the product, and it cost a session.** macOS registers the AUv3 from the app in
`/Applications`, but a host that is already open does not rescan. On 2026-09-09 the extension
crashed on load (the `Tunings.loadTunings` subscript, since fixed); Logic had it loaded, stayed
open through five reinstalls, and reported no audio. Nothing in Logic says "the plugin you have
loaded is stale" — it is simply quiet.

`Scripts/validate-au.sh` now warns when Logic, GarageBand, Live, Reaper or Bitwig is running.
**Quit and relaunch the host after every install.**

Diagnosing it needed instrumentation rather than reasoning, and the technique is worth keeping:
`os_log_create("com.badpackets303.SynthOne", "diag")` in the render block, read afterwards with

```bash
/usr/bin/log show --last 10m --info --debug --predicate 'eventMessage CONTAINS "S1DIAG"'
```

`NSLog` from the extension did **not** show up in that query; `os_log` with an explicit subsystem
did. The probe is removed — it is not real-time safe — but that is how to get evidence out of a
plugin running inside a host.


### ✅ Fixed: three separate casualties of the Mac idiom (ADR-023)

All reported by the owner within a day of adopting *Optimize Interface for Mac*, all with the same
root cause and none of them visible to a unit test — the test bundle reports `.pad`, so only the app
and the plugin ever see `.mac`.

1. **Every `UIButton` was dead.** Six control classes handled input by overriding `touchesBegan`,
   which UIKit never calls when the button is backed by an AppKit cell. Fixed with `.touchUpInside`
   actions. ADR-026.
2. **Every iPad *layout* path was skipped.** `Conductor.device` was the running idiom, and 37 checks
   ask it "iPad or iPhone?" — under `.mac` they matched neither, so the second panel was never
   installed and the Tunings panel's metrics were wrong. `device` is `.pad` by construction now.
   Restoring those paths exposed an out-of-range subscript in `Tunings.loadTunings` that stopped the
   **extension loading at all**.
3. **Buttons were painted with the system accent.** UIKit resolved them to the Mac behavioural
   style, filling a selected button blue over its own dark background and leaving the design's pale
   title unreadable — the owner saw it on `Mono`. Every button now sets
   `preferredBehavioralStyle = .pad`. Measured on a running build: the default resolves to `.mac`.

⚠️ **The idiom change was a one-line build setting with a very long tail.** If anything else looks
wrong in the interface, ask first whether it is UIKit's Mac styling rather than our code.


### ✅ Fixed: every `UIButton` in the interface was dead under the Mac idiom

Owner-reported as "`Hide` does nothing", then "neither does `Wheels`". **Six control classes** were
affected, not two: `SynthButton`, `MIDISynthButton`, `CallbackButton`, `FilterTypeButton`,
`PresetUIButton` and `HeaderNavButton` — so the filter-type selector, the preset list buttons and
the header navigation were dead too, and had not been tried yet.

All of them handled input by overriding `touchesBegan`. Under *Optimize Interface for Mac*
(ADR-023, adopted the day before) UIKit backs `UIButton` with an AppKit cell and never calls it.
Every working control — knobs, the Octave stepper, the toggles — is a `UIView` subclass, and that
correlation was the whole diagnosis. Fixed with `.touchUpInside` actions, which both idioms deliver.
A test now greps for the pattern so it cannot come back. ADR-026.

⚠️ **If anything else in the interface seems unresponsive, check whether it is a `UIButton`
subclass first.** Two sessions were spent on `Hide` inspecting the button, the storyboard, the
constraint and the layout engine — all of which were working.


### ✅ Fixed: a queued main-thread message outliving its audio unit

Found at P4-4, deferred, and fixed at P4-5 after it took the test runner down a second time.

`AEMessageQueuePerformSelectorOnMainThread` stores its target as a **raw pointer** in a lock-free
ring buffer — retaining on the render thread is not real-time safe — and delivery is a later
`dispatch_async`. A unit destroyed in between left the handler doing `objc_retain` on freed memory.

**Fix:** the render thread addresses an `S1MessageRelay` that holds a *weak* reference to the unit
and is deliberately never deallocated. A late message finds `nil` and does nothing. ADR-025.

**The lesson, worth more than the fix:** the first regression test generated a backlog, dropped the
unit without draining, and ran the main queue — and **passed against the unfixed code**, because the
freed memory had not been reused yet. A use-after-free is not deterministic, and a test that only
sometimes reproduces is worse than one that states what it actually verifies. The shipped tests
check the mechanism: the relay outlives its unit, its reference is weak, every posted selector
no-ops on a gone unit, and messages still arrive while the unit is alive.

### ✅ Resolved: the `Octave:` stepper is now one global octave

**Closed 2026-09-09 by the owner's own observation:** the stepper *does* work — it moves what the
on-screen keys and the typing keyboard play — and it does **not** affect notes arriving from a
hardware MIDI keyboard. That is upstream behaviour, and it is arguably correct: `Octave:` is the
on-screen keyboard's octave, and a hardware keyboard has its own octave buttons and sends its own
note numbers.

Verified in the code rather than assumed:
- `Manager+callbacks.swift:22` — the stepper's only effect is `keyboardView.firstOctave = value + 2`.
- `Manager+MIDIListener.swift` — `receivedMIDINoteOn` passes `noteNumber` straight to
  `keyboardView.pressAdded(noteNumber:velocity:)`. No offset is applied anywhere on that path.

**The three ranked hypotheses that used to be here were all wrong**, and worth remembering as a
lesson: the leading one blamed `Stepper`'s hard-coded hit rects in a 109×37 design space against a
108×35 frame. The geometry *is* mismatched and it is *not* what anyone was seeing. Two sessions of
analysis were spent on a bug whose actual shape one sentence from the owner settled — "it works on
the virtual keyboard, not on MIDI" was the missing observation, not more code reading. The same
shape as ADR-015, where a 72-second launch was a consent dialog.

**Resolved by the owner 2026-09-09: `Octave:` is now one global octave.** Move it up one and the
on-screen keys relabel C2 to C3 *and* a MIDI keyboard's C2 plays C3. `midiOctaveShift` is derived
from `typedOctave`, so the three input paths cannot drift apart.

Two things that make this more than an addition:
- **A note-off releases the note its note-on started**, via a map of incoming note -> sounding note.
  Without it, nudging the octave with a key held leaves the note sounding forever.
- **Notes shifted past 127 are dropped, not clamped.** Clamping piles several keys onto note 127,
  and `notesFromMIDI` is a *set*, so releasing one would silence the rest — a stuck note traded for
  a vanishing one.

Deliberately **not** routed through the DSP's `transpose` parameter, which was the obvious
alternative: it applies on top of the on-screen keyboard's own shift, so one octave step would move
the virtual keys by two — and `transpose` is a preset field, so presets and the stepper would fight.

✅ **The plugin too, since ADR-031.** Host MIDI goes through `S1HostMIDI`, which applies the same
octave shift and note-off pairing on the render thread. `HostMIDIParityTests` holds the two to the
same behaviour.

## Host validation matrix (filled in at P4-7)

| Host | Instantiate | Audio | UI | Automation | State | Multi-instance | Offline bounce |
|------|---|---|---|---|---|---|---|
| auval | | | — | | | | |
| Logic Pro | | | | | | | |
| Ableton Live | | | | | | | |
| GarageBand | | | | | | | |
| Reaper | | | | | | | |
| Bitwig | | | | | | | |

---

## Session log

### 2026-09-14 (last) — P7-8: classic by default, and an app icon at last (ADR-052)
- **Owner:** "Can we make the default layout the classic one. And then let's assign this icon to
  it for MacOS", with a synthwave keyboard PNG (now `Scripts/branding/source/Arcade-Ruins-Icon.png`).
- **`bool(forKey:)` cannot tell absent from `NO`.** Flipping the default meant reading
  `object(forKey:)` first; otherwise an owner who had deliberately chosen the desktop layout would
  have been moved back to classic.
- **The icon lesson is worth keeping: check what macOS draws, not what you shipped.** The first
  pass was a mac-idiom icon set — correct by every catalog rule, built, installed, `.icns` in
  Resources, both plist keys set. `NSWorkspace.icon(forFile:)` on the installed app showed it
  composited inside macOS 26's shape on a light plate, a rounded square inside a rounded square.
  An `.icon` bundle whose layer is the body full-bleed is what fills the icon. The measurement is
  a dozen lines of Swift against the installed app; it settled in one run what no amount of
  reading would have.
- An incremental build left the previous pass's `AppIcon.icns` in the bundle. Harmless — the plist
  names the other one — but **release builds should be clean**.
- **Then the owner saw the second half of the same lesson.** The icon "fades to white in the lower
  half": macOS 26 lights layers like glass, which suits the flat, layered artwork Icon Composer is
  built around and ruins a finished dark illustration. `specular` and `translucency` off on the
  group fixed it. The schema is not documented on this machine — `strings` on
  `IconComposerFoundation` listed the keys (`fill`, `specular`, `translucency`, `shadow`,
  `blur-material`, and `fill` being one of `automatic`, `linear-gradient`, `automatic-gradient`).

### 2026-09-14 (earlier) — P7-7: the Arcade skin is dropped (ADR-051)
- **Owner:** "Remove the 'Arcade' skin as an option." Deleted rather than hidden: nothing has been
  released with it, two skins of the same genre with one superseded is a worse menu than one, and
  the code is a `git show bf8a08a` away.
- **What stayed is the interesting part.** `S1ArcadeArt` was never Arcade's in anything but name —
  Neon Ruins draws its sun, mountains, grid, starfield, joystick, scanlines and CRT frames with it.
  Renamed `S1SynthwaveArt`; only the Arcade-specific palette, header art, browser art, drawn
  wordmark and grunge tile went.
- No migration needed: `S1SkinChoice.chosen` has always fallen back to Studio for an unknown value,
  so an owner whose default still says `arcade` opens Studio. A test holds that.

### 2026-09-14 (later still) — P7-6: the layout is chosen in Settings; tests stop writing the owner's settings (ADR-050)
- **Owner:** "I would still like to access the original iPad-based interface by changing the
  setting. Can we include that in the release?" They are running the classic layout (their own
  setting), where P7-5's skin picker was not present at all — the desktop layout installed it.
- **The install point moved into the ported Settings controller** (one line, PORT comment). That is
  the whole fix: the pickers now exist in both layouts and both products, so Classic is never a
  one-way trip in a host.
- **The classic render caught a collision the desktop one could not:** with the skins caveat as a
  second note line, the block grew upward into the scene's "On older iPads…" paragraph. The caveat
  moved into the skin row's title (`SKIN · DESKTOP ONLY`), which keeps the block one line tall.
  **Render every layout a shared screen appears in**, not just the one being worked on.
- **The test bundle had started writing the owner's real settings.** Yesterday's suspicion was
  wrong for the suites as they stood; P7-5's new tests made it true — `S1Layout.setCurrent` and
  `S1SkinChoice.choose` write `UserDefaults.standard`, and in the test host that is the app's own
  domain. Both now read and write `S1Preferences.store`, which `TestStorageIsolation` points at a
  scratch suite and removes at the end. Checked by exporting the owner's domain before a 58-test
  run and comparing after. ADR-036 covered `Disk` only; this is the same hazard one layer over.

### 2026-09-14 (later) — P7-5: the skin is chosen in Settings (ADR-049)
- **Owner:** "Can we allow skin selection through the Settings menu within the app? Going through
  Terminal is not a feasible option." Right: the plugin has no menu bar, so in Logic the terminal
  was the only way, with a different domain from the app's.
- The picker rides in the Settings popover, added by `dressPresented` — the settings segue reached
  it already and returned nil. No ported file changed. The scene's 600×382 is set by the ported
  `prepare(for:)` *after* `dressPresented` runs, so the picker fits the empty right column rather
  than growing the popover.
- **A mistake worth remembering: I deleted two of the owner's preference values on a hunch.** The
  settings render came up classic at 1024×800, `defaults read` showed `S1ClassicLayout = 1` and
  `S1Skin = neonRuins`, and I assumed the test bundle had written them (ADR-036's fault pattern) and
  deleted both. Then I proved the suites write nothing: cleared the keys, ran `SkinTests` alone and
  all three suites, and the domain stayed empty. So the values were the **owner's own**, restored
  exactly (`S1ClassicLayout` YES, `S1Skin` neonRuins). **Check before deleting, not after**, and
  render with launch arguments (`RENDER_ARGS="-S1Skin neonRuins -S1ClassicLayout NO"`), which is
  what they are for — the driver never needs the owner's defaults.
- **The owner is set to the classic layout** (their own setting, predating this work). Worth asking:
  everything in Phases 6–8 is the desktop layout, which they will not see until View ▸ Classic
  Layout is unchecked.

### 2026-09-14 — P7-4: the Neon Ruins skin, one neon per section (ADR-048)
- **Owner:** the app "has no character … every AI generated synth looks pretty much like this";
  showed ChatGPT's one-shot synthwave mock and asked for it approximated on the design canvas as a
  new skin. Four rounds on the canvas: "still lifeless and muted … keep the original brand label
  graphic" → hotter glows, near-black panels, the artwork; "the rust is too warm and seems more like
  a glow reflection rather than texture" → neutral worn metal; "the orange is making the UI too
  monotonous and overpowering — mix it up with other neon colors for different panels" → one neon
  per section; "Build this as the third skin in the app. Make the Mix panel match the green of the
  Delay panel."
- **How a per-section accent reaches a ported control without rebinding anything:** the section
  holds it, `UIView.s1Accent` walks up to the nearest section, and every `S1DesktopStyle` drawing
  takes it as an argument — a required one, so the compiler found all eleven call sites. Studio and
  Arcade name no section accent, so they fall through to the palette's; Studio's render is
  byte-identical to yesterday's, which settles that the plumbing changed nothing for them.
- **Two controls are dressed before they are placed** (the filter picker, the step-number boxes):
  their accent is unknown at dress time, so they re-apply their colours on `didMoveToWindow`.
- **The owner's artwork is ~14:1 once its noise is trimmed.** The canvas's 150×46 wordmark frame
  would have shown 10-point letters; the skin asks for 220×24 instead (the one layout number a skin
  may set, `S1SkinDress.wordmarkSize`), and the header art's sun and palm moved to the gaps that
  leaves.
- **Test trap:** `XCTAssertEqual(UIColor.black.mixed(with: .white, 0), .black)` fails — a mix is
  always in the extended sRGB space, `.black` is grey-space. Compare components.
- The envelope plots' colours are the storyboard's (`AKADSRView`'s IBInspectables), so the row
  builder hands them the section's accent; which envelope has a fill stays the storyboard's word.
- Not built: the canvas's "PLAY · CREATE · DESTROY · REPEAT" marquee in the preset browser — it
  would be a new view in the browser's column, a layout change for the owner to ask for.

### 2026-09-13 (evening) — P8-0: the preset browser drops down; the sidebar is gone
- **Owner:** "I changed my mind about the preset panel. Let's have it as a drop-down when a user
  clicks on the preset name at the top of the window. Get rid of the side panel. That will give us
  more wiggle room to readjust some of the panel sections that still need work."
- Done as ADR-047: the same column in a 380×720 card under the preset name (a root subview, not a
  presentation — the browser's own editors and Search still present from it, and the plugin needs no
  window). Chevron on the name, ⌥⌘P, View ▸ Preset Browser; click outside, Escape or a card closes it.
- Rows re-spaced for the full width; rows one and two 158/220 tall — the first pass at 150/212 clipped
  the Semitones readouts and LFO 2's Amount; the LFO section had been at its limit since P6-2 (that
  was the "1/4 triplet" / "100%" overlap in every render).
- Find menu removed: ⌘F is Search Presets, and the `_UIMenuBuilderError` at launch is gone.
- Tests: `sendActions(for:)` does nothing in the test host (no `UIApplication`); the drop-down test
  invokes the `S1ActionButton` closures directly.
- **Owner:** "Where did the preset editor go?" — the row buttons had been clipped since P6-6 (only
  the star showed in every sidebar render, unnoticed). Fixed in `PresetCell` for the desktop dress.
- **P8-1 (owner):** LFO section "clunky and haphazard", knobs could be bigger, OSC 2 knobs scrunched.
  Two-column LFO section, knobs 48/46/68/52, OSC 2 `fillEqually`. Rows stay 158/220/122.

### 2026-09-13 (later) — Phase 7: the Arcade skin, fully procedural
- **Owner:** "Finish P6-8 first, then do the skin fully procedural." Built P7-0…P7-3 in one pass
  (ADR-046): plumbing, palette, Arcade's controls and art, tests, docs, 0.3.0.
- Studio pixel-diffed against 0.2.0's screenshot after the palette refactor: one real difference (the
  wave picker's selected cell had been folded into the "lit" colours) — restored as `plateTop` /
  `plateBottom`; what remains is run state.
- **Trap found:** `xcodegen generate` rewrites `Sources/SynthOne/Info.plist` and the AU's from
  `info.properties`, with `1.0` / `1` for the version keys unless they are listed — the P6-8 hand edit
  was undone by the first generate. The keys are in `project.yml` now.
- Pre-existing: `_UIMenuBuilderError` at launch for ⌘F vs Find (P6-6). Left for the owner's list.

### 2026-09-13 — P6-8: release prep for 0.2.0; skins planned as Phase 7
- **The owner** showed a synthwave mock-up of the layout and asked for it as a skin; decided "finish
  P6-8 first, then do the skin fully procedural". Plan recorded under *Next action*.
- **Screenshots.** The render driver gained `RENDER_SELECT` (select table rows by label text) because
  the owner's library has replaced factory BankA with their own presets, whose names do not belong in
  a public README; the renders show the Brice Beasley bank's first preset. `standalone.png`,
  `presets-sidebar.png` (a crop), `standalone-compact.png` (1180×900, sidebar hidden);
  0.1.0's `standalone.png` renamed `classic-layout.png`; the P6 work renders removed.
- **A real bug from the compact render:** the Steps stepper drew as a horizontal smear after the
  sidebar hid in an 1180-wide window (the window was over-constrained for a moment, the stepper drew at
  a wrong width, and UIKit stretched that bitmap when the bounds came back). Every desktop dress now
  sets `contentMode = .redraw`; reproduced twice before, clean after.
- **Version strings.** Both `Info.plist`s hardcoded 1.0 / 1; they now read `$(MARKETING_VERSION)` and
  `$(CURRENT_PROJECT_VERSION)`. Built app and plugin report 0.2.0 (2).
- README rewritten for the desktop layout; `docs/release-notes.md` started. Tests 26/26 (desktop
  suites). Reinstalled with `validate-au.sh`; `auval` passed.
- **Noticed, not touched:** two `notarytool` processes from the 0.1.0 release attempt were still
  running after 38 hours — the owner's terminals.

### 2026-09-11 — About and the header trimmed; bonus presets in factory BankA (ADR-040)
- **The owner:** remove the About tagline and the "How Synth One was made" link. Asked what More does
  now, and to remove it if nothing.
- **What More does.** With `MailChimpAPIKey` stubbed, every click shows "Bonus presets have been added
  to BankA" and appends `Bonus.json` to BankA with no duplicate check. The owner's BankA already holds
  93 of the 94, and the plugin's addition lasts only the session. More is hidden, and factory BankA
  includes the bonus presets.
- **Caught by the full suite, not by the new test.** Deleting the Swift `videoButton` outlet left the
  unshipped iPhone About scene's connection dangling, and both storyboard sweeps threw. That scene's
  tagline, button and outlet are gone too.
- **269 → 271 tests.** The revert check failed exactly the three new or changed tests.
- **Installed 2026-09-11 08:53**, with ADR-039. The installed binaries and storyboards match the plain
  build, and in the scratch host the plugin loaded its presets at launch. Not yet seen by the owner.

### 2026-09-11 — One view, no Show/Hide (ADR-039)
- **The owner:** the hidden view should be the standard one, and the toggle should go, because Show
  "only elongates the virtual keyboard a bit".
- **ADR-037 reverted, not left as dead code.** Its files had been touched only by ADR-035 and
  ADR-037 since b7a9313, which `git log b7a9313..HEAD` per file confirmed. They were restored from
  there:
  - the container, `SceneDelegate`, the plugin's view controller and `SynthOneApp`;
  - the four `Manager` and panel files;
  - three test files.

  ADR-035's storyboard, shading, octaves and settings switch stay.
- **Two small `PORT (ADR-039)` changes.** `Manager.viewDidLoad` hides `keyboardToggle`.
  `AppSettings` no longer reads `showKeyboard`, so a saved "shown" cannot cover the lower panel.
- **269 tests green** (274 less ADR-037's five). The revert check failed exactly the two tests
  covering the changes. The plain build carries no test entitlements. Installed 2026-09-11 08:53,
  with ADR-040.
- **Open question for the owner:** the toolbar's right end is empty where the button was.

### 2026-09-10 — The plugin's empty presets panel and the ▶ crash (ADR-038)
- **The owner, from Logic:** "an empty panel when clicking on a preset". A new crash report,
  `ArcadeRuinsAU-2026-09-10-212840.ips`, whose binary UUIDs match the 21:25 install, died in
  `nextPreset()`, at `presetBank[0]`.
- **Evidence, in order:**
  - The plugin's `currentPreset.json` was last written at 21:03 and never after the 21:25 install, in
    Logic or in `Scripts/debug/auhost.swift`. So no banks had loaded.
  - lldb in the scratch host, inside the sandbox: `banks.json` exists, `isReadableFile` is NO, and
    reads return 0 bytes.
  - `codesign` on every plugin build on disk: only a build made by `xcodebuild test` has
    `absolute-path.read-only /`.
- **Why it had worked before.** Earlier installs shipped a test-signed `./DerivedData` product. At
  ADR-037 the tests moved to a scratch folder, so 21:25 was the first plain install. STATE's claim
  that the plugin reads the folder read-only is corrected where it appears.
- **Fixed:**
  - `Disk.exists` uses `isReadableFile`;
  - `nextPreset` and `previousPreset` guard an empty bank;
  - `validate-au.sh` refuses a test-signed plugin.
- **Two wrong guesses along the way:** "`xcodegen` dropped the entitlement" (the entitlement was never
  in the repo), and a test threshold of 100 BankA presets taken from the owner's file, which holds 135
  (the bundle ships 41). Both were caught by measuring.
- **271 → 274 tests.** Revert checks: `Disk` at HEAD fails both loading tests; the preset code at HEAD
  crashes the arrow test.
- **Installed 2026-09-11 08:30.** In the scratch host, the installed plugin loaded BankA and wrote its
  current preset at launch. Not yet seen in Logic.

### 2026-09-10 — Show and Hide resize the window (ADR-037, P3-6c)
- **The owner tried ADR-035 in Logic.** Show raised an "absolutely massive" keyboard over the lower
  panel. They wanted Show to show what Hide had shown, the keybed, and Hide to be much shorter.
- **Three choices were put to the owner**, and they picked:
  - the window shrinks rather than leaving 100 empty points;
  - Hide shows 88-point whole keys;
  - it opens hidden.
- **Built:**
  - `S1ScalingContainer` has two design sizes and `setKeyboardShown`. It requests the new size at the
    current scale and holds the scale 0.5 s so the interface doesn't zoom out and back.
  - `SceneDelegate` resizes with `requestGeometryUpdate(.Mac)`, keeping the top-left origin.
  - The plugin passes `preferredContentSize` to its host.
  - In `Manager`, the toggle stays at 636, and `keyboardCoversLowerPanel` (false) turns off upstream's
    covered-panel paths: VoiceOver, navigation, and the presets panel hiding the keyboard.
- **A navigation bug the change would have exposed.** With the keyboard shown, upstream let the top
  panel offer the panel below it, which would empty the lower panel. That is now tested.
- **Another session committed ADR-036 while this one worked**, in the same tree, so this record is
  ADR-037. A first renumbering silently did nothing, because zsh doesn't word-split `$FILES`; it was
  redone with the paths written out. The CLAUDE.md gotcha applies to `sed` as well as `-only-testing`.
- **271 tests green.** The revert check failed 4 of 27, each as expected. In the running standalone the
  window went from 800 to 900 points with its top edge fixed. **Not installed**, and not tried in Logic.

### 2026-09-10 — Session 39: the test bundle stays out of the owner's files (ADR-036, P3-3)
- **The task, from Session 38's finding:** a test run was overwriting the standalone's real
  `settings.json` and `tunings_v1.json`.
- **A second leak turned up.** `.caches` is `~/Library/Caches` itself in an unsandboxed process, and
  `~/Library/Caches/currentPreset.json` had the same 21:01:42 mtime as the owner's `settings.json`.
- **Fix:** `TestStorageIsolation` is the test bundle's `NSPrincipalClass`. XCTest creates it before any
  test class runs, and it points `Disk.sharedSupportURL` and the new `Disk.cachesURL` at
  `SynthOneTests-<UUID>/` under the temporary directory. The app's and the plugin's paths are
  unchanged. Rejected: detecting XCTest inside `Disk`, which would ship a test-only branch, and a shared
  `setUp`, which covers only the classes that call it.
- **`StorageIsolationTests`, four tests.** They drive the real writers: the keyboard toggle, the
  tunings save and a `.caches` save. Each asserts the file lands in the temporary folder and that the
  real files' size and mtime did not change.
- **Proof.** Before and after a full run, the md5 and mtime of `settings.json`, `tunings_v1.json` and
  `currentPreset.json` were identical, and so was a stat digest of the whole support folder. The run:
  266 tests, 0 failures. The temporary folder was removed afterwards.
- **The revert check was not run.** The plan pointed `Disk`'s defaults at a scratch folder first, so
  nothing real could be written, and then removed the redirect. The permission classifier refused that
  edit, and it was not worked around. The one experiment edit that had applied was reversed, and both
  files were byte-compared against their backups before the full run. *Next action* has the steps.
- **The owner's `settings.json` was not touched or restored.** It reads `firstRun` false, `launches`
  2, `keybedVersion` 1, and every MIDI-learn CC at 255.
- Not covered: `testRecordingsGoToAFindableFolder` still creates the real, empty `~/Music/Arcade Ruins`,
  because that folder is the path it tests.
- The owner had the plugin open during the session. It is sandboxed read-only on the support folder
  (ADR-020), and nothing it did changed the files. *(ADR-038: a plain build of the plugin cannot read
  that folder at all. The read access was a test-signed build's.)*

### 2026-09-10 — Session 38: the keybed (ADR-035, P3-6c)
- **The owner: the on-screen keyboard is "outrageously huge" on a big screen.** Measured: shown, it
  covers the whole lower panel with white keys of about 25 × 165 mm at full screen on a 27-inch
  display, larger than a grand piano's. Hide only moved the container, so 299 of the keyboard's 387
  points ran off the bottom of the window, and what showed was the black-key zone.
- **Mockups before code**, published as the "Arcade Ruins Keybed" artifact and drawn at the
  storyboard's geometry over the real render. A: fit the strip. B: a taller window. C: a shorter
  Show. The owner chose B, asked to see more white key below the black ones, compared +80, +100,
  +120 and +160, and chose **+100, 4 octaves, shaded**.
  - **The first mockup was wrong, and the owner saw it**: a duplicate toolbar in every frame.
    `sips -c` with `--cropOffset 0 0` crops around the centre, so the panel image included the real
    toolbar. They then said they had misread it; they hadn't. PIL crops correctly.
- **Built:**
  - a bottom constraint on the keyboard container, with autoresizing on the keys, wheels and labels;
  - `designSize` 1024×868;
  - hidden and 4 octaves by default, with `keybedVersion` for a one-time switch;
  - 1–5 octaves in the Keys popover;
  - shaded keys.

  The toggle's 337 and 636 are unchanged.
- **252 → 262 tests.** The revert check failed 8 of 10, each as expected. The first shown-state test
  failed with the layout correct: a window-less view needs `setNeedsLayout()` after a constraint
  change. CLAUDE.md has the gotcha.
- **Found: every full test run overwrites the standalone's real `settings.json` and
  `tunings_v1.json`.** A `PointerInputTests` test fires the keyboard toggle, which saves a fresh
  `AppSettings`. The owner's file was already test data, and now carries `keybedVersion`, so the
  one-time switch was not seen on real settings. A separate task to fix it was offered.
- **Not installed**: Logic was running. The launched standalone's window could not be captured from
  this session.

### 2026-09-10 — Session 37: the editors' name fields in Dark appearance (ADR-034)
- **Confirmed in the running standalone, along the path a click takes.**
  - An injected walker opened the preset editor from a preset cell's Edit, and the bank editor from
    a bank's Edit.
  - In Dark, both names were white on `#F8F8F8`, at 1.05. Rendering with and without the text changed
    no pixels.
  - It then swept all 53 scenes in Dark, and again with the window overridden to Light. No other
    reachable text input is unreadable in either.
- **Upstream had the same bug.** Its CI built with Xcode 11.2 against the iOS 13 SDK, and it pins no
  appearance.
- **Fix:** both fields pinned to Light in `viewDidLoad`. Three tests in `TextInputAppearanceTests`.
- **The first revert check proved nothing, and that was caught.** The test gave 5 failures in 3 tests
  both with and without the fix. In the window-less test bundle, an override set in `viewDidLoad` is
  not seen until a trait update. Fixed by laying out and calling `updateTraitsIfNeeded()`. Then 0
  failures with the fix, 3 of 3 with the Swift files reverted, and the positive control passed both
  times. CLAUDE.md has the gotcha.
- **249 → 252 tests.** On the fixed build, the live walk measures both names at 14.3 in Dark.
- **Another session was committing in the same working tree** (the wordmark, `59ffe61` to `f162dae`),
  so only this session's paths were committed. Three consequences for the owner:
  - Both sessions build into the same `DerivedData`, so that session's installs will carry this fix.
  - It launched the DerivedData standalone at 19:07:54.
  - This session's last walk then restored its own 18:49 copy of `settings.json` and
    `tunings_v1.json` over that launch's version. In this session's runs a launch only changed the
    launch count and the MIDI source list, but anything else that launch saved is gone.
- **Not installed**, because Logic was running. The three Light-only findings are offered as a
  separate task.

### 2026-09-10 — Session 36: the preset editor's bank picker crashed both products (ADR-033)
- **Three crash reports, one cause.** The extension crashed in Logic at 11:52 (twice) and at 14:53,
  the last on the ADR-032 build. `UIPickerView` throws when it enters a window under the Mac idiom,
  and the preset editor's bank picker was one.
- **Reproduced in the standalone first.** lldb drove the DerivedData build along the real path: the
  display label, then a preset cell's Edit. The reason and backtrace match the plugin's. Driving it
  cost runs in three traps:
  - `stringWithFormat:` with no prototype passes garbage;
  - a launch pop-up refuses every presentation until it is dismissed;
  - short local names collide with loaded symbols.

  CLAUDE.md and *Known issues* have them.
- **Swept the running app by walking the storyboards.** 53 scenes went into the Mac-idiom window, and
  only the preset editor threw. UIKit's own record of restricted classes
  (`UICatalystMacIdiomUnsupported_Internal`) names six. Five are unused, and plain `UIButton` is
  covered by ADR-026 and ADR-029.
- **Fix:** a `UITableView` in the picker's frame, with the picker's row label. Three new tests. With
  the fix reverted, two failed as intended and the positive control passed. Restored and rebuilt:
  **246 → 249 tests** green. After the fix, the live editor opens with no exception and the live sweep
  is clean.
- **Installed later the same evening**, with the owner's go-ahead and Logic quit. Rebuilt first, and
  11 preset-editor and UI-load tests passed. `Scripts/validate-au.sh` passed `auval`, and the
  installed framework's md5 matches the tested build.
- **The owner reported three more problems from Logic.**
  - Edit still crashing was the old build, which had not been installed.
  - The star does nothing, and Share crashes, **but only in the plugin**. The plugin cannot write
    preset files, so rename, duplicate, reorder and Save fail silently there too. Apple's share sheet
    throws when presented from an extension.
  - Both work in the standalone. That was checked under lldb, and the preset files were restored
    byte-identical afterwards.
  - The owner chose no change to saving or Share while deciding on a Developer account, and kept the
    star grey, as upstream.
- **A different crash turned up on the way:** `ArcadeRuinsAU-2026-09-09-215217.ips`, where
  `-[S1AudioUnit setCurrentPreset:]` → `presetStateFor:` threw on the XPC thread. It had not been
  recorded; offered as a separate task.

### 2026-09-10 — Session 35: velocity sensitivity always on in the standalone too (ADR-032)
- **Asked whether the standalone should match, the owner said yes.** `Manager+MIDIListener` no longer
  flattens MIDI velocity to 127 (`PORT FIX`), and the MIDI settings switch is on, dimmed and inert in
  both products. The plugin-only flag from Session 34 is gone again. `AppSettings.velocitySensitive`
  is still stored and no longer read.
- **A revert check that proved nothing, caught before it was believed.** The first run gathered its
  `-only-testing` flags in an unquoted zsh variable. zsh does not split that into separate arguments,
  so the filter matched nothing: `Executed 0 tests`, `TEST SUCCEEDED`. Redone with the flags written
  out, 5 of 29 tests failed as they should. CLAUDE.md has the gotcha.
- **245 → 246 tests**, all green on the restored sources. Installed, with `auval` passing and the
  installed framework matching the tested build.

### 2026-09-10 — Session 34: the plugin always plays its host's velocity (ADR-032)
- **The owner's answer to the velocity question: "Velocity sensitivity should always be on."** The
  question was about the plugin, so it is applied there: the router plays the host's velocity, the
  setting is gone from `S1HostMIDISettings`, and the plugin's MIDI settings show the toggle on,
  dimmed and inert. The standalone kept its switch at first; asked, the owner extended the decision to
  both products (Session 35).
- 3 new tests; the router's expectations now assert the velocity sent. Two pieces reverted at once
  each failed their tests. Restored, rebuilt: **242 → 245 tests**, all green.
- **Installed** once the owner had quit Logic. `auval` passes, and the installed framework's md5
  matches the tested build.

### 2026-09-10 — Session 33: the plugin takes MIDI only from its host (ADR-031)
- **The owner approved the proposal after the unselected-track capture.** Built it:
  - the plugin opens no CoreMIDI inputs;
  - `S1HostMIDI` handles host MIDI on the render thread as the standalone's chain does;
  - controls, program changes and held keys come back to `Manager`;
  - the interface's MIDI settings are pushed across as they change;
  - on-screen keys are queued to the render thread.
- **The router is a port, so parity is the test.** `HostMIDIParityTests` drives the same MIDI through
  a real `Manager` and through the plugin's own unit and requires identical note calls: scripted
  scenarios, eight seeded random runs, and the whole white-keys map. Upstream quirks are ported and
  pinned rather than tidied.
- **Four pieces reverted at once, and each failed the test aimed at it** — the table is in ADR-031.
  The files were restored and byte-compared, and the full suite re-run afterwards rebuilt
  `DerivedData` before anything was installed.
- **An hour's reasoning pointed the wrong way.** Two parity tests crashed on a nil recorder, and new
  C++ was the natural suspect for memory corruption. A `didSet` that logged a stack found the writer
  in one run: the recorder's own `take()` resolved to `Optional.take()`, which nils the property.
  CLAUDE.md has it.
- **The extension's crash reports showed two crashes at 11:52**, before anything here was installed:
  `UIPickerView` in the preset editor throws under the Mac idiom. Offered as a separate task.
- **217 → 242 tests.** The first full run failed one old test, which read the extension's source for
  the setup calls that moved into `SynthOneApp.makePluginAudioUnit`. It now builds the unit through
  that factory and checks it has presets, routes host MIDI and makes sound. `auval` passes, and the
  installed framework matches the tested build.
- **Checked live in Logic with the owner.** The lldb captures were repeated with the new build. With
  the plugin's track selected, one note gave one `startNote` on the render thread, and nothing arrived
  through CoreMIDI. With the other track selected, all nine breakpoints stayed silent. The extension
  no longer opens inputs or publishes virtual ports. Details under *Next action → 0*.
- **Still to do:** the velocity-sensitivity question.

### 2026-09-10 — Session 32: the plugin's two MIDI routes, measured
- **Asked to answer, with evidence, whether the plugin's own CoreMIDI inputs double or bypass Logic's
  MIDI, and to report before changing anything.** No product code changed. Findings and the proposal
  are under *Next action → 0*.
- **A stimulus that did not need the owner:** a small CoreMIDI sender on `IAC Driver Bus 1`. Logic
  and the plugin both listen to that source, so it stands where a hardware keyboard would.
- ⚠️ **The first lldb driver hung with the plugin suspended for about four minutes** inside the
  owner's Logic: it waited for a post-attach stopped event that async mode never delivered. SIGINT let
  lldb detach cleanly, the plugin resumed, and there is no crash report. The driver that worked polls
  state and was tested on a throwaway process first — see the technique under *Known issues*.
- ⚠️ **The measurement changed the owner's patch.** To leave cutoff alone, the breakpoint rewrote the
  CC1 argument to the wheel's current position; `SetValueFromCString` on that Swift argument returned
  false, so the 64 went through and cutoff moved 3210.8 → 2818.5 Hz. It also sounded one short note on
  the selected track.
- **Then, at the owner's request, the unselected-track capture: the bypass is confirmed.** The owner
  selected another track, disarmed Arcade Ruins' track and closed its window. No render-block MIDI
  reached the plugin, and CoreMIDI still started a voice that the kernel rendered. Driver v3 rewrites
  no arguments, and it arms its render-side proof only once a note starts, because that hook fires 21
  times a second. The patch was not changed this time.
- Not investigated: at 09:44:21 an extension process logged `Conductor.startHosted() called again`.
  A second instance in one process drives the first instance's `Conductor` — relevant to P4-7's
  multi-instance column.

### 2026-09-10 — Session 31: the mod wheel that would not stay put (ADR-030)
- **Owner: the plugin's mod wheel "is jittery and doesn't remain at the position it's dragged to"**;
  asked, on release it drifts back. Logic was open with the extension loaded, so this was the
  plugin, running out of process.
- **Eliminated by measurement first.** The plugin opens every CoreMIDI input itself, so a hardware
  CC1 stream was a real candidate: a 20 s sniffer on all six sources saw nothing, and the plugin
  sends no MIDI.
- **Then evidence from inside Logic.** The installed extension is a Debug build with
  `get-task-allow`, so an lldb Python driver attached to it in the owner's session while they
  dragged: **574 host-observer callbacks for `cutoff` in two minutes**, none of them the host's.
  Dragged to the top (360 Hz), the echo came back 50 ms later and the wheel was redrawn at 0.58.
  Two captures were wasted first — a closure regex that also caught the waveform's 30 Hz pull, and
  a run the owner did not know had started. The technique is under *Known issues*.
- **Two bugs.** The originator token does not cross the process boundary, so every write came back
  as a host move — every control, not only the wheel; and upstream's cutoff → wheel placement never
  inverted the wheel's own write. Fixed both: `S1HostedSynth.echoWindow` with reconciliation, and
  the exact inverse. ADR-030.
- **Reverted each fix and watched its test fail — which caught two tests proving nothing:** an
  inside-window check that ran before the tree's late, coalesced callback had arrived, and an
  end-to-end test that was also measuring the touch pad's reset animation, which reaches the same
  placement code with no echo at all. A spy on `updateUI` told those apart. Both rewritten and
  re-verified.
- **The experiments left `DerivedData` built from the reverted sources.** Restoring the files does
  not restore the build, and `validate-au.sh` installs from `DerivedData` — it would have shipped
  the bug. Rebuilt and re-ran the new tests against that build before installing.
- **212 → 217 tests.**
- Flagged, not investigated: the plugin opens hardware MIDI inputs *and* takes the host's MIDI
  through the render block (ADR-030, *Not addressed*). Offered as a separate task.

### 2026-09-09 — Session 30 (end): a publishing audit, and a bug that was a design

No code changes in this stretch; `main` is `0507d74` plus this documentation commit.

- **The owner asked to publish to GitHub and offer downloads.** I audited first, because a public
  repo cannot really be made private again. The full-history secret scan is clean for our code, but
  it found AudioKit's live Audiobus key in `upstream/`, plus 9.5 MB of their App Store screenshots
  in `docs/reference/`. **Gatekeeper, measured against the installed build: `rejected`** — ad-hoc
  signature, no Team ID — so a download would fail as "damaged" without an `xattr` step. The Release
  configuration builds (20 MB, appex embedded). Both choices went to the owner; the questions were
  dismissed and the owner moved on, so **nothing was published**. See *Next action*.
- **The owner reported the DCO waveform selector's highlight as clunky and draggable.** Traced it to
  three real upstream defects: absolute PaintCode geometry, mismatched touch and draw mappings, and
  a `!=` that ignored every single touch. I wrote a fix with eight tests at both real widths — then
  the owner realised the control is a continuous morph and withdrew the report. **Reverted
  completely, never committed.** The findings are under *Known issues* so they are not rediscovered.
- **The lesson:** establish what a control *is* with the owner before writing a change to what it
  does. The first question worth asking was whether this was a switch or a morph.
- STATE.md's top half still described P4-6 as the next task; it is rewritten for a cold start.

### 2026-09-09 — Session 30 (cont.): the project is called Arcade Ruins
- **README, LICENSE and NOTICE.md now exist.** The repo had *none* of them, which was the one thing
  genuinely at odds with calling it open source — with no licence file the default is
  all-rights-reserved. MIT, plus a NOTICE covering AudioKit Synth One, AudioKit 4.9.2, Soundpipe
  and TAAE (zlib, which asks for an acknowledgement and now has one).
- **The legal question the owner asked, answered.** Upstream is MIT and its README explicitly grants
  re-skinning and redistribution. Copyright and trademark are separate; only trademark constrains
  this, so the *marks* go and the attribution stays. All 695 presets come along under the same
  licence — and the `bank` field on each one **is** the sound designer's credit, so bank names are
  now protected by NOTICE.md as well as by ADR-024's load-order argument.
- **Rebranded at product-identity level.** Display names, bundle IDs, `.app` name, AU name and
  description; header wordmark, both About logos, all 18 app icons; About/MailingList copy and every
  outward link. Internal targets and the `SynthOneCore` module stay — provenance signal, ADR-009,
  and 153 import lines not worth the risk.
- **`aks1` → `ruin`, and that had a deadline.** The AU's `manufacturer`+`subtype` is what a host
  stores in a session file. It was free to change today and will never be free again.
- **Two things that would have silently kept the old name:** six localised `InfoPlist.strings`
  hard-code `CFBundleDisplayName = "Synth One"` and override the plist; and seven `About.strings`
  held translated copy describing a *different product* ("the first free iOS synth in history") —
  deleted rather than edited, so those languages fall back to accurate English.
- **The ~100-name contributor list in the About panel is untouched.** Those are the people who built
  the instrument. Only the framing paragraph around it changed.
- **The branded assets are generated** — `Scripts/branding/`. Wordmark and icon are code.
- ⚠️ **`/Applications/SynthOne.app` must be deleted by hand.** It still registers the old
  `aumu`/`aks1`/`BP03`, so a host lists both plugins until it goes.
- **The wordmark is orange-to-grey, not magenta-to-cyan.** The owner called the clash on the first
  pass. Both ends are now sampled from the app rather than chosen: `#E68800` is the accent orange
  used twelve times across the panels, `#DEE3E2` the brightest ink in the wordmark replaced. Glow
  cut to two-thirds. The app icon is untouched — the owner scoped this to the label.
- **The wordmark is centred in the header's `Title Button` frame** `(7,3,200,30)`, computed from
  that frame rather than placed by eye. Synth One's own was 11px/79px left-right and 22px/8px
  top-bottom inside it; both are now even.
- **The rectangle the owner saw around it was a bug, not a frame.** `Title Button` is a transparent
  hit area, and the Mac behavioural style draws a bare `UIButton` as a macOS push button — ADR-026
  again, missed there because that sweep went class by class and this one has no `customClass`.
  Fixed with a hierarchy walk; reverting it fails the new test with **five** offenders, not two
  (title, dice, prev, next, host-app icon). **Enumerating classes has now missed live cases twice.**
- **212 tests green.** `auval` clean against the new `ruin` subtype — which also proves the renamed
  `NSExtensionPrincipalClass` resolves, since auval instantiates the view controller's unit.

### 2026-09-09 — Session 30 (cont.): the plugin's waveform now moves
- **The animated waveform under the volume knob works in the plugin.** It never had: P4-6 built the
  plot as `AKNodeOutputPlot(nil)` — a live view over nothing — because it draws by tapping an
  `AVAudioNode` and a plugin has none. It drew a flat line, which the owner noticed after the volume
  knob was re-centred over it.
- **The traffic runs the other way now.** `AVAudioNode.installTap`'s callback allocates and
  `dispatch_async`es, neither of which is legal on a render thread, so the shape could not be
  reused. `S1AudioUnit` keeps a fixed 1,024-sample ring (`S1Scope`) that the render thread writes
  into and the plot pulls from on a 30 Hz `CADisplayLink`. A **seqlock** separates them: the writer
  never waits, and a reader that catches a write in progress retries and then keeps its last frame.
  Off by default — the standalone still taps the mixer and pays nothing. ADR-028.
- **The tests assert the plot receives the tail of the audio the host played**, not that a copy
  reported success — an all-zero snapshot is exactly what the bug looked like. Verified by reverting
  `push`: three of five fail, one of them on the owner's symptom.
- **202 -> 211 tests.** `auval` clean.

### 2026-09-09 — Session 30 (cont.): the Record button, and the last raw idiom reads
- **Owner asked whether the Record button is needed.** In the plugin it was a *dead control* —
  every call site is optional-chained and `startHosted` builds no `AudioRecorder`, because it taps
  a mixer the plugin does not have. It is now hidden when there is no recorder.
- **In the standalone it was heading for a crash.** `didFinishRecording` presents a
  `UIActivityViewController` and set its popover source only when the idiom was `.pad` — which
  stopped being true at ADR-023. Catalyst throws without one, so stopping a recording would have
  taken the app down. Replaced with opening the containing folder, which reveals it in Finder.
- Recordings now go to **`~/Music/SynthOne`** instead of `temporaryDirectory`. The temp directory is
  right on iOS, where a share sheet takes the file away immediately; on a Mac the system is free to
  reap it.
- **Swept for other raw idiom reads, as asked. Three, all broken since ADR-023**, and one was a live
  visual bug nobody had reported: the microtonal keyboard drew its key labels at font size **10**,
  the iPhone size, instead of 14. The other two were the share-sheet popovers above and in the
  mailing-list panel. A test now fails on any use of `UIDevice.current.userInterfaceIdiom`.
- **199 -> 202 tests.** `auval` clean.

### 2026-09-09 — Session 30 (cont.): the tempo bug I mistook for a confirmation
- **Owner: "Logic's project tempo is 120 by default, so it should have read 120."** Correct, and it
  exposed a bug *and* a bad claim of mine. `handleTempoSetting` compared the host tempo against a
  `tempo` member initialised to **120**, so a project at Logic's default never looked like a change
  and `arpRate` was never set. Every tempo except 120 worked.
- **I had reported `tempo=100.0` from the diagnostic log as proof the binding worked.** It was the
  opposite: 100 was the loaded preset's own `arpRate`, and seeing it there was the evidence that the
  host tempo had never been applied. I saw a number that was not 120 and rationalised it.
- **Fixed by comparing against `arpRate` rather than the last tempo seen**, which also fixes a
  second bug in the same line: a preset writes its own `arpRate`, and an unchanged host tempo would
  never have corrected it. The host is now continuously authoritative. ADR-027.
- **This time I reverted the fix and watched the tests fail** with the owner's exact symptom
  (`100.0` where `120.0` was expected) before shipping. That step was skipped earlier the same day
  on the message-queue fix, where the "regression test" passed against the unfixed code.
- **196 -> 199 tests.** `auval` clean.

### 2026-09-09 — Session 30 (cont.): the parameter binding, and a false alarm
- **P4-6 is complete.** Control moves go through the `AUParameterTree` so a host records them; an
  observer token carries host moves back to the controls without echoing. Host tempo now reaches
  the tempo control as well as the DSP.
- **Then "no audio in Logic" — which was not a regression.** The extension had crashed on load
  earlier in the day (the `Tunings` subscript), Logic had that build loaded, and it stayed open
  through five reinstalls. A stale plugin presents as *silence*, with nothing in the host saying so.
- **I could not reproduce it and stopped guessing.** Four headless reproductions all made sound —
  interface loaded, every panel loaded, stopped transport, musical context. `auval` passed too.
  So I shipped a build with an `os_log` probe in the render block and read the unified log
  afterwards: 23 of 72 sampled blocks had audio, peak 0.22, and `tempo=100.0` — Logic's project
  tempo, which also confirms the tempo binding works end to end.
- `Scripts/validate-au.sh` warns when a host is running, and CLAUDE.md has the gotcha. The lesson
  is the same one as ADR-021: when a plugin misbehaves inside a host, get evidence *out of the
  host* rather than reasoning about it from the source.
- 196 tests green; probe removed.

### 2026-09-09 — Session 29: the plugin draws, and every button was dead
- **The plugin loads in Logic with its real interface.** `Conductor.startHosted(audioUnit:)` wires
  the same twelve storyboards to the audio unit a host provides — no engine, no mixer, no output
  device. `Conductor.synth` became `S1SynthControlling` so all 153 UI files are untouched.
- **Then the owner reported `Hide` did nothing, and later that `Wheels` did not either.** That
  second report was the whole diagnosis: two buttons dead, every knob and stepper fine. Under the
  Mac idiom `UIButton` is backed by an AppKit cell and **never calls `touchesBegan` on the
  subclass** — so six control classes went silently dead the day the idiom changed (ADR-023).
- **Six, not two.** A test that greps for `UIButton` subclasses overriding `touchesBegan` found
  `FilterTypeButton`, `PresetUIButton` and `HeaderNavButton` as well. The owner had not reached them.
- **I had already spent two sessions on `Hide` looking in the wrong place** — the button class, the
  storyboard's stale `customModule`, the constraint, the layout engine. All of it worked; I even
  proved the constraint moves the keyboard 299 points. The bug was one layer above all of it.
- Fixed a second bug in passing: upstream ran each button's callback **twice per tap**, from
  `touchesBegan` and again from `touchesEnded`.
- **A host-less test bundle cannot press a button** — `sendActions(for:)` dispatches through
  `UIApplication.shared`, which does not exist there. Same family as ADR-023's `NSApplication`
  problem. The tests assert the wiring structurally and the behaviour by calling the action, and
  say so rather than implying they simulate a click.
- **178 -> 185 tests**, green. `auval` clean. Installed to `/Applications`.

### 2026-09-09 — Session 28: P4-5, and a crash that stopped being deferrable
- **Host tempo is `arpRate`,** and upstream had already answered the question I had written up as a
  design decision: its Ableton Link listener did `setSynthParameter(.arpRate, bpm)` and moved the
  tempo stepper. Dropping Link (ADR-004) is precisely why this work landed at P4-5. Both upstream
  TODOs in `handleTempoSetting` are answered by that one file.
- **Transport stop releases voices and rewinds the sequencer**, and deliberately does *not* lock the
  sequencer to the host's beat position — `process` resets `mBeatTime` on the held-keys edge, so the
  arpeggiator starts when you play rather than on the bar line. Offline bounces stay repeatable
  anyway, because the note-on that sets the phase lands in the same place every time.
- **Two upstream methods do not do what their names say**, both found by testing rather than
  reading. `S1DSPKernel::reset` is documented "Puts all notes in release mode" and calls
  `S1NoteState::clear()`, which sets `amp = 0` — a hard cut that clicks. And `S1Sequencer::reset`
  clears note vectors while leaving `mBeatTime`/`mStepCounter` alone, which means
  `resetSequencer()` never rewound anything despite the name. Added `resetPosition()`.
- **The message-queue use-after-free is fixed.** It was written up at P4-4 as its own task and
  deferred; it took the runner down a second time here, which is enough. The render thread now
  addresses an immortal `S1MessageRelay` with a weak reference to the unit.
- **The lesson of the session.** My first regression test for that fix generated a backlog, dropped
  the unit, and drained — and **passed against the unfixed code**, because the freed memory had not
  been reused. A use-after-free is not deterministic. I very nearly shipped it as proof. The tests
  that shipped verify the mechanism instead, and say plainly that they are not testing the crash.
- Also worth remembering: my first attempt to measure the arpeggiator counted note attacks in the
  rendered audio and found one. The arp was running fine — the notes overlap and the patch fades up
  through portamento, so the envelope never falls back between them. The beat counter *is* the
  sequencer's clock and is exact.
- **152 -> 163 tests**, green across two consecutive full runs. `auval` clean.

### 2026-09-09 — Session 27: `Octave:` becomes one global octave
- **Owner's decision, implemented and confirmed on real hardware:** one control. Up one octave and
  the on-screen keys relabel C2 to C3 *and* a MIDI keyboard's C2 plays C3. `midiOctaveShift` is
  *derived* from `typedOctave` rather than stored beside it, so the on-screen keyboard, the typing
  keyboard and MIDI input cannot drift apart.
- **The two non-obvious parts**, both tested: a note-off releases the note its note-*on* started
  (a map of incoming -> sounding), or nudging the octave with a key held sticks the note forever;
  and a note shifted past 127 is **dropped rather than clamped**, because `notesFromMIDI` is a set
  and clamping several keys onto 127 would make releasing one silence the others.
- **Rejected: routing this through the DSP's `transpose` parameter.** It looked like the tidier
  answer — it would have covered the plugin too — but it applies *on top of* the on-screen
  keyboard's own shift, so one octave step would move the virtual keys by two. It is also a preset
  field, so presets and the stepper would have fought over it.
- Updated the comment in `Manager+ComputerKeyboard.swift` that documented the opposite decision.
  Upstream's reasoning is sound on an iPad, where touch is the only input; it is not on a Mac.
- **148 -> 152 tests.**

### 2026-09-09 — Session 26: the window buttons, and the Octave bug that was not one
- **Fixed: the traffic lights sat on top of the "AudioKit Synth One" label.** `SceneDelegate` hides
  the title bar, so content runs to the top edge and macOS draws the window buttons over it.
  Catalyst already reports the room they need — `safeAreaInsets.top`, **measured at 32 points on a
  running build**, not guessed — and `S1ScalingContainer` was laying out in the full bounds and
  ignoring it. It now lays out inside the safe area, and the window opens 32 points taller so the
  interface is still 1:1.
- The inset arrives on the *second* layout pass (the first reports zero), so
  `viewSafeAreaInsetsDidChange` re-applies the scale.
- **The geometry moved out of the view to be testable.** A Catalyst safe area only exists inside a
  real window, and a visible `UIWindow` in this host-less test bundle throws "NSApplication has not
  been created yet" — so `S1ScalingContainer.layout(in:safeArea:)` is a pure function the tests can
  call. That the caller passes `view.safeAreaInsets` is *not* covered by a test, and the comment
  says so; it was verified by measurement.
- **The `Octave:` stepper was never broken.** The owner supplied the missing observation: it works
  on the on-screen and typing keyboards, and does not affect a hardware MIDI keyboard — which is
  upstream behaviour, since `Octave:` is the on-screen keyboard's octave. Confirmed in code:
  `receivedMIDINoteOn` passes the note number straight through with no offset. **The three ranked
  hypotheses in Known issues were all wrong**, including the plausible one about `Stepper`'s
  mismatched hit rects, which is a real geometry bug that nobody was actually seeing. Two sessions
  on a bug that one sentence from the owner settled — the same shape as ADR-015's consent dialog.
- Left as an open **product question**, not changed: whether a global octave should transpose MIDI
  input too. The DSP already has a `transpose` parameter, so the vehicle exists; the decision does
  not, and changing input transposition would change how the instrument plays for everyone with a
  controller.
- **144 -> 148 tests**, green.

### 2026-09-08 — Session 25: P3-1b, and both halves of P4-4
- **P3-1b — Optimize Interface for Mac.** The decision was the owner's; finding the switch was the
  work. It is `TARGETED_DEVICE_FAMILY` (family 6 = Mac), and ADR-023 records the four things it is
  *not*, because I tried three of them first. The most seductive was
  `UIDesignRequiresCompatibility`: a real key, in the shared cache, sounding exactly right, and
  belonging to SwiftUI's macOS 26 design system rather than to Catalyst. Setting it changed nothing.
- **Two self-inflicted detours worth not repeating.** `plutil -extract KEY json FILE` **rewrites the
  file in place** unless given `-o -` — I destroyed a built `Info.plist` with it and spent a while
  reading the wreckage as evidence. And a unit test cannot observe the app's idiom at all: the test
  target has no host, so it runs in `xctest`, whose own bundle decides it.
- **P4-4, and the finding that justifies the house rule.** The round-trip test renders the restored
  unit and compares audio sample-for-sample instead of comparing dictionaries — and it failed.
  `allocateRenderResources` calls `S1DSPKernel::init`, which rewrites all 128 tuning entries back to
  12-ET; upstream snapshotted `parameters` around that call but not the tuning table. Invisible in
  the standalone, where the Tunings panel re-applies after the engine starts. Fatal in a plugin,
  which gets one shot. **A dictionary-comparison test would have passed.**
- **All 695 presets go in the host menu**, named `Bank: Preset`. The numbering is now a
  compatibility surface: a host stores the *number*, so `S1FactoryPresets.bankOrder` cannot be
  reordered without silently repointing saved sessions.
- **`Preset.apply(to:)` now targets a protocol** rather than `AKSynthOne`, because the plugin has no
  node wrapper and duplicating the hundred-line mapping would be two places to get the order wrong.
- **A second bug found and deliberately not fixed:** TAAE's main-thread messages carry the audio
  unit as a raw pointer, so a queued message can outlive its unit and the handler retains freed
  memory. It segfaulted the test runner once my preset tests started creating and destroying units
  with messages in flight. Worked around in the tests, written up in Known issues with three
  candidate fixes. It is its own task.
- **136 -> 144 tests**, green across two consecutive full runs (the crash was intermittent, so one
  green run would not have meant much). `auval` clean.

### 2026-09-08 — Session 24: P4-3, the plugin obeys the host
- **The project had moved.** The session opened in the old iCloud directory, which now holds only a
  `MOVED.md`. Followed it to `~/Developer/SynthOne`.
- **`startRamp` implemented** — one line of effect, three decisions around it (ADR-022). The one
  worth arguing about was `notifyMainThread`. The cheap answer is `false`; it is wrong, because for
  142 parameters the flag costs nothing and for the other eight `_rateHelper` **quantizes** the
  value, so suppressing the notification does not save work on the parameters that matter — it
  makes the UI wrong about exactly those.
- **The finding worth having found:** upstream passed `dependentParameters:nil` for all 150
  parameters. That was harmless while nothing automated the tree and is not harmless now — one
  automation move on `arpRate` changes **five** DSP values, and a host that does not know keeps
  showing, and later writes back, four stale ones. Declared on the two drivers.
- **A test trap that cost a full round trip.** Every test that scheduled a parameter failed
  identically, exactly as if `startRamp` were still a no-op. It was not: `scheduleParameterBlock`
  hands its event to the *framework*, and it is `AUAudioUnit.renderBlock` that drains the pending
  list into `internalRenderBlock`'s `realtimeEventListHead`. The existing ADR-021 tests drive
  `internalRenderBlock` directly — they have to, since forging a past timestamp is otherwise
  impossible — and that silently delivers no scheduled parameters at all. Both paths are now in the
  file with the distinction spelled out.
- Added `Signal.spectralCentroid` to the shared test helpers: peak and RMS both move when a filter
  opens, but they also move when the amplitude does, so neither shows the *spectrum* changed.
- Noted but **not fixed**: `_setSynthParameterHelper` calls
  `updatePortamento(getParameter(portamentoHalfTime))`, and `getParameter` returns the ramping
  value rather than the portamento target — so setting `portamentoHalfTime` applies the previous
  one. Upstream behaviour, and changing it would move the goldens.
- **119 → 126 tests**, all green including the 20 golden renders (the standalone sets parameters
  through `setSynthParameter` on the main thread and never touches the tree, so the DSP is
  unchanged). `auval` passes in ~8s — up from 2s because *Checking parameter setting* now applies
  all 150 parameters instead of none.


### 2026-09-08 — Session 23: documentation, so P4-3 can start cold (no code changes)
- **`Where things stand` was a session behind** — it said "P4-1 is done" and did not mention that
  the plugin now makes sound. Rewritten.
- **The `▶ Next action` section was accurate but thin.** It named `startRamp` without saying where
  it is or what calling `setSynthParameter` from the render thread actually does. Traced the whole
  path by reading and wrote it down: `implementorValueObserver` → `scheduleParameterBlock` →
  `processWithEvents` → `handleOneEvent` → `startRamp` → nothing, with file:line for each hop.
- **The finding worth having found:** `setSynthParameter` hard-codes `notifyMainThread = true`,
  because upstream's only caller was the main thread. Eight parameters route through `_rateHelper`
  and post to TAAE's main-thread endpoint; `portamentoHalfTime` loops all 150. None of it is
  unsafe on the render thread — the endpoint is a lock-free ring buffer — but it is best-effort,
  so a full buffer silently drops a UI update. P4-3 has to choose that flag deliberately rather
  than inherit it.
- Also noted that `duration` is ignored everywhere, and that the kernel smooths with Soundpipe
  `sp_port` rather than an AU ramp — so "honour `duration` or defer to `sp_port`" is a P4-3
  decision, not an oversight to fix silently.
- **CLAUDE.md:** three gotchas from ADR-021 (a hang is not slowness; an out-of-process AUv3 turns a
  crash into a hang — check the *extension's* DiagnosticReports; the signed→unsigned cast), and the
  stale ADR-015 row corrected — the 90 seconds was a microphone consent dialog, not CoreAudio.
  `Scripts/validate-au.sh` added to the every-session checklist now that `auval` is a real check.
- **PORT_PLAN.md:** P4-3 points at `startRamp` and at STATE.md rather than restating it.
- Unchanged and still open: the Octave stepper bug (Known issues) and P3-1b.


### 2026-09-08 — Session 22: P4-2 — the plugin makes sound, and a crash that looked like slowness
- **The plugin vends the real `S1AudioUnit`.** The P1-1 stub that `memset` the buffer to silence is
  deleted. Wavetable loading came out of `AKSynthOne.init` into `S1Wavetables` — the AUv3 has no
  `AKSynthOne`, and the tables must be loaded between `init` and the host's
  `allocateRenderResources` or `sp_oscmorph2d_init` dereferences tables that do not exist.
- The AU path creates **no engine at all**: the host owns the graph and gives us the format. 5 tests
  drive it the way a host does — audio out, 440/220 Hz, 150 parameters present, 48 kHz.
- **`auval` then stopped finishing, and I misdiagnosed it as slowness** ("it tests 150 parameters
  now"). The owner asked why it would take so long, which was the right question.
  - **0.0% CPU and no output for 2.5 hours — a hang, not slow work.** That one check should have
    come first.
  - `sample` put the main thread in `AUAudioUnit_XPC internalRenderBlock → signal_wait`: waiting on
    an XPC reply from the extension.
  - `DiagnosticReports` had **three `SynthOneAU` crashes**, the last at exactly the second auval's
    output stopped. `EXC_BAD_ACCESS` in `S1DSPKernel::process`.
- **The bug:** `DSPKernel::processWithEvents` computes its segment as
  `AUAudioFrameCount(event->head.eventSampleTime - now)` — an **unsigned cast of a signed
  difference**. An event at or before `now`, which is what `AUEventSampleTimeImmediate` and
  therefore every automation move produces, becomes ~4 billion, and it renders four billion frames
  into a 4,096-frame buffer. Clamped both ends. **`auval` now passes in 2 seconds** with all 150
  parameters tested and no crash. ADR-021.
- Three lessons, only one about code: **a hang is not slowness** (0% CPU tells you in one command);
  **an out-of-process AUv3 turns a crash into a hang**, with nothing in the host's output naming the
  cause — check the *extension's* crash reports; and **vendored sample code is not tested code**,
  the same shape as ADR-011 and the P3-1 assertion bug.
- Found while there: **`S1DSPKernel::startRamp` is an empty function**, so the plugin receives host
  automation and discards it. Upstream's state, and exactly what P4-3 must implement. Pinned by a
  test that will fail when P4-3 lands.
- 111 → 119 tests green.

### 2026-09-08 — Session 21: P4-1 — the sandbox question, answered
- The extension target and its `AudioComponents` were already `auval`-clean from P1-1, so **P4-1's
  real content was settling the question ADR-018 left open**: can an ad-hoc-signed AUv3 be
  unsandboxed? Everything about whether to buy a Team ID hung on it.
- Measured all three routes with a probe the extension writes when a host instantiates it:
  - **Sandboxed, shared folder:** `sharedExists=true` but `canListShared=-1` and reading
    `settings.json` fails with a permission error. Confirms what ADR-018 assumed.
  - **Unsandboxed:** `auval` fails at `OpenAComponent: result: 4` — **the system refuses to open the
    component at all** and the extension is never instantiated. This is a platform rule about app
    extensions, not an ad-hoc-signing limitation; no entitlement gets around it.
  - **Sandboxed, own framework bundle:** banks, wavetables and storyboards all readable.
- **So: the plugin ships factory presets only**, which is a much smaller loss than it first looked.
  All 695 factory presets and the whole UI are framework resources. Only *user*-saved presets cannot
  cross, and per-session state is unaffected because that is `fullState` (P4-4), not the filesystem.
  **The Team ID question is now a product decision rather than a technical unknown** — and taking it
  later changes `Disk.sharedSupportURL` and two entitlement files, nothing else.
- Six tests guard the packaging. The identity ones matter most: `aumu`/`aks1`/`BP03` is what every
  saved session in every DAW references, and changing one orphans every project that used the
  plugin. There is no migration for that, so it gets a test rather than a comment.
- `Bundle.synthOneCore` is public now — the extension legitimately needs it, and P4-6 will too.
- 105 → 111 tests green; `auval` passes.
- **Next:** P4-2 — make the plugin make sound.

### 2026-09-08 — Session 20: owner testing — the Octave control did nothing
- Owner reported *"the octave setting doesn't seem to do anything."* It did — just not the thing a
  person would expect.
- **Diagnosis, by driving the real control rather than reading it:** the `Octave:` stepper fires
  correctly and moves `keyboardView.firstOctave` (value 2 → firstOctave 4). What it did *not* do was
  change what you play, because **P3-5 gave the typing keyboard its own private octave**. The app
  had two: the stepper moved the on-screen keyboard while `Z`/`X` moved what actually sounded. On
  the iPad there is only one, because touch is the only input — the equivalence was mine to break.
- Fixed by making `typedOctave` a computed view of the stepper. Now the stepper changes what typing
  plays, `Z`/`X` move the stepper, and the on-screen keyboard follows either. Clamping is the
  stepper's own range (−2…4 → MIDI 24…96). Four tests.
- Checked two things I might otherwise have asserted: **incoming MIDI is deliberately not
  transposed** by this (a MIDI note carries its own pitch — Transpose is the control for that), and
  **preset load already sets the stepper and the keyboard consistently**, so there was no bug there.
- Also caught by the new tests: `ComputerKeyboardTests` never started the synth, and
  `Manager.viewDidLoad` force-unwraps `conductor.synth`. Fixed with the same offline start
  `UILoadTests` uses.
- 102 → 105 tests green.

### 2026-09-08 — Session 19: P3-6b, a resizable window
- Owner asked for a window resizable by its bottom-right corner. **Scaling, not relayout** — the
  storyboards place every control by hand at 1024×768 with no adaptive layout underneath, so
  stretching would strand controls, open gaps between panels and push the keyboard off the bottom.
  `S1ScalingContainer` holds the interface at its design geometry and applies a uniform transform to
  fit, like a plugin GUI. ADR-019.
- Opens at 1:1, resizes from 0.5× (where labels stop being readable) to 3×. Non-4:3 windows letterbox
  in the panel background colour so it reads as part of the instrument rather than a gap.
- **The trap worth knowing:** the transform has to be cleared before setting the frame, or UIKit
  reads the frame in the *scaled* space and the view creeps on every layout pass — and a live window
  drag is a great many layout passes. `testRepeatedLayoutDoesNotDrift` is that regression.
- Renders at three sizes are in `Renders/ui/resize-*.png`; the layout is identical at each.
- **This makes P3-1b less pressing.** ADR-007 was partly about the interface being stuck at one
  wrong size. It is not stuck any more — the remaining question is only about Mac control metrics.
- 94 → 102 tests green.

### 2026-09-08 — Session 18: P3-5 and P3-6 — the app becomes a Mac app
- **P3-5, pointer input.** Knobs gained the **scroll wheel** and **⌥ fine drag**; double-click to
  default already worked and is now pinned by a test.
  - The scroll recogniser sets `allowedTouchTypes = []` so it responds *only* to indirect scroll
    events. Without that it competes with the click-drag and the knob jumps.
  - **Computer-keyboard note entry is the real answer to having one pointer** — chords by mouse
    otherwise require turning Hold on and clicking notes one at a time. GarageBand and Logic's
    Musical Typing layout deliberately: this is a Mac synth and its users have that map in their
    fingers. Notes route through `keyboardView.pressAdded`, the same path MIDI uses, so hold, mono
    and key highlighting behave identically whatever played the note.
  - Key auto-repeat is suppressed (a held key sends repeated `pressesBegan`, and every repeat would
    retrigger the envelope), and an octave shift releases what is sounding first — otherwise the
    key-up computes a different note number and the old one sticks on.
  - **Touch pads and the ADSR editor needed no change**: they already track a single touch and reset
    on release. Checked rather than assumed.
  - **Right-click MIDI-learn turned out to be unnecessary.** The plan listed it as replacing a
    long-press; MIDI learn is actually a global mode toggled from the header, and assignment is a
    plain click. Already single-pointer.
  - Found a latent upstream bug on the way: `Knob` wires its gestures only in `init?(coder:)`, so a
    knob constructed in code has none. Invisible upstream, where every knob comes from a storyboard.
  - Also simplified `RateKnob`, which overrode the entire drag routine to change one line and so
    would have silently missed ⌥ and the scroll wheel. It overrides the value derivation now.
- **P3-6, window and chrome.** A `SceneDelegate` — new, since an iPad app has no window — that names
  the window, bounds it between 0.75× and 2× the 1024×768 design size, and hides the title bar. The
  size bound matters: the storyboards place every control by hand and there is no adaptive layout
  underneath, so a freely resizing window pulls the panels apart.
- **The menu bar is as much removal as addition.** Catalyst hands every app a default menu full of
  things a synthesiser cannot use — Format, New Window (which would open a second synth), Recents,
  spelling, substitutions, speech. Those are removed; **Panic (⌘.)** is added, along with a
  discoverable Musical Typing section so the typing keys are not folklore.
- 84 → 94 tests green; app builds and launches.
- **Next:** P3-1b, the ADR-007 idiom decision — the one Phase 3 item that wants the owner's eye.

### 2026-09-08 — Session 17: P3-4, and a 72-second launch that was not what it looked like
- **P3-4.** `S1MIDI` over CoreMIDI: source enumeration, connect/disconnect by display name, a
  virtual destination and source, and hot-plug through the client notify block. Incoming Universal
  MIDI Packets (MIDI 1.0 protocol, `MIDIInputPortCreateWithProtocol` — the API that is not
  deprecated at our deployment target) are parsed into the `AKMIDIListener` calls `Manager` and
  `KeyboardView` already implement, so MIDI learn and CC mapping ported untouched.
  - Verified on the owner's machine against real hardware: the app's `AudioKit Synth One` endpoints
    appear system-wide alongside their M4 and SL GRAND.
  - 7 tests drive the parser directly. Pitch bend gets three known values, because assembling the
    two 7-bit halves in the wrong order still produces plausible numbers.
  - `addListener` now kicks an initial setup-change: CoreMIDI only notifies on *change*, and
    upstream relied on AudioKit having already scanned. Without it nothing connects until you unplug
    something.
  - The Bluetooth MIDI button opens **Audio MIDI Setup** instead of hiding, closing the gap the UI
    cross-check found in the bottom bar.
- **The app took 72 seconds to show its window, and I misdiagnosed it.** Timestamping the launch
  showed `SynthOneApp.start()` returning 72 s late, which matched ADR-015's `outputNode` stall
  exactly — so I wrote that into the code and was about to put it in an ADR. **The owner supplied
  the actual cause: a consent dialog they had not clicked.** A TCC record for
  `kTCCServiceMicrophone` confirmed it.
  - Upstream's session category is `.playAndRecord`, which makes macOS ask for microphone access.
    **Synth One never records audio input on macOS** — `S1NodeRecorder` taps the mixer's *output*
    (P2-3), and Audiobus and IAA are gone (P3-2). The permission was being requested for nothing.
  - Now `.playback`, with the `device.audio-input` entitlement and `NSMicrophoneUsageDescription`
    removed. Permission reset, relaunched: instant, and **nothing is asked for**.
  - **ADR-015 is corrected, not withdrawn.** Re-measured in `xctest` afterwards: `outputNode` costs
    **0.59 s**, not 90 — the stall it was built on does not reproduce, and its stated mechanism was
    wrong. What survives is the practice: choose manual rendering before touching the engine when
    you do not want hardware, an AUv3 must never touch `outputNode`, and never block the window on
    device setup. `Conductor.start(mode:)` now starts the realtime engine off the main thread, so no
    slow device or future prompt can hide the UI again.
  - The lesson is ADR-011's in a new costume: **a reproducible measurement is not a diagnosis.**
    Two different processes were blocked on the same dialog and it looked like a CoreAudio pathology.
- 76 → 84 tests green; app builds, launches instantly, MIDI endpoints live.
- **Next:** P3-1b (the ADR-007 idiom decision), then P3-5 and P3-6.

### 2026-09-08 — Session 16: P3-2 and P3-3
- **P3-2.** `S1PlatformServices` — a protocol whose default implementation does nothing — now
  carries the StoreKit review prompt, Audiobus/IAA host registration, the host icon and host
  switching. The call sites stay where upstream put them, per the port plan.
  - Push (OneSignal) and analytics (AppCenter) needed no stub at all: **upstream already guards them
    with `#if !targetEnvironment(macCatalyst)`**, so they are unreachable here. The `OneSignal` shim
    P3-1 added was dead code and is gone.
  - **Removed AudioKit's live Audiobus API key** from `Private.swift` — a real credential sitting in
    their public repository, and nothing we use.
  - **The `"***REMOVED***"` strings are upstream's own placeholders and are load-bearing.**
    `MailingListViewController`, `Manager` and `Manager+HeaderDelegate` all gate the mailing-list
    signup on `Private.MailChimpAPIKey != "***REMOVED***"`. Filling one in switches the feature on.
    Pinned by a test so nobody tidies it away.
- **P3-3, and the answer is uncomfortable.** Presets now live in
  `~/Library/Application Support/SynthOne/`, with a once-only migration out of the old sandbox
  container — verified end to end: 15 files moved, existing files not overwritten, non-JSON left
  behind.
  - App Groups need a Team ID (ADR-006). The documented fallback, a
    `temporary-exception.files.home-relative-path.read-write` entitlement, **is denied under ad-hoc
    signing**: it is present in the signature and the sandbox refuses the write anyway
    (`NSPOSIXErrorDomain 1`). Measured with a probe the app wrote into its own container, not
    assumed. Same code unsandboxed: `create=ok`.
  - So **the app is no longer sandboxed** (defensible under ADR-005 — local-only, unsigned, not App
    Store), and **the AUv3 stays sandboxed and still cannot see the presets**. That half of P3-3 is
    genuinely unsolved and lands on P4-1. ADR-018 says so plainly.
  - Migration names the legacy container path explicitly rather than asking `FileManager` for "the
    Documents directory" — unsandboxed, that is the user's own `~/Documents`.
- **A near-miss worth recording:** the first run of the sandbox experiment appeared to show the
  unsandboxed build failing too. It was wrong — the previous instance was still running, so
  `open -a` activated it instead of launching the new binary. `pkill` first. That false result was
  one step from going into the ADR as a finding.
- **Caught a 300-second test.** The full suite went 14 s → 315 s, all of it in `UILoadTests`: it
  calls `SynthOneApp.start()`, which started a **real-time** engine, which touches
  `AVAudioEngine.outputNode` — the exact 90-second stall ADR-015 documents. Added
  `Conductor.AudioMode` / `SynthOneApp.start(mode:)`; the UI tests start offline. Back to 14.9 s.
  The same distinction is what the AUv3 will need at P4: an audio unit renders through its host and
  must never open an output device.
- 62 → 76 tests green; app builds and launches; presets land in the shared folder.
- **Next:** P3-4, the CoreMIDI layer.

### 2026-09-08 — Session 15: UI cross-check against the App Store captures
- Compared our rendered panels against `docs/reference/appstore/` panel by panel. Written up in
  **`docs/06-ui-cross-check.md`**; `docs/03-parity-checklist.md` panel rows moved to `[~]`.
- **Corrected a P0-5 conclusion.** `docs/reference/README.md` claimed `ipad-06` is "the shot whose
  labels match our source", inferred from `Global`/`Resonance`/`Semitones`/`Volume` appearing in
  `Generators.storyboard`. The inference does not hold: that file has **two scenes**, iPad and
  iPhone, and grepping it returns the union. `Rez` and `Semi` are the *iPhone* layout's labels and
  are present in v1.4.1. Against the iPad scene alone, ipad-06 still shows `DCO 1`/`DCO 2`,
  `Master Volume`, `Amp` and two Global toggles where v1.4.1 has `OSC 1`/`OSC 2`, `Vol` + `Record`,
  `Volume` and three. **None of the six captures shows the version we are porting** — ipad-06 is
  merely the closest.
- **Everything structural lines up.** Every difference found traces to a version change confirmed in
  our storyboard or `S1Parameter.h`: the `Div` knob (`arpSeqTempoMultiplier`), the `Pitch Track` knob
  (`adsrPitchTracking`), `Anti-Aliasing` (`oscBandlimitEnable`), `Record`, `Import`/`TuneUp`, and the
  header's `Web`/`Apps`/`More`. No layout defects.
- **Effects and TouchPad have no reference capture at all** — none of the six shows them. Verified
  against the storyboards and by loading, but there is no photograph to compare against. Recorded.
- Three real findings, all in `docs/06-ui-cross-check.md`:
  - **The bottom container empties if a panel is moved to the top.** Panels are single lazily created
    view controllers, so putting the sequencer on top reparents its view out of the bottom container
    and nothing puts it back. Upstream behaviour, not a defect — but my first screenshot run walked
    the top container through every panel including the sequencer, which blanked the bottom half and
    made the Tunings render look broken. The test now mirrors the app's real arrangement.
  - **Hiding `AKBluetoothMIDIButton` leaves a gap** between `Settings` and `Wheels`; the bar uses
    fixed frames so nothing reflows. Open for P3-4.
  - **The `darkMode` KVC warning is inert** — the storyboard sets `NO` and the class already defaults
    to `.light`, so intended and actual agree. Upstream behaves identically. Our light keyboard is
    correct; `ipad-04`'s dark one is a user setting.
- **Turned the silent failure mode into two tests.** `testEveryStoryboardCustomClassResolves` checks
  all 80 `customClass` references from the storyboard XML — so new controls are covered without
  editing the test — and `testNoStoryboardHardcodesAForeignModule` catches a reintroduced module
  name while correctly tolerating the entries `ibtool` rewrites. Getting that distinction wrong the
  first time would have demanded a pointless mass edit of all twelve files.
- 60 → 62 tests green.

### 2026-09-08 — Session 14: P3-1, the interface runs on macOS
- **All 12 storyboards and 153 Swift files compile inside `SynthOneCore`, and every panel loads.**
  The app launches. `UILoadTests` proves it headlessly — instantiating each panel by the identifier
  `Manager` uses, asserting the concrete type, laying it out, and rendering the result to
  `Renders/ui/*.png`.
- **Why the type assertions matter:** a storyboard class that fails to resolve is *not* an error.
  The nib substitutes a plain `UIView`/`UIViewController`, every outlet is nil, and you find out
  when something force-unwraps. That is what a screenshot would not have told us.
- **The UI is in the framework, and that drove most of the work** (ADR-017). `UIMainStoryboardFile`
  cannot reach a framework storyboard, so the app instantiates it — which is what the AUv3 will do
  at P4-6. Everything stays `internal` behind a `SynthOneApp` façade, because making `Conductor`
  public would have meant `public` on every `@objc` protocol method and would have dragged
  `S1Support` into the generated header again (ADR-014).
- **Eighteen `customModule` attributes had to be corrected** in `Main.storyboard` and
  `Envelopes.storyboard`. Most entries carry `customModuleProvider="target"` and `ibtool` rewrites
  them to the compiling target's module; eighteen hardcode `AudioKitSynthOne` / `AudioKit` /
  `AudioKitUI`. Those classes genuinely live in `SynthOneCore` now.
- **Four real bugs, each found by actually running the thing:**
  - **`AKTuningTable+NorthIndianRaga.helper` asserts `input.count < masterSet.count - 1`** — not the
    bounds check its own message claims. The master set has 17 entries and the 17-degree Persian
    preset asks for all 17, so it reads `17 < 16` and traps. `assert` vanishes in Release, which is
    why the shipping iOS app never hit it **and every Debug build of the Tunings panel died on
    launch.** Fixed to check what it says; regression test added.
  - **`Tunings+Math.swift` mixes `Float` and `Double`** in one expression. The fourth narrowing bug
    of this shape in the port — the first three were AudioKit's (P1-3); this one is Synth One's own.
  - **My `AKNodeOutputPlot` aborted the app on launch**, tapping a node before the engine had
    attached it. A direct consequence of ADR-015's lazy graph build: upstream created the plot right
    after `AudioKit.output = mixer`, which used to attach immediately. `Conductor` creates it after
    `start()` now, and the plot refuses to tap an unattached node.
  - **`Conductor.start()` was not idempotent** — a second call builds a second graph on a running
    engine and AVAudioEngine aborts. Guarded.
- **`Bundle.main` is the recurring hazard.** Twelve call sites load storyboards, preset banks and a
  test fixture from it; they are framework resources now. `#imageLiteral` is the worst of them
  because it **traps** rather than returning nil — the Touch Pad panel's spark particle took the
  process down. `Bundle.synthOneCore` and `UIImage.synthOne(_:)` exist so the next one has an
  obvious right answer.
- Ported `Conductor.swift` at last (P2-1 deferred it deliberately): `AudioKit.output`/`start()` →
  `S1AudioEngine`, `AKSettings.setSession` → the P2-2 session protocol, IAA and Audiobus commented
  out for P3-2.
- New shims: `Disk` (FileManager, the storage half of P3-3), `AKADSRView` (ported), `AKNodeOutputPlot`
  (written — AudioKit's needs EZAudio), `AKMIDIListener` + `AKMIDIControl` (protocol only; P3-4 does
  the CoreMIDI work), `S1MIDI`, `AKLinkButton`/`AKBluetoothMIDIButton` (both hide themselves).
- **The golden WAVs stayed green throughout**, which is what P2-4 was for: none of this touched the
  DSP, and now that is a fact rather than a belief.
- 53 → 60 tests green; app builds and launches; `auval` passes.
- **Next:** P3-2.

### 2026-09-08 — Session 13: P2-4, the regression safety net — Phase 2 complete
- **20 of Synth One's own presets now render against committed golden WAVs.** `GoldenRenderTests`
  re-renders them every run. Phase 2 and Milestone 2 are done.
- **Chose real presets over invented ones, which meant porting the preset model early.**
  `Preset.swift` and the 100-line mapping extracted from `PresetDataManager.loadPreset()` are Phase 3
  work on paper, but a golden suite built on parameter sets invented for a test would exercise
  patches nobody plays and be thrown away later. All 695 shipped presets in all 13 banks decode.
  Two deviations, both recorded: `init(dictionary:defaults:)` takes its defaults instead of reaching
  into `Conductor.sharedInstance.synth`, and the sequencer fallbacks come from those defaults rather
  than from whatever the previously-loaded preset left behind.
- **Selection was computed, not guessed:** greedy coverage over 23 sonic features across all 695
  presets, then spread so all 13 banks contribute. Covers every filter type, both LFOs and every
  routing in use, arp, sequencer, mono, legato, glide, detune, FM, sub, noise, bitcrush, phaser,
  delay, reverb, autopan, widen.
- **16-bit goldens do not work.** Tried first to halve the size; **four of the twenty presets render
  above full scale** — loud patches through the master compressor, the instrument behaving as
  designed — and integer PCM clamps them. Worst mismatch 1.37, entirely clipping. Float32, 10 MB.
  A golden has to record what the DSP produced, over-full-scale included.
- **Verified the suite actually catches things, rather than assuming it.** Changed one internal LFO
  smoothing constant by 0.24% (`kLFOSmoothHalftime`, 0.0053125 → 0.0053): **17 of 20 failed.** The
  three that passed are the patches with no LFO — the right answer, not a gap. Reverted.
- **Determinism is asserted first**, since a flaky golden suite is worse than none. Two renders of
  the same preset are bit-identical; it holds because each builds a fresh `S1DSPKernel` and
  `sp_create` seeds Soundpipe's RNG to zero, so even the noise presets reproduce exactly.
- Trap worth knowing: **`xcodebuild` does not pass the shell environment to the test runner.**
  `SYNTHONE_WRITE_GOLDENS=1 xcodebuild …` is silently ignored — it has to be
  `TEST_RUNNER_SYNTHONE_WRITE_GOLDENS=1`. `Scripts/write-goldens.sh` gets it right.
- Lifted the offline render loop and the estimators into `Tests/SynthOneTests/Support/`, and moved
  `S1AudioEngineTests` onto it. `S1AudioUnitRenderTests` deliberately still drives the AU by hand —
  rendering without an engine at all was the point of P1-6.
- 49 → 53 tests green; app builds; `auval` passes.
- **Next:** P3-1, compile the UI under Catalyst.

### 2026-09-08 — Session 12: P2-1 to P2-3, the audio path becomes ours
- **P2-1.** `S1AudioEngine` replaces AudioKit's global engine. `AKNode`, `AKPolyphonicNode`,
  `AKMixer` and `AKComponent` ported; `AKSynthOne.swift` ported with **three changed lines** (its
  import, and `Bundle.main` → the framework bundle at 3 sites). 8 new tests: the audio unit we get
  really is our in-process subclass, the graph renders, played notes sound at 440/220/329.63 Hz,
  note off releases, mixer volume reaches the output, and it all works at 48 kHz.
- **Chose an object over a global, on evidence rather than taste.** Reproducing `AudioKit.engine`
  would have kept ~11 call sites unchanged — but counting them showed five are in `Conductor.start()`
  (the code P2-1 replaces), four in Audiobus/IAA (stubbed at P3-2). Almost nothing that survives
  wants a global, and P2-4 renders twenty presets that each need an independent engine. ADR-014.
- **Two things bit that are worth carrying:**
  - **`S1Support` cannot own anything Obj-C can see.** The node layer went there first; because
    `AKSynthOne` is `@objc` and subclasses `AKPolyphonicNode`, Xcode emitted `@import S1Support;`
    into `SynthOneCore-Swift.h` — a module no consumer can resolve, since S1Support is a *static
    library* (ADR-008). The rule now: S1Support is the **value layer** (tables, tunings, settings,
    logging); graph objects live in SynthOneCore. Moved, plus one `@objc` dropped from
    `AKPolyphonicNode.tuningTable`.
  - **`AVAudioEngine.outputNode` blocked for 90 seconds.** Reproducibly, once per process, in the
    test bundle. Timing each call located it exactly: `outputNode` lazily creates the hardware
    output unit, and in a process that cannot get an output device that is a 90-second timeout
    which then succeeds anyway. Configuring an `AVAudioSession` first does not help. Calling
    `enableManualRenderingMode` **before anything touches the engine** means the hardware unit is
    never created: **0.009 s**. The test class went 92.9 s → 2.3 s. `S1AudioEngine` is built around
    this — `output` records, `start`/`startOfflineRendering` build. **ADR-015.** The same rule
    applies to the AUv3 at P4: an extension must never touch `outputNode`.
- **P2-2.** `S1AudioSession` with `S1SystemAudioSession` (app) and `S1HostedAudioSession` (no-op).
  **The no-op is the default**, deliberately: forgetting to configure the standalone app is a silent
  app you notice in a second, while forgetting to suppress it in the plugin is a bug in someone
  else's DAW you never see. `.allowBluetooth` → `.allowBluetoothHFP` (Catalyst rename).
- **P2-3.** `S1NodeRecorder` taps a node into an `AVAudioFile` and writes WAV directly, which
  deletes AudioKit's whole asynchronous CAF→WAV export step. `AudioRecorder.swift` ported onto it;
  its delegate now hands over a `URL` instead of an `AKAudioFile`, because the single call site
  (`Manager.didFinishRecording`) only ever used `file.url`.
  - Learned in passing: **`installTap` ignores your `bufferSize`** (4,410 frames at 44.1 kHz here)
    and only delivers whole buffers, so a take is short by up to one of them. Inherent to tapping,
    and true of `AKNodeRecorder` too. Exposed as `tapBufferFrames` and asserted, rather than papered
    over with a loose tolerance.
- **`Scripts/validate-au.sh` hardened.** Its `auval -a` poll wedged for 40 minutes with no output —
  same environment as the 90-second stall. It now retries `auval -v` on our component directly, with
  a 120-second bound per attempt, so a hang fails the check instead of hanging the session.
- 40 → 49 tests green; app builds; `auval` passes.
- **Next:** P2-4, the golden WAVs.

### 2026-09-08 — Session 11: P1-6 — the first sound
- **Synth One plays on macOS.** `S1AudioUnitRenderTests` builds `S1AudioUnit` directly, loads the 52
  band-limited wavetables, allocates render resources, sends a note on, and pulls
  `internalRenderBlock` by hand. 10 tests: audible output, fundamental matching the note across four
  octaves, transpose, note-off release, four-voice polyphony checked spectrally, survival of repeated
  allocation, and a WAV written for listening. 22 tests → 32, `auval` still passes.
- **Getting Swift to see the synth was the real work, and STATE's plan for it was half right.** The
  headers did *not* need adding to a `headerVisibility: public` list — XcodeGen already defaults
  every framework header to public, so all 30 (the C++ ones included) were being copied out and
  clang was warning 25 times a build. What was actually missing was the umbrella entry. Three
  further things fell out, all in ADR-012:
  - **Our `AKInterop.h` shim was wrong.** It defined `AK_ENUM` as `NS_ENUM`; AudioKit defines it as
    `enum __attribute__((enum_extensibility(open))) a : int`. Not interchangeable: upstream writes
    `typedef AK_ENUM(S1Parameter) { … } S1Parameter;`, which under `NS_ENUM` expands to a *variable*
    declaration colliding with the typedef. It compiled for five sessions only because `S1Parameter.h`
    was reached exclusively from Obj-C++, where our `__cplusplus` branch was taken. The Swift importer
    parses as plain Obj-C, and it broke immediately. Now matches AudioKit.
  - **`#pragma once` is not an include guard here.** It keys on file identity, and inside the
    framework build these headers are legitimately reached by two paths — the source tree and the
    copied public header — which are different files on disk. Named guards instead.
  - Declared the public surface in `project.yml` (6 headers) and swept the rest to `project`.
    **Order matters:** XcodeGen keeps the first entry matching a file, so the per-file `public`
    entries must precede the directory. Listed after, they are ignored, the framework ships *no*
    public headers, **and the build still succeeds** because Xcode's own header map resolves
    `<SynthOneCore/…>` within the target. Hit this and fixed it.
- **The pitch came back flat, and chasing it was worth the time.** 434.9 Hz for A440, drifting
  431 → 429.5 → 427.9 across allocation cycles. A windowed measurement showed a note struck at t=0
  starting near 295 Hz and gliding up to 440 by ~0.8 s, then holding at 440.1 forever. Cause is
  upstream and exact: `sp_port_init` zeroes its filter state, so every portamento-enabled parameter
  re-ramps from 0 after each `allocateRenderResources`, while `S1NoteState::run` multiplies
  `oscmorph->freq` by `detuningMultiplier` **once per sample**. A multiplicative accumulator fed a
  value below 1 walks the pitch down and back. **Preserved, not fixed** — it is the shipping
  instrument's behaviour — and pinned by its own test. ADR-013.
- Measurement note: the harness estimates pitch by normalised autocorrelation taking the *first*
  strong peak, not zero-crossing counting. The default patch is a sawtooth, which crosses zero many
  times per cycle; and the tallest autocorrelation peak is as likely to be 2T as T.
- Cross-checked the deliverable outside the toolchain entirely: a Python spectral analysis of
  `Renders/p1-6-first-sound.wav` measured the four melody notes at 219.95 / 261.60 / 329.55 /
  439.90 Hz. It also caught the file clipping at full scale, so the audition velocities were lowered
  and a no-clipping assertion added.
- **Next:** P2-1. Also worth weighing: P2-4's golden WAVs are now cheap — the render harness is the
  hard part and it exists.

### 2026-09-07 — Session 1: survey & planning
- Surveyed upstream `AudioKitSynthOne` @ `6466a37`. Inventoried languages, storyboards,
  localizations, parameter count, dependency set, AudioKit API surface.
- Key findings: DSP is portable Obj-C++ over Soundpipe; AudioKit is thin glue, not structural;
  TAAE is already vendored; **the AU parameter tree was never implemented upstream**
  (`///auv3, not yet used` in `S1AudioUnit.h`) — net-new work.
- Strategy: Mac Catalyst for UI fidelity + drop AudioKit + XcodeGen, gated on a Catalyst-AUv3
  spike (P0-4) with a native/SwiftUI fallback track.
- Wrote `CLAUDE.md`, `PORT_PLAN.md`, `STATE.md`, `docs/`. No code written.

### 2026-09-08 — Session 2: foundations
- Owner answered the open questions: GitHub under `badpackets303`, no Developer Program account,
  no Ableton Link. Recorded as ADR-004 and ADR-005; P3-7, P5-2, P5-3 closed or deferred.
- Xcode 26.6 confirmed installed; XcodeGen 2.46.0 installed via Homebrew. `xcode-select` and the
  license agreement still need the owner's password — **the one blocker**.
- Repo created at `~/Developer/SynthOne` (off iCloud) and pushed to the private GitHub repo
  `badpackets303/SynthOneMac`. `upstream/` vendored at the pinned commit,
  `.gitignore` written, first commit landed.
- Surfaced a consequence of dropping the paid account: App Group entitlements need a Team ID, so
  the app↔extension shared-storage design (P3-3) is now an open question to settle during P0-4.
- **Next:** run the P0-4 Catalyst AUv3 spike.

### 2026-09-08 — Session 10: handoff hardening (no code changes)
- Owner asked for the project to be made resumable in a fresh session. Audited what a cold start
  would actually need and closed the gaps.
- **Real gap found:** the AudioKit 4.9.2 clone every port has been made from lived in the *session
  scratchpad* (`/private/tmp/...`), which does not survive. Phases 2–3 still need it for ~15 symbols
  (`AKPolyphonicNode`, the MIDI layer, `AKADSRView`, `AKNodeOutputPlot`, `AKKeyboardView`).
  Added `Scripts/fetch-references.sh`, which clones it pinned to `03fecf80` into a gitignored
  `.references/`. Verified the revision matches and the Phase-3 UI sources are reachable.
  Confirmed nothing in the build depends on it — it is reading material only.
- Rewrote `CLAUDE.md` around a start-of-session quickstart plus a table of the gotchas that each
  cost real time (symbol presence ≠ compatibility, `sp_create` returning 0, `pow2` squaring, the
  stale `oscmorph2d.c` decoy, AudioKit not compiling on modern Swift, the `implementorValueObserver`
  clobber, 77% Catalyst scaling, App Groups).
- Rewrote `docs/04-build-and-test.md` with a **"build settings that are load-bearing"** table — every
  setting that exists because something broke, so a future session does not tidy one away.
- Made `STATE.md`'s next action self-contained: P1-6 now names the file to copy the harness from,
  the headers that must go public, and the wavetable-loading problem it will hit.
- `PORT_PLAN.md` P1-1…P1-5 updated to what actually happened, and risk R-3 annotated as **already
  fired once** (ADR-011) — the argument against deferring P2-4.
- **Fixed a real build break in the process:** the two new `PORTING.md` files were being copied into
  the framework as resources and collided. Added `excludes: ["**/*.md"]`. Caught by rebuilding
  rather than by assuming the docs were inert.
- Verified: 22 tests green, app builds, `auval` passes, 55 wavetables still bundled, no markdown in
  the framework, build self-contained.

### 2026-09-08 — Session 9: P1-5 the DSP kernel compiles on macOS
- Ported the whole Obj-C++ DSP tree. The P1-4 base layer accepted it as designed: `S1DSPKernel.hpp`,
  `S1Parameter.h` and `S1AudioUnit.mm` all keep their `#import "AudioKit/..."` lines verbatim.
  **Total edits to ported DSP sources: 8 lines across 8 files** — 7 vestigial `AudioKit-Swift.h`
  imports (grep-verified as unused; the one apparent `AKPolyphonicNode` use is in a comment) and
  ADR-010's 3 `AKSettings` reads.
- **P1-2's vendoring was wrong, and P1-5 is what proved it (ADR-011).** Canonical Soundpipe has no
  band-limited `sp_oscmorph2d`, and the `oscmorph2d.c` sitting in `upstream/DSP/Kernel/` is a stale
  non-band-limited copy — a red herring P1-2 fell for. AudioKit's real one picks among 13
  band-limited tables per waveform by pitch; **that is Synth One's anti-aliasing**, and the 54
  `BandlimitedWavetables/` JSONs exist to feed it. The stale version compiles and runs, and would
  have aliased audibly with no error anywhere. Re-vendored from AudioKit's fork; the four kernel
  patches made earlier in the session were reverted as no longer needed.
- Lesson recorded in ADR-011: **symbol presence is not compatibility.** Only compiling the real
  client — or comparing rendered audio — settles it. That is the argument for not deferring P2-4.
- Also pulled in: `TPCircularBuffer` (TAAE needs it), `pow2` (**squares**, not 2^x — it is a velocity
  curve, so misreading it would change how the instrument plays), and `gnu11`/`gnu++17` because TAAE
  uses `typeof()`.
- Framework now has 62 `S1DSPKernel` symbols, 32 objects, 55 bundled wavetables. 22 tests green;
  app builds; `auval` passes.
- **Not yet proven: that it sounds right.** No note has been rendered. That is P1-6.
- **Next:** P1-6, the headless render harness.

### 2026-09-08 — Session 8: P1-4 AudioUnitBase — the AU/kernel base layer
- Ported `DSPKernel` (Apple sample), `AKDSPKernel`, `AKSoundpipeKernel`, `AKOutputBuffered`,
  `BufferedAudioBus` and `AKAudioUnit` from AudioKit 4.9.2.
- Deliberate layout choice: headers live in `AudioUnitBase/AudioKit/` and that directory is on the
  header search path, so **P1-5's kernel sources keep their `#import "AudioKit/..."` lines verbatim**.
  Public framework headers are the exception — Xcode flattens them, so they use `<SynthOneCore/...>`.
- **Another upstream bug found:** `AKDSPKernel::init` reads `sampleRate = sampleRate` — a
  self-assignment, so the member never updated. Masked in practice because `sp->sr` is set separately,
  but `getSampleRate()` was stale after any rate change. Fixed, with a regression test.
- **ADR-010**: `AKSettings`' three DSP-facing scalars are backed by C storage. The Swift class is in a
  static library and has no usable Obj-C header; promoting `S1Support` to a framework would add a
  binary for the AU extension to embed, which ADR-008 avoided. Swift call sites are unchanged.
- Also confirmed `soundpipeextension.h` need not be reproduced — it declares only `sp_oscmorph2d`,
  which our generated `soundpipe.h` already covers, closing that loop from P1-2.
- Proof is `S1TestToneAudioUnit`, built as a structural rehearsal for `S1AudioUnit`: same inheritance,
  same `BufferedOutputBus`, same render-block shape. It renders 440 Hz to ±3 Hz, is exactly silent
  when gated off, and survives three allocate/deallocate cycles.
- Noted for P4-3: `allocateRenderResources` **replaces** the parameter tree's `implementorValueObserver`
  — upstream behaviour, preserved, and exactly the kind of thing that will look like a bug later.
- 22 tests green; app builds; `auval` still passes.
- **Next:** P1-5, port the DSP kernel.

### 2026-09-08 — Session 7: P1-3 S1Support — AudioKit glue replaced
- Measured the real surface first: `AKSettings` needs only 8 members (`bufferLength` alone is 19 of
  the 29 uses); `AKTable` must be a **Codable class** because the band-limited wavetables are JSON;
  `AKTuningTable` drags in the whole Microtonality folder (9 files, ~1,000 lines) because
  `Tunings+DefaultTunings.swift` calls the Wilson/Persian preset library.
- Ported `Microtonality/` + `AKTable.swift` + 3 helper fragments from AudioKit 4.9.2 (MIT, headers
  intact). Wrote `AKLog`, `AKSettings`, `AKTypes`, `AKInterop.h` ourselves.
- **Finding: AudioKit 4.9.2 does not compile under a modern Swift.** Three integer/floating-point
  narrowing errors. The worst is `exp2((noteNumber - 69) / 12)` in `AKTuningTableBase` — integer
  division; a careless fix (casting only the result) would collapse 128 notes onto ~11 frequencies.
  Each fix has a regression test. This retroactively strengthens ADR-002: keeping AudioKit was never
  actually an option.
- **ADR-009**: ported code keeps its `AK` names, so ~190 call sites port untouched and the
  `upstream/` diff stays about real changes. `SynthOneCore` re-exports `S1Support`, so porting a
  file means changing `import AudioKit` to `import SynthOneCore` and nothing else.
- 16 tests green: 12-TET correctness, 19-TET, Scala import of a 5-limit just major scale checked
  against exact ratios, and `AKTable` decoding a real shipped 4,096-point wavetable from `upstream/`.
- Full app still builds and **`auval` still passes** — the per-phase regression check from ADR-008
  doing its job.
- **Next:** P1-4, `S1AudioUnitBase`.

### 2026-09-08 — Session 6: P1-2 Soundpipe vendored and behaviourally tested
- Vendored from **canonical** Soundpipe @ `3efb43bd` — AudioKit's fork (`AudioKit/soundpipe`) does
  not exist. Verified every symbol the kernel calls is present upstream *before* copying, including
  `sp_vdelay_reset` and `sp_gen_sine`, the two most likely to have been AudioKit additions. Both
  are stock.
- Needed two modules the inventory didn't list, found by following build errors: **`base`**
  (`sp_auxdata_*`, needed by delay/revsc/vdelay) and **`randmt`** (`ftbl.c` calls `sp_randmt_*`).
- `oscmorph2d` is Synth One's own module, not Soundpipe. Ported it out of `upstream/` and moved its
  inline declarations into a header — otherwise the typedef is defined twice, which is a hard error.
  That is the only modification to any ported code; upstream `.c`/`.h` are byte-for-byte pristine.
- Wrote `Scripts/assemble-soundpipe-header.sh`: upstream ships no `soundpipe.h`, its Makefile
  concatenates unguarded header *fragments* in dependency order. Reproduced for our subset.
- **Trap found the hard way:** `SP_OK` is 1 but `base.c`'s `sp_create` returns **0**. Cost one red
  test. Documented in `VENDORING.md` and in a comment at the call site.
- Tests assert behaviour, not linkage: 440 Hz oscillator accurate to ±2 Hz, moogladder attenuating
  8 kHz below a tenth of the 100 Hz level, ADSR reaching sustain then releasing, oscmorph2d at pitch.
- Verified Release build is universal **arm64 + x86_64**; undefined externals are libc/libm only.
- **Next:** P1-3, the `S1Support` shims.

### 2026-09-08 — Session 5: P1-1 target graph builds; AU validates from day one
- Wrote `project.yml`: `Soundpipe` + `S1Support` (static) → `SynthOneCore.framework` →
  `SynthOne.app` (Catalyst) + `SynthOneAU.appex` (aumu/aks1/BP03), plus `SynthOneTests`.
- Placeholder sources throughout, but the *link path is real*: a Swift test calls into the vendored
  C through a module map and passes, so P1-2 cannot be surprised by module wiring.
- Two judgment calls recorded as **ADR-008**: static libraries rather than frameworks (nothing extra
  for the AU extension to embed or sign, which matters more than usual under ad-hoc signing), and
  shipping a structurally complete AU stub at P1-1 so **`auval` becomes a per-phase regression
  check** instead of a cliff at P4-7. The stub passes `auval` today.
- Fixed a latent bug carried over from the spike: XcodeGen's `options.deploymentTarget` is ignored
  when `supportedDestinations` is used, so the spike had silently built with `minos 26.5`. Now set
  explicitly — the app reports `minos 14.0`.
- Added `Scripts/build.sh` and `Scripts/validate-au.sh`; `docs/04-build-and-test.md` now has real
  commands rather than placeholders.
- **Next:** P1-2, vendor the 21 Soundpipe modules.

### 2026-09-08 — Session 4: P0-5 done from App Store; Phase 0 complete
- Owner asked whether upstream ships screenshots. It does not — only a TouchPad texture and
  Crowdin diagrams, plus one low-res marketing GIF with text overlaid across the UI.
- Pulled clean 2048×1535 iPad captures from the live App Store listing instead. **No iPad needed.**
- Found two things worth knowing: the App Store app is **v1.9.2 (2026-01)** while our source is
  **v1.4.1 (2022)**; and the six screenshots span multiple app versions — label comparison against
  `Generators.storyboard` shows only `ipad-06` matches our source (`Global`/`Resonance`/
  `Semitones`/`Volume` vs the older `Main`/`Rez`/`Semi`/`Vol`).
- Recorded that **the storyboards, not the screenshots, are the authoritative layout spec** — we
  compile the same 12 files, so screenshots only settle rendered appearance and the ADR-007 idiom
  question.
- **Phase 0 complete. Next:** P1-1, the XcodeGen target graph.

### 2026-09-08 — Session 3: P0-4 spike passed, Track A confirmed
- Built a throwaway Catalyst app + AUv3 instrument (`Spikes/P0-4-CatalystAU/`), ad-hoc signed,
  no developer account. **`auval` validation succeeded**; the AU loads **both** in-process and
  out-of-process and renders audio in both; a **UIKit storyboard loads inside the extension**
  (proved in-band via the AU parameter tree, since the remote view could not be screenshotted).
- **ADR-001 resolved: Track A (Mac Catalyst).** Track B — the SwiftUI rewrite — is withdrawn.
  Risk R-1 is closed; it was the largest risk in the plan.
- Two findings recorded: **ADR-006** — App Groups need a Team ID, so P3-3 is re-scoped to a
  `~/Music/Audio Music Apps/` shared location; **ADR-007** — Catalyst renders the iPad UI at
  exactly 77%, so the idiom choice becomes an explicit P3-1 decision, not a silent default.
- Toolchain fixed along the way: `xcode-select`, license, and `xcodebuild -runFirstLaunch`.
- **Next:** P0-5 reference screenshots, then P1-1.
