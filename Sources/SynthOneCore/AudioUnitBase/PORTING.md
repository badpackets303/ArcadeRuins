# AudioUnitBase — porting record (P1-4)

Replacements for AudioKit's `AKAudioUnit` and `AKSoundpipeKernel`, plus the Apple sample-code
classes AudioKit vendored beneath them. Source: `github.com/AudioKit/AudioKit` @ `v4.9.2`
(`03fecf80`, MIT). Names kept per **ADR-009**.

## Layout, and why headers sit under `AudioKit/`

```
AudioUnitBase/
  AudioKit/            <- on the header search path, so ported kernel sources keep
    DSPKernel.hpp         their `#import "AudioKit/AKSoundpipeKernel.hpp"` lines verbatim
    AKDSPKernel.hpp
    AKSoundpipeKernel.hpp
    BufferedAudioBus.hpp
    AKAudioUnit.h              (public framework header — pure Obj-C)
    S1TestToneAudioUnit.h      (public framework header — pure Obj-C)
  DSPKernel.mm
  AKAudioUnit.mm
  S1TestToneAudioUnit.mm
```

`Sources/SynthOneCore/AudioUnitBase` is in `HEADER_SEARCH_PATHS`, so `S1DSPKernel.hpp` ports at P1-5
without touching its include lines. **Public** headers are different: Xcode flattens them into
`SynthOneCore.framework/Headers`, so they must use `#import <SynthOneCore/AKAudioUnit.h>` instead.

## The class stack

```
DSPKernel                 Apple sample: process(), startRamp(), handleMIDIEvent(),
  └ AKDSPKernel           processWithEvents() event/render splitting
      └ AKSoundpipeKernel  channels + sampleRate
                           owns the sp_data lifecycle
AKOutputBuffered          holds the output AudioBufferList
BufferedOutputBus         AVAudioPCMBuffer backing + prepareOutputBufferList()
AKAudioUnit               AUAudioUnit subclass: busses, parameter-tree categories
```

`S1DSPKernel : public AKSoundpipeKernel, public AKOutputBuffered` — unchanged at P1-5.

## Changes from upstream

**1. PORT FIX — `AKDSPKernel::init` never updated the sample rate.**

```cpp
virtual void init(int channelCount, double sampleRate) {
    channels = channelCount;
    sampleRate = sampleRate;   // upstream: self-assignment, member never written
}
```

Now `this->sampleRate = sampleRate`. Upstream's bug was partly masked because `AKSoundpipeKernel::init`
separately assigns `sp->sr` from its own parameter, and `S1DSPKernel::sampleRate()` reads `sp->sr` —
but `getSampleRate()` returned a stale value after any sample-rate change.

**2. `soundpipeextension.h` is not reproduced.** Upstream's `AKSoundpipeKernel.hpp` includes it; that
header declares nothing but `sp_oscmorph2d`, which our generated `soundpipe.h` already declares
(`Sources/Soundpipe/VENDORING.md`). Confirmed by inspecting AudioKit's copy.

**3. `AKSettings` is read through C.** Upstream reaches it via `<AudioKit/AudioKit-Swift.h>`. Ours is
Swift in a *static library*, which has no usable Obj-C interface header across the target boundary.
The three scalars the DSP layer needs are backed by C storage that both languages front — see
**ADR-010** and `Sources/S1Support/include/AKSettingsBridge.h`.

**4. `AKParametricKernel` / `ParameterRamper` not ported.** Synth One does not use them (verified by
grep over `upstream/`). `S1DSPKernel` implements `startRamp` itself.

**5. `AKAudioUnit` init no longer clobbers a subclass's busses.** Upstream unconditionally creates its
own `outputBus`/`outputBusArray` after calling `createParameters`. Since `S1AudioUnit` builds its own
from a `BufferedOutputBus`, ours only creates defaults when the subclass left them nil.

## ⚠️ Behaviour to remember at P4-3

`AKAudioUnit::allocateRenderResourcesAndReturnError:` calls `setUpParameterRamp`, which **replaces**
`parameterTree.implementorValueObserver` with one that funnels through `scheduleParameterBlock`. It
therefore overwrites whatever a subclass installed in `createParameters`, on every allocation. That is
upstream's behaviour and is preserved deliberately — but it is exactly the kind of thing that will look
like a bug when the real 150-parameter tree is wired up at P4-3.

## Verified

`S1TestToneAudioUnit` is a deliberate rehearsal for `S1AudioUnit`: same inheritance, same
`BufferedOutputBus`, same render block shape. 6 tests in `Tests/SynthOneTests/AudioUnitBaseTests.swift`:

- instantiates; `AKAudioUnit` vends the subclass's own bus array; format is 44.1 kHz stereo
- gate closed renders **exact digital silence** (proves `BufferedOutputBus` zero-fills)
- gate open renders a 440 Hz tone measured to **±3 Hz**, peak > 0.5
- frequency is settable (220 Hz verified)
- survives three allocate/deallocate cycles — `sp_data` teardown and rebuild does not leak or crash
- sample-rate regression test for PORT FIX 1

## X1-3 (ADR-067) — the kernel no longer inherits these

`S1DSPKernel` used to derive from `AKSoundpipeKernel` → `AKDSPKernel` → `DSPKernel` and
`AKOutputBuffered`. It derives from the engine's own `S1SoundpipeKernel` and `S1OutputBuffered`
(`Sources/S1Engine/Kernel/S1KernelBase.hpp`) now, which keep exactly what it used. These
headers stay for `S1TestToneKernel` and for `S1KernelAUAdapter` (`S1AudioUnit.mm`), which is
a `DSPKernel` + `AKOutputBuffered` wrapping the engine kernel: Apple's event splitter, unchanged
(P4-2 fix included), forwarding `process` / `startRamp` / `handleMIDIEvent` and pointing the
kernel's output at the buffer list. The three helpers `clamp`, `pow2` and `noteToHz` are
defined here and in `S1KernelBase.hpp` under one guard, `S1_KERNEL_HELPERS_DEFINED`, so a
translation unit that meets both keeps the first.

