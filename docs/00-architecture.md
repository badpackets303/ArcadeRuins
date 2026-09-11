# Architecture

## Target graph

```
                    ┌──────────────┐   ┌──────────────┐
                    │  Soundpipe   │   │  S1Support   │
                    │  (C, MIT)    │   │  AK shims    │
                    └──────┬───────┘   └──────┬───────┘
                           └────────┬─────────┘
                            ┌───────▼────────┐
                            │  SynthOneCore  │  framework
                            │  DSP kernel    │
                            │  S1AudioUnit   │
                            │  model/presets │
                            │  ALL UIKit UI  │
                            └───┬────────┬───┘
                   ┌────────────┘        └────────────┐
           ┌───────▼────────┐              ┌──────────▼──────────┐
           │   SynthOne     │              │     SynthOneAU      │
           │ Catalyst app   │              │  AUv3 app extension │
           │ (standalone)   │              │  aumu / ruin        │
           │ owns AVAudio-  │              │  host owns the      │
           │ Engine+Session │              │  render context     │
           └────────────────┘              └─────────────────────┘
```

Everything visible and audible lives in `SynthOneCore`. The two products differ only in who owns
the audio context. That is the whole point of the split: it is what stops the plugin and the
standalone app from drifting apart as the port proceeds.

## The `S1Engine` seam (P4-2)

Upstream, `Conductor` both owns the `AVAudioEngine` and is the UI's route to the DSP. In a plugin
the host owns the render context, so those two roles must separate:

```
    UI  ──▶  S1Engine (protocol)  ──▶  S1AudioUnit  ──▶  S1DSPKernel
                  ▲                                          │
       ┌──────────┴──────────┐                    TAAE lock-free queues
       │                     │                               │
StandaloneEngine        PluginEngine                         ▼
(owns AVAudioEngine,   (host owns render,              UI updates on
 AVAudioSession,        params via                      main thread
 CoreMIDI)              AUParameterTree,
                        transport via
                        musicalContextBlock)
```

The UI keeps talking to one thing. Standalone drives the engine and reads tempo from its own clock
(or Ableton Link, if P3-7 ever lands); the plugin reads tempo and transport from the host.

## Threading

`S1DSPKernel` runs on the render thread. Main↔render communication already goes through TAAE's
lock-free primitives (`AEMessageQueue`, `AEMainThreadEndpoint`, `AEAudioThreadEndpoint`), which are
vendored in-tree and portable. **Preserve this discipline.** No allocation, no locks, no Obj-C
message sends to unbounded code on the render thread. The AU parameter tree added at P4-3 must feed
the kernel through the same path — that is the most likely place for a real-time-safety regression
to be introduced.

## Parameters

`S1Parameter.h` defines 150 parameters as a C enum (`S1ParameterCount = 150`), with ranges, defaults
and taper curves already living in the kernel (`S1DSPKernel+parameters.mm`, `+tapers.mm`) and
exposed via `getMinimum:` / `getMaximum:` / `getDefault:`.

The `AUParameterTree` (P4-3) is **generated from that enum**, never hand-written. 150 hand-maintained
parameter definitions would rot the first time one changes.
