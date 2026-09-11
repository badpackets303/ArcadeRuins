# SynthOneCore/Presets — porting record (P2-4)

The preset model and the mapping from a preset to the DSP. Ported early, out of Phase 3, because
P2-4's golden-WAV suite needed to render Synth One's **own** patches rather than parameter sets
invented for a test.

## Files

| File | Origin | Notes |
|---|---|---|
| `Preset.swift` | `upstream/.../Presets/Preset.swift` | The Codable model — ~110 fields plus a JSON-dictionary initialiser |
| `Preset+Synth.swift` | extracted from `PresetDataManager.loadPreset()` | The 100-line mapping from preset fields to `S1Parameter` |
| `Data/*.json` | `upstream/.../Presets/Data/` | 13 banks, 695 presets, bundled as framework resources |

## Changes to `Preset.swift`

| Change | Why |
|---|---|
| `import AudioKit` → `import S1Support` | the file lives inside `SynthOneCore` |
| `init(dictionary:)` → `init(dictionary:defaults:)` | upstream reads per-parameter defaults off `Conductor.sharedInstance.synth`, a UI singleton. A preset is a value; it should decode without a running synth. `AKSynthOne.presetDefaults` is what the app passes. Same for `parseDataToPreset(s)` |
| sequencer defaults read from the defaults provider, not the live synth | upstream's fallback for a missing `seqPatternNote` / `seqNoteOn` / `seqOctBoost` key was "keep whatever the previous preset left in the sequencer" — so decoding the same JSON twice could give different objects. **Inert for the shipped banks**: all 695 carry all three keys |

Nothing else. Every field name, default and JSON key is upstream's — they have to be, or presets
saved by the iOS app stop loading.

## Why the mapping moved out of `PresetDataManager`

Upstream, `loadPreset()` is an extension on `Manager`, the top-level view controller, and interleaves
three genuinely-UI concerns with the mapping: the DEV panel's *freeze delay / reverb / arp* toggles,
the tunings panel, and `conductor.updateDefaultValues()`.

`Preset.apply(to:)` is the mapping alone, **verbatim and in upstream's order**. Order is not
cosmetic here — `S1DSPKernel::_setSynthParameter` has dependent parameters, so writes can affect each
other. Phase 3's `loadPreset()` becomes a thin wrapper that puts the freeze toggles and the tuning
back around a call to this.

## Verified

`GoldenRenderTests`: all 695 presets in all 13 banks decode; applying a preset reaches the DSP
(checked against five parameters that the JSON sets away from their defaults); and 20 of them render
to committed golden WAVs.
