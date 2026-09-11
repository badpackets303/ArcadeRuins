# UI cross-check against the App Store captures (P3-1)

Our rendered UI compared, panel by panel, against `docs/reference/appstore/`. Renders are in
`Renders/ui/` (gitignored — regenerate with the test suite). The captures are AudioKit's App Store
screenshots and are not included in the public repository.

## ⚠️ First, a correction to the P0-5 note

`docs/reference/README.md` says *"`ipad-06.png` is the shot whose labels match our source"*, inferred
from `Global` / `Resonance` / `Semitones` / `Volume` appearing in `Generators.storyboard`.

**That inference does not hold.** `Generators.storyboard` contains **two scenes** — `GeneratorsPanel`
(iPad) and `iPhoneGeneratorsPanel` — and grepping the file finds the union of both label sets. The
abbreviations the note attributes to "older shots" (`Rez`, `Semi`) are simply the **iPhone** layout's
labels, present in v1.4.1 and irrelevant to an iPad capture.

Comparing against the iPad scene alone:

| | v1.4.1 iPad scene | ipad-06 | ipad-01 / 03 / 04 |
|---|---|---|---|
| Oscillator sections | `OSC 1` / `OSC 2` | `DCO 1` / `DCO 2` | `DCO 1` / `DCO 2` |
| Master volume | `Vol` + a `Record` button | `Master Volume`, no Record | `Master Volume`, no Record |
| Row-2 headers | `Sub Volume Mix FM Noise Global` | `Sub Volume Mix FM Noise Global` | `Sub Vol Mix FM Noise Main` |
| Row-2 knob labels | `Volume` / `OSC 1` / `OSC 2` / `OSC 1-2` | `Amp` / `DCO 1` / `DCO 2` / `DCO 1-2` | `Amt` / `DCO 1` / `DCO 2` / `DCO Mix` |
| Global toggles | `Anti-Aliasing`, `Widen`, `Arp` | `Widen`, `Arp/Seq` | `Widen`, `Arp/Seq` |

So **ipad-06 is the closest of the six, but it still predates v1.4.1.** *None* of the captures shows
the version we are porting. Ranked oldest to newest: `ipad-01` ≈ `ipad-03` ≈ `ipad-04` ≈ `ipad-05`
(`Vol`/`Main`/`Amt`) → `ipad-02` → `ipad-06` (`Volume`/`Global`) → **our v1.4.1**.

The practical consequence is unchanged and worth restating: **the storyboards are the specification.**
Our render is produced by compiling those exact files, so where it differs from a capture, the
capture is the thing that is out of date.

## Panel by panel

### Generators — `Renders/ui/06-sequencer-over-generators.png` vs `ipad-04.png`

Same arrangement, so directly comparable. Everything structural lines up: the four waveform buttons
per oscillator, the semitone/detune knobs, the `Filter ▶ Low Pass` header with Frequency and
Resonance, the Glide knob with Mono/Legato beneath, the six-column second row, and the bpm stepper.

Every difference traces to a version change, each confirmed in our storyboard or `S1Parameter.h`:

| Difference | Explanation |
|---|---|
| `OSC` vs `DCO` naming throughout | renamed after the captures |
| `Vol` knob + `Record` button where the capture has a larger `Master Volume` knob | the record button is `Record` in our storyboard; recording is P2-3's `AudioRecorder` |
| Three Global toggles vs two | `Anti-Aliasing` was added — it is `oscBandlimitEnable`, and the 54 band-limited wavetables exist to serve it (ADR-011) |
| Header has `Web`, `Apps`, `More`; dice moved right of the display | accumulated header changes; `ipad-06` already shows `Web`/`More` |

### Sequencer — same render vs `ipad-04.png` / `ipad-02.png` / `ipad-05.png`

Identical structure: the toggle, `Interval` knob, `Octave` stepper, three-way `Style` control, the
Arp/Seq switch, and a 16-column grid of value field → vertical slider → note-on button, grouped 4-4-4-4.

Two differences: `Seq Steps` is now `Steps`, and there is a new `Div` knob at the right end — that is
`arpSeqTempoMultiplier`, present in `S1Parameter.h`.

### Envelopes — `Renders/ui/02-envelopes.png` vs `ipad-05.png`

Two envelope plots side by side with knob rows beneath, the filter side carrying the extra `Env Amt`
control in its highlighted pill. The ported `AKADSRView` draws both in the reference's style — the
filter envelope stroked, the amplitude envelope filled.

Differences: the titles read `Filter Envelope` / `Amplitude Envelope` rather than
`Envelope - Filter` / `Envelope - Amp`, and the amplitude side has a fifth knob, `Pitch Track`
(`adsrPitchTracking`, the highest-numbered parameter in `S1Parameter.h` and therefore the most
recently added).

### Tunings — `Renders/ui/05-tunings.png` vs `ipad-02.png`

Tuning list on the left, Wilson pitch wheel on the right, `Master Tuning` knob and dice on the right
rail. Ours adds `Import` and `TuneUp` buttons below `Reset` — TuneUp is a v1.4.1 feature
(`Tunings+TuneUp.swift`). The pitch wheel labels ratios (`1`, `967`, `1/967`) where the capture shows
decimals (`0.0000`, `0.0833`); the label mode changed between versions.

Only one table view is visible in both. That is correct: `tuningTableView` and `tuningBankTableView`
share `tuningContainerView.bounds` and are swapped, not shown side by side.

### Effects, TouchPad — **no reference capture exists**

None of the six App Store screenshots shows either panel. They are verified against the storyboards
and by loading (`UILoadTests`), but there is no photograph of the shipping app to compare them to.
If a stronger reference is ever wanted, the App Store listing is still live and Apple may have added
shots since P0-5.

## Real findings

1. **The bottom container empties if a panel is moved to the top.** Each panel is a single lazily
   created view controller, so `switchToChildPanel(.sequencer, isOnTop: true)` reparents the
   sequencer's view out of the bottom container and nothing puts it back. **This is upstream
   behaviour, not a porting defect** — but the first screenshot run walked the top container through
   every panel including the sequencer, which left the bottom half blank and made the Tunings render
   look broken. The screenshot test now mirrors the app's real arrangement.

2. **Hiding `AKBluetoothMIDIButton` leaves a gap in the bottom bar.** The layout uses fixed frames,
   so nothing reflows into the space between `Settings` and `Wheels`. ADR-004's `AKLinkButton` is
   hidden in the header the same way but sits at the end of a row, where it does not show.
   **Open for P3-4**: either repurpose the button (macOS pairs Bluetooth MIDI in Audio MIDI Setup,
   which the app could open) or close the gap.

3. **The `darkMode` KVC warning is inert.** `Main.storyboard` sets `darkMode = NO` as a runtime
   attribute, and `KeyboardView.darkMode` is a Swift enum, so KVC cannot set it and logs a failure.
   The class already defaults to `.light`, so the intended value and the actual value agree — and
   upstream's own build behaves identically. The light keyboard in our renders is correct;
   `ipad-04`'s dark keyboard is a user setting, not the default.

## What is now checked automatically

`UILoadTests` covers the failure modes that are otherwise silent:

- every custom class named by any storyboard resolves at runtime (80 references, derived from the
  storyboard XML so new controls are covered without editing the test);
- no storyboard **hardcodes** a foreign module — while correctly tolerating the entries that carry
  `customModuleProvider="target"`, which `ibtool` rewrites;
- every panel instantiates as its intended concrete type, loads and lays out;
- all twelve storyboards and eight localisations are in the framework bundle.
