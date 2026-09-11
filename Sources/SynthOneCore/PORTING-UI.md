# The UI — porting record (P3-1)

153 Swift files and 12 storyboards, brought across from `upstream/AudioKitSynthOne` into
`SynthOneCore` with the directory layout preserved so `diff upstream/ Sources/` stays readable.

**The UI lives in the framework, not the app.** That is what lets the AUv3 host the same panels at
P4-6, and it is the source of most of the changes below: upstream loads everything from
`Bundle.main`, and `Bundle.main` is now the app, which contains none of it.

## Mechanical changes, applied across the tree

| Change | Files | Why |
|---|---|---|
| `import AudioKit` → `import S1Support` | 23 | ADR-009. These files are inside `SynthOneCore` now, so they import the value layer directly rather than through the framework's re-export |
| `import AudioKitUI` deleted | 3 | `AKADSRView` and `AKNodeOutputPlot` are ours now, in `UI Components/` |
| `import UIKit` added | 31 | Upstream got UIKit transitively — AudioKit re-exported it. `S1Support` is the value layer and does not |
| `import Disk` deleted | 9 | Replaced by `Platform/Disk.swift`, a `FileManager` implementation of the same five entry points |
| `import OneSignal` deleted | 1 | No-op stub in `Platform/PlatformServices.swift` (P3-2) |
| `AudioKit.midi` → `S1MIDI.shared` | 8 | No global engine (ADR-014). `S1MIDI` is a placeholder — **P3-4** builds the real CoreMIDI layer |
| `Bundle.main` → `Bundle.synthOneCore` | 12 | Storyboards, preset banks and the tunings upgrade fixture are framework resources |
| `#imageLiteral` / `UIImage(named:)` → `UIImage.synthOne(_:)` | 4 files | Same reason — and `#imageLiteral` **traps** rather than returning nil |
| `try AKTry { ... }` → `S1AudioSessionProvider.current...` | 2 | `AKTry` was AudioKit's Obj-C exception trampoline. Routed through P2-2's session protocol so the AUv3 cannot touch the host's session |

## Ported from AudioKit / AudioKitUI to fill the gaps

| What | Where | Notes |
|---|---|---|
| `AKADSRView` | `UI Components/` | Pure UIKit, ported unchanged. Four storyboard instances |
| `AKNodeOutputPlot` | `UI Components/` | **Written, not ported** — AudioKit's subclasses `EZAudioPlot`, a whole vendored Obj-C library for one waveform display. Ours taps a node and draws |
| `AKMIDIListener`, `AKMIDIControl` | `MIDI/AudioKit/` | Protocol and message vocabulary only. Nothing delivers events yet — P3-4 |
| `Double.normalized(from:)` / `.denormalized(to:)` | `S1Support/AKHelpers.swift` | The knob taper maths |
| `MIDIByte`, `MIDIWord` | `S1Support/AKTypes.swift` | |
| `AKLinkButton`, `AKBluetoothMIDIButton` | `UI Components/AKStubbedControls.swift` | Both hide themselves. Link is dropped (ADR-004); Bluetooth MIDI pairing has no Catalyst equivalent — **P3-4 should decide** whether to point at Audio MIDI Setup instead |

## Storyboards

All 12 compile into `SynthOneCore.framework/Base.lproj`, with `.strings` for 8 languages.

**Eighteen `customModule` attributes in two storyboards had to be rewritten.** Most entries carry
`customModuleProvider="target"`, which makes `ibtool` substitute the compiling target's module — so
they became `SynthOneCore` on their own. Eighteen did not: `Main.storyboard` hardcodes
`customModule="AudioKitSynthOne"` for `KeyboardView`, `Stepper`, `MIDICell`, `ChannelStepper`,
`SynthButton` and `ToggleSwitch`, and `"AudioKit"` for `AKBluetoothMIDIButton`;
`Envelopes.storyboard` hardcodes `"AudioKitUI"` for `AKADSRView`. Those classes really do live in a
different module now, so the attribute was wrong rather than the code.

The failure mode is worth knowing: a class that does not resolve does **not** error. The nib
substitutes a plain `UIView`/`UIViewController`, every outlet is nil, and you find out when
something force-unwraps. `UILoadTests` checks the concrete types for exactly this reason.

## Bugs found by compiling and loading

- **`Tunings+Math.swift` mixes `Float` and `Double`** in one expression, which modern Swift rejects.
  The fourth narrowing bug of this shape in the port — the first three were AudioKit's (P1-3), this
  one is Synth One's own. `PORT FIX` at the site.
