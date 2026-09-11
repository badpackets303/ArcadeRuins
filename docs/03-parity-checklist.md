# Parity checklist

The operational definition of "same UI and functionality". References live in `docs/reference/` —
note that the **storyboards are authoritative** for layout and the App Store screenshots only settle
rendered appearance; see `docs/reference/README.md` for the version caveats. Sign off each row as
the port lands. Nothing ships at a
milestone with unsigned rows in its scope.

Legend: `[ ]` not started · `[~]` partial · `[x]` verified against reference · `[–]` intentionally
dropped (needs an ADR)

## Rendering (ADR-007)

- [ ] **Catalyst idiom decided** — iPad-scaled (77%, layout preserved exactly, renders smaller) vs
      Optimize-for-Mac (100%, true size, Mac control metrics). Compare both against the P0-5
      reference screenshots before committing.

## Panels (12 storyboards)

Layout was cross-checked against the App Store captures at P3-1 — see `docs/06-ui-cross-check.md`.
`[~]` below means *renders correctly and matches the storyboard*; the rows stay open until the
controls are also driven (P3-5) and their behaviour confirmed.

- [~] **Main** — renders. Window sizing done (P3-6) and resizable by scaling (P3-6b, ADR-019)
- [~] **Header** — renders; preset name and nav wired. MIDI activity now has a live CoreMIDI
      source (P3-4) but has not been watched under real input
- [~] **Generators** — renders; matches `ipad-04` structurally, differences all v1.4.1 additions
- [~] **Envelopes** — renders; `AKADSRView` draws both envelopes in the reference's style. Fifth
      `Pitch Track` knob is a v1.4.1 addition
- [~] **Effects** — renders. **No App Store capture exists for this panel** — storyboard only
- [~] **Sequencer** — renders; 16-column grid matches the captures. New `Div` knob is
      `arpSeqTempoMultiplier`, a v1.4.1 addition
- [~] **TouchPad** — renders. **No App Store capture exists for this panel** — storyboard only
- [~] **Tunings** — renders; matches `ipad-02`. `Import`/`TuneUp` buttons and ratio-style pitch
      labels are v1.4.1 additions
- [ ] **Presets** — bank list, preset list, categories, favorites, search, edit/rename/reorder,
      import/export, factory bank restore
- [ ] **About** — credits, links, version
- [ ] **MailingList** — *(candidate for removal — needs ADR)*
- [ ] **Dev** — developer panel, keep behind a debug flag

## Controls (must feel identical)

- [~] `Knob` — drag, taper, double-click-to-default, ⌥ fine drag and scroll wheel all covered by
      tests (P3-5). Value readout not yet checked against the reference
- [ ] `Stepper` / `TempoStepper` — increment/hold-to-repeat
- [ ] `ToggleButton`, `ToggleSwitch`, `SynthButton`, `CallbackButton` — visual states
- [ ] `VerticalSlider` (sequencer)
- [ ] `MorphSelector`, `LFOWavePicker`, `FilterTypeButton`, `ArpDirectionButton`
- [ ] `ModWheel`, pitch bend
- [ ] `KeyboardView` — 12-ET and microtonal drawing modes, key size, octave range, latch
- [ ] `AKTouchPadView` / `AKVerticalPad` — pad tracking and release behavior
- [~] `AKADSRView` — **ported** at P3-1 and renders both envelopes in the reference's style.
      Drag editing not yet driven
- [x] `AKNodeOutputPlot` — **written** at P3-1 (AudioKit's needs EZAudio). Taps the synth node and
      draws; starts on `engineDidStart`

## Input (Risk R-2 — the honest fidelity gap)

33 files handle `UITouch`. macOS has one pointer where iPadOS had ten. Each of these needs a
deliberate decision, not a default:

- [~] On-screen keyboard: single-pointer play works; **Hold** is the latch affordance and is
      upstream's own. Chords by pointer alone still need Hold — the typing keyboard is the real
      answer, below
- [x] **Computer keyboard → notes** — GarageBand/Logic Musical Typing (`A W S E D F T G Y H U J K`,
      `Z`/`X` octave, `C`/`V` velocity). New feature. Routed through `keyboardView.pressAdded`, so
      hold, mono and key highlighting behave the same whatever played the note.
      **`Z`/`X` and the `Octave:` stepper are the same control** — the app must not have two octaves
- [x] Touch pads: single-pointer tracking verified; latch behaviour unchanged from upstream (the
      indicator returns to centre on release). No code change needed
- [x] **Knobs**: click-drag, **scroll wheel** (`allowedScrollTypesMask`, restricted to indirect
      events so it cannot fight the drag), **⌥ fine drag**, double-click to default
- [x] Right-click → MIDI learn — **not needed**: MIDI learn is a global mode toggled from the
      header, and assignment is a plain click on the control. Already single-pointer
- [–] Trackpad gestures — nothing in this UI maps cleanly to pinch or rotate. Scroll on knobs is
      the one that does, and it is done
- [ ] Text entry in preset rename / Scala import — untested with a hardware keyboard

## Functionality

- [ ] All 150 `S1Parameter` values reachable and correct
- [ ] Factory preset banks load; sound matches reference (golden-WAV, P2-4)
- [ ] User preset save / rename / reorder / delete / import / export
- [ ] Tunings: all bundled tunings, Scala import, TuneUp inter-app *(iOS-only — needs ADR)*
- [ ] Arpeggiator + sequencer: all directions, octaves, rates, tempo sync
- [ ] MIDI in: notes, velocity, pitch bend, mod wheel, sustain, CC mapping / MIDI learn
- [ ] MIDI out *(if upstream has it)*
- [ ] Audio recording / export
- [ ] Polyphony limits, mono/legato/glide modes
- [~] Panic / all-notes-off — wired to the menu bar and ⌘. (P3-6); the header's Panic button is
      upstream's and not yet driven
- [ ] Settings persistence across launches
- [ ] All 8 localizations render without truncation

## Plugin-only (net-new; no upstream reference exists)

- [ ] All 150 parameters exposed and automatable, with correct ranges and tapers
- [ ] UI reflects host automation live; host records UI moves
- [ ] Session state saves and restores (`fullState`)
- [ ] Factory presets visible to the host
- [ ] Host tempo/transport drives arp, sequencer, tempo-synced LFOs and delay
- [ ] Multiple simultaneous instances
- [ ] Offline / faster-than-real-time bounce produces correct audio

## Intentionally dropped (each needs an ADR)

- [–] Audiobus (iOS-only) — behind `S1PlatformServices`, P3-2
- [–] OneSignal push notifications — unreachable under Catalyst; upstream already `#if`s it out
- [–] AppCenter analytics — never ported; the call site was in an app-level file we do not use
- [–] StoreKit review prompt — behind `S1PlatformServices`, P3-2. No listing to review (ADR-005)
- [–] Launch-count prompts — the rating alert (5th launch), review request (every 50th), "Synth One +
      Share One!" card (every 7th) and push request (9th, every 75th) no longer fire, at the owner's
      request (ADR-042). The storyboards and functions remain
- [x] Bluetooth MIDI button — **opens Audio MIDI Setup** instead of hiding (P3-4), which also
      closed the gap it left in the bottom bar
- [x] Ableton Link — dropped (ADR-004)
- [–] `AKLinkButton` and the Link UI — hidden, per ADR-004
