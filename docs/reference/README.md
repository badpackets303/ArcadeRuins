# Reference material for parity work (P0-5)

## The short answer on screenshots

**The upstream repository contains no screenshots.** Its only images are `spark.png` (a TouchPad
particle texture) and three Crowdin translation-workflow diagrams. The README embeds a single
*external* marketing GIF (`audiokitpro.com/images/ak2.gif`, still live) — 768×498, inside an iPad
bezel, with large marketing text overlaid across the UI. Not usable as a pixel reference.

Full-resolution references were instead obtained from the **App Store listing**, which is still
live: `itunes.apple.com/lookup?id=1371050497` returns iPad screenshot URLs, and swapping the
`552x414bb.png` suffix for `2048x1536bb.png` yields clean, unframed, full-resolution captures of
the real app. Those are in `appstore/`.

## ⚠️ Two caveats that matter

**1. The shipping app is ahead of our source.** The archived repo is **v1.4.1** (`MARKETING_VERSION`
in the pbxproj, commit `6466a37`, 2022-03-14). The App Store listing is **v1.9.2, updated
2026-01-22**. Five minor versions of fixes and changes exist in the shipping binary that are *not*
in the source we are porting. We are porting 1.4.1; that is the correct and only available baseline,
but do not treat the App Store app as the specification.

**2. The six screenshots are not all from the same version.** Apple retains old marketing
screenshots. Comparing control labels against our source's `Generators.storyboard`:

| Label in source storyboard | Matching shots | Older shots show |
|---|---|---|
| `Global` | ipad-06 | `Main` |
| `Resonance` | ipad-06 | `Rez` |
| `Semitones` | ipad-06 | `Semi` |
| `Volume` | ipad-06 | `Vol` |

**`ipad-06.png` is the closest of the six**, but see the correction below.

> **⚠️ Corrected at P3-1.** This inference does not hold. `Generators.storyboard` contains **two
> scenes** — iPad and iPhone — and grepping the file returns the union of both label sets. `Rez` and
> `Semi` are simply the *iPhone* layout's labels, present in v1.4.1. Compared against the iPad scene
> alone, ipad-06 still shows `DCO 1`/`DCO 2`, `Master Volume`, `Amp` and only two Global toggles,
> where v1.4.1 has `OSC 1`/`OSC 2`, `Vol` + `Record`, `Volume` and three (`Anti-Aliasing` was added).
> **None of the six captures shows the version we are porting.** Full comparison in
> `docs/06-ui-cross-check.md`. The others show an earlier UI. Use them
for layout and visual style, but trust the storyboard over any screenshot when they disagree.

## The authoritative reference is the storyboards

For Track A (Mac Catalyst) we compile the *same 12 storyboard files* the original shipped. So the
storyboards in `upstream/AudioKitSynthOne/**/Base.lproj/*.storyboard` are the specification for
layout — exact frames, exact control classes, exact hierarchy. Screenshots serve a narrower purpose:

- confirming rendered appearance (colours, custom-drawn knobs, textures) that XML doesn't convey
- judging the ADR-007 idiom question (77% iPad-scaled vs 100% Mac) against a real rendering
- catching anything Catalyst silently substitutes or mis-renders

## Coverage

| Panel | Reference |
|---|---|
| Header | all shots |
| Generators | ipad-01, 03, 04, 06 |
| Sequencer | ipad-02, 04, 05 |
| Envelopes | ipad-05 |
| TouchPad | ipad-01 |
| Tunings | ipad-02 |
| Presets | ipad-06 |
| Keyboard / wheels | ipad-03 (pitch + mod wheels visible), all |
| **Effects** | **none — storyboard only** |
| **About** | **none — storyboard only** |
| **MailingList** | **none — storyboard only** (candidate for removal anyway) |
| **Dev** | **none — storyboard only** (debug-only panel) |

Eight of twelve panels have a rendered reference. The four without are either trivial (About),
slated for removal (MailingList), debug-only (Dev), or knob-and-label panels whose storyboard is a
sufficient spec (Effects). No iPad hardware is required.

## Files

- `appstore/ipad-01.png` … `ipad-06.png` — 2048×1535, from the App Store listing. They are AudioKit's
  screenshots, with AudioKit's wordmark, and are **not included in the public repository**. The
  lookup above fetches them again.
- Marketing GIF deliberately not committed: low resolution, text overlay, no added value