- **`AKTuningTable+NorthIndianRaga.helper` asserts `input.count < masterSet.count - 1`**, which is
  not the bounds check its message claims. The master set has 17 entries and
  `presetPersian17NorthIndian00_17()` legitimately asks for all 17, so it reads `17 < 16` and traps.
  `assert` is compiled out of Release builds, which is why the shipping app never hit it — **and why
  every Debug build of the Tunings panel died on launch.** Fixed to check what it says; regression
  test in `S1SupportTests`.
- **`AKNodeOutputPlot` tapped an unattached node and aborted the process on launch.** A consequence
  of ADR-015: `S1AudioEngine` builds its graph when the engine starts, so a node is not attached at
  the moment upstream created the plot. `Conductor` creates it after `start()` now, and the plot
  refuses to tap an unattached node in any case.
- **`Conductor.start()` was not idempotent.** Calling it twice builds a second graph on a running
  engine and AVAudioEngine aborts. Guarded.

## Controls the Mac idiom refuses (ADR-033)

- **The preset editor's bank picker was a `UIPickerView`**, which throws as soon as it enters a
  window under Optimize Interface for Mac (ADR-023). Opening the editor crashed the app and the
  plugin. `Presets.storyboard` now has a `UITableView` in the picker's frame, keeping its element
  id and connections. `PresetEditorViewController` gives each row the label the picker drew, and
  selecting a row sets `bankSelected` as the picker's `didSelectRow` did. `PORT FIX` at the sites.
- **A sweep of the running app found no other offender.** It loaded 53 of the 55 scenes into the
  window. The other two are `Manager`, which was already in the window. `MacIdiomControlTests`
  repeats that walk in the test bundle. Its list of restricted classes is the one UIKit records in
  its `UICatalystMacIdiomUnsupported_Internal` categories, not a list of names we chose.

## Text that disappears in Dark appearance (ADR-034)

- **The preset and bank editors' name fields** have a fixed near-white background (`#F8F8F8`) in
  `Presets.storyboard` and no text colour, so their text is the dynamic label colour: black in
  Light, white in Dark. In Dark the name was white on near-white, at a contrast of 1.05.
  `PresetEditorViewController` and `BankEditorViewController` pin each field to Light in
  `viewDidLoad`, so it draws as Interface Builder shows it. `PORT FIX` at both sites. The
  storyboard is unchanged.
- **Pinned per field, not per app.** The rest of the interface uses fixed colours, or dynamic ones
  that suit Dark: the category rows, the bank list's selection and the `SynthButton` titles all
  look wrong in Light. Pinning the app to Light would break those; pinning it to Dark would break
  these two fields.
- **A sweep of the running app found no other unreadable text input**, in Dark or in Light.
  `TextInputAppearanceTests` repeats it in the test bundle.

## The keybed (ADR-035)

**A deliberate departure from upstream's layout, at the owner's request**, confined to the keyboard.
The panels, the toolbar and the Show/Hide positions (337 and 636) are upstream's.

- **`Main.storyboard`, iPad scene only.** The keyboard container's height constraint `IyF-k0-ybl`
  (431) is replaced by `kbD-Bd-8Hx`: container bottom = root view bottom. The keyboard view
  `kQD-gK-cOc`, the wheel panel `eos-Os-2YY` and the pads `SJO-uT-R2c` and `RfU-sr-0bT` became
  `heightSizable`. The Pitch and Mod labels `OTn-XD-KmQ` and `GdY-Af-kY1` became `flexibleMinY`. The
  keyboard view's `contentMode` is `redraw`. Frames are left at upstream's values, because the
  autoresizing margins are computed from them. The iPhone scene is untouched.
- **The Keys popover's octave control `Ai9-6v-51K`** gains segments 4 and 5. Otherwise the new default
  of 4 would index a segment that doesn't exist.
- **`AppSettings`**: `octaveRange` 4, `showKeyboard` 0, and a new `keybedVersion`, so settings saved
  before the keybed take its defaults once. `PORT (ADR-035)` at each.
- **`KeyboardView+Draw12ET.swift`** paints shading over upstream's flat fills. `PORT (ADR-035)` at
  each call site. The microtonal drawing is not shaded.
- `KeyboardSettingsViewController.setUpAccessibility()` labels octave segments 1–3 by subview index.
  Nothing calls it, so it was left alone rather than extended.

## No Show/Hide (ADR-039)

**Supersedes ADR-037, which was reverted.** The owner kept the compact view as the only one and
dropped the toggle, because Show only lengthened the keys. The interface is upstream's 1024×768
again. `Manager+callbacks.swift`, `PanelController.swift`, `Manager+EmbeddedViewsDelegate.swift` and
`Manager+HeaderDelegate.swift` are back to upstream: with the keyboard always hidden, upstream's
hidden-keyboard paths are the ones that run.

