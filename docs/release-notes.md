# Release notes

Versions are `MARKETING_VERSION` in `project.yml`; both products carry the same number.

## 0.5.0 — the cabinet comes alive (2026-09-17)

The DSP, the 150 parameters and the presets are unchanged.

- **Cabinet replaces Neon Ruins** (ADR-060). Settings ▸ Skin is now Studio | Cabinet. Cabinet keeps
  Neon Ruins' colours and glowing controls; a saved Neon Ruins choice opens Cabinet.
- **The cabinet's joystick works** (ADR-061). Drag it up for the mod wheel, lean it sideways to bend
  the pitch; let go and it springs back.
- **And so do its two red buttons** (ADR-062). The left one cuts the power: the panels flicker out at
  random, over about eight seconds, until the synth is dark and grey. The right one brings them back.
  It still plays in the dark.

## 0.4.0 — the Cabinet skin (2026-09-17)

One addition to the desktop layout (ADR-059). The DSP, the 150 parameters and the presets are
unchanged, and the classic layout and the other two skins look as they did.

- **Cabinet, a third skin.** Settings ▸ Skin ▸ Cabinet (or View ▸ Skin), with Layout set to
  Desktop; it applies at the next launch. The whole window is a painted arcade cabinet: the section
  frames and titles, the header, the wordmark and the Save, Panic, Settings and Presets buttons are
  artwork, and Neon Ruins' controls — one neon colour per section — sit in the frames. The preset
  name reads in the painted display, the painted arrows step through presets, **Presets** opens
  the browser, the wordmark opens About, and the scope runs in the cabinet's screen.
- To fit the painted frames, the oscillators, the envelopes, the LFO block and Voice draw a size
  smaller under this skin. Every control, binding and shortcut is the same.
- **LFO Rate and Amount no longer shift as they turn**, under every skin. A rate's readout changes
  length ("1/8 note", "1/4 triplet") and its cell used to grow with it, pushing its neighbours.

Known: the painting stretches with the window, so a window far from 1440×900's shape distorts it
slightly.

## 0.3.0 — the desktop layout, skins and an icon (2026-09-14)

Everything since 0.1.0 in one release: Phases 6, 7 and 8 of the port (ADR-045 to ADR-053). The DSP,
the 150 parameters and the presets are unchanged, and a preset saved by 0.1.0 opens identically.
0.2.0 was prepared and never released; its work is folded in here.

**Two interfaces, and you choose**

- **The classic interface — Synth One's own iPad layout — is what a fresh install opens with**, as
  it did in 0.1.0.
- **A one-screen desktop layout** designed for a Mac window is a setting away. Every section is
  visible at once: oscillators, mix, filter and voice; the envelopes and LFOs; reverb, delay,
  phaser, bitcrusher and auto pan, and master; the arpeggiator/sequencer with tall step faders, and
  the XY pads.
- **Settings ▸ Layout** switches between them, in the app and in the plugin, and the change lands at
  the next launch. View ▸ Classic Layout does the same in the app.

**New in the desktop layout**

- **Readouts in real units** under every knob — Hz, ms, s, %, semitones — and the LFO, delay and
  auto-pan rates as note values when tempo sync is on.
- **The preset browser drops down from the toolbar.** Click the preset name, or ⌥⌘P, or View ▸
  Preset Browser; click anywhere else or press Escape to put it away. ⌘F searches. It carries the
  classic browser's categories, banks, favourites, notes and its New · Import · Reorder · Import
  Bank · New Bank buttons.
- **Filter type** as a Low / Band / High picker; **tempo sync** as a switch in the LFO header;
  **mod targets** as a grid; a **Master** section with volume, anti-alias, widen and the arp/seq
  switch.
- **LFO & Mod Targets in two columns** — each LFO with its wave picker, rate and amount on the left,
  the twelve targets as a grid on the right — and larger knobs throughout.
- **Dark, textured sections** drawn in code; knobs, switches, steppers, faders, wave pickers and
  step buttons redrawn for the pointer. Every control keeps its binding, MIDI learn and VoiceOver.
- **About, the preset and bank editors and Search** open as centred cards over the layout.
- **Plugin**: the same layout at 1440×900 in the host's window, with the editors, About, Search and
  Tunings as overlays inside the plugin view, and the scope fed from the render thread.

**Skins**

- **Settings ▸ Skin, or View ▸ Skin ▸ Studio | Neon Ruins**, applied at the next launch. Studio is
  the dark-grey default.
- **Neon Ruins**: each section in its own neon — orange, mint, pink, violet, gold or cyan — with a
  hot two-point border and bloom over near-black, worn-metal panels; knobs with a halo and a white
  pointer; lit fader tracks; cyan readouts; a sunset behind the toolbar with the Arcade Ruins
  wordmark lit; and a magenta floor that shows through the play bar. Drawn in code — no artwork but
  the wordmark — so it is crisp at any size.
- A skin changes only how things look. Every control, section, size, binding and shortcut is the
  same under each, and a test holds every section to the same frame under both.
- Skins dress the desktop layout; the classic one is left as it was.

**Elsewhere**

- **The app has an icon** — the Arcade Ruins keyboard. Every build before this one showed the
  generic placeholder in the Dock and the Finder.
- **Settings works in the plugin**, which has no menu bar of its own: layout and skin are chosen
  there, in a host, for the first time.
- The on-screen keyboard is not in the desktop layout. Play from MIDI or the computer keyboard
  (A–K play, Z/X octave, C/V velocity); hold, mono, MIDI learn, transpose, octave and the wheels are
  in the play bar. The classic layout keeps its keyboard.
- The desktop window's minimum size is 1440×900, and it and its sheets are pinned to Dark.
- Version strings: the app and plugin report the marketing version (0.1.0 reported "1.0").
- ⌘F is Search Presets; the system Find menu is gone.

**Fixed**

- The Steps/Octaves steppers, the tempo stepper and the arpeggiator direction control hit-tested
  against rectangles fixed for their storyboard sizes, so at other sizes the plus button and the
  third direction cell were partly unreachable.
- LFO 2's chip hit-tested at a constant 100 points, so at any other width it was nearly
  unclickable.
- The XY pad set a NaN layer position when a hosted synth's dependent parameters were read before
  render resources existed, which could take the plugin down in a host that builds the view first.
- Custom-drawn controls redraw when their bounds change instead of stretching the previous bitmap.
- The selected preset row's rename, duplicate and share buttons were off the right edge of the
  desktop browser's rows; only the star showed.

**Known**

- The plugin keeps its own layout and skin, separate from the app's, and its Settings popover has
  not yet been opened inside Logic: it anchors to a view in the host's window, and Apple's share
  sheet failed in exactly that position (ADR-044).
- The Logic Pro screenshot in the README is from 0.1.0.
- The oscillator morph selector keeps its classic drawing under both skins.

## 0.1.0 — the port (2026-09-11, tag `v0.1.0-classic-ui`)

Phases 0–5. AudioKit Synth One's DSP, interface and 695 factory presets on macOS: a Mac Catalyst
standalone at the Mac idiom's 100%, and an AUv3 instrument (`aumu` / `ruin` / `BP03`) with all
150 parameters host-automatable, host tempo and transport for the arpeggiator and sequencer, session
state, factory presets offered to the host, and presets, banks and favourites shared between the
app and the plugin. No AudioKit dependency, no CocoaPods, no Ableton Link, Audiobus, Inter-App Audio,
analytics or push notifications. Rebranded from AudioKit; the interface layout was preserved exactly.