- **`Manager.viewDidLoad`** hides the Show/Hide button, `keyboardToggle`. Its callback is unchanged and
  still runs at launch with 0. `PORT (ADR-039)`.
- **`AppSettings`** never reads `showKeyboard`, so a saved "shown" cannot put the keyboard over the
  lower panel. `PORT (ADR-039)`.

## Preset arrows on an empty bank (ADR-038)

- **`Presets+LoadSaveManipulate.swift`, `nextPreset` and `previousPreset`.** Upstream indexes the
  current preset's bank without checking it has any presets. The plugin, which cannot read the shared
  preset folder, loaded none, and ▶ crashed it in Logic. Both now return on an empty bank, and
  `previousPreset` clamps a position past the end of the bank. `PORT FIX (ADR-038)` at both.
- The root cause was in our `Disk.exists`, not in ported code: it answered "yes" for files the
  sandbox would not let the plugin read.

## About, More and the bonus presets (ADR-040)

- **`About.storyboard`**: the "World's First Free & Open-Source Pro iOS Synth" label (`s4D-if-VhP`)
  and the "How Synth One was made" button (`aDf-IB-L3u`) are deleted. The credits box (`PTm-MK-dhI`)
  moves from y 140 to 52 and grows from 362 to 450 points, and its text view (`1Nf-2H-Scf`) grows
  from 355 to 443.
- **Upstream's iPhone About scene (`iPhoneAbout`)**, which the Mac never shows, loses the same
  tagline (`Zoc-hO-tj8`, with its three constraints) and its video button, "Synth One in action"
  (`D38-wE-L3I`). Its `videoButton` outlet had to go with the Swift property. The storyboard sweeps
  load every scene, and both threw `NSUnknownKeyException` on the dangling outlet until it did.
- **`AboutViewController.swift`**: the `videoButton` outlet and its callback are removed. `PORT`.
- **`HeaderViewContoller.swift`**: `morePresetsButton` is hidden in `viewDidLoad`. `PORT`.
- **`Presets+LoadSaveManipulate.swift`, `loadBanks`**: BankA built from the factory files includes
  `Bonus.json`, as upstream's More unlock did. `PORT`.

## Settings apart from the shared presets (ADR-041)

The app and the plugin share banks, presets and tunings through an App Group, and each keeps its own
settings. So the three `settings.json` call sites move from `Disk`'s `.documents` to its new
`.settings`: the existence check in `Manager.viewDidAppear`, and `loadSettingsFromDevice` and
`saveAppSettings` in `Manager+AppSettings.swift`. `PORT (ADR-041)` at each. Where the folders
actually are is decided in `Platform/Disk.swift`, which is ours.

## No pop-ups at launch (ADR-042)

`Manager.viewDidAppear` no longer runs upstream's launch-count prompts: the rating alert on the 5th
launch, the App Store review request every 50th, the "Synth One + Share One!" card
(`SegueToSharing`, `SegueToPhoneShare`) every 7th, and the push request on the 9th and every 75th.
The owner saw the card clipped in the standalone and asked for them all to go. `PORT (ADR-042)`
where they were. `reviewPopUp`, `pushPopUp`, the segues and the `SharingIsCaring` scene are
untouched, and `launches` still counts. `LaunchPromptTests` covers it.

## Share in the plugin (ADR-044)

`sharePressed` in `Presets+PresetCellDelegate.swift` and `bankShare` in `Presets+CategoryDelegate.swift`
no longer present a `UIActivityViewController` themselves. Each writes its file as upstream did and calls
`share(_:)` in the new `Presets+Share.swift`. That keeps the share sheet in the standalone and presents an
export `UIDocumentPickerViewController` in the plugin, where the share sheet crashes. `PORT (ADR-044)` at
both call sites. `PluginShareTests` covers the choice.

## Known cosmetic gap

`Main.storyboard` sets a `darkMode` runtime attribute on `KeyboardView`, whose `darkMode` is a Swift
enum and therefore not KVC-compliant. It logs and is ignored — upstream behaves identically. Left
alone; it belongs with the P3-5 pointer/appearance work if it matters.

## Not yet done in this directory

- **P3-2** — Audiobus, AppCenter, StoreKit and the push-notification UI still have live call sites
  that are commented out rather than routed through protocols.
- **P3-3** — `Disk` writes to the app's own container. App Groups are unavailable under ad-hoc
  signing (ADR-006), so the app and the plugin do not share presets yet.
- **P3-4** — `S1MIDI` accepts listeners and does nothing with them.
- **P3-5 / P3-6** — pointer input, window chrome, resizing. The panels render; they have not been
  driven with a mouse.
