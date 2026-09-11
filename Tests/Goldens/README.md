# Golden renders (P2-4)

Twenty of Synth One's shipped presets, rendered offline, committed as 32-bit float WAV.
`GoldenRenderTests` re-renders them on every test run and compares. **This is the check that makes
"preserve functionality" mean something** — ADR-011 is the story of a bug that compiled, linked, ran,
and would only ever have been caught by comparing audio.

## They are also for listening to

`open Tests/Goldens`. If a future change is *supposed* to alter the sound, listening to the before
and after is the review; the numbers only tell you that something moved.

## Regenerating

```bash
Scripts/write-goldens.sh
```

Only for a change you intend to hear. The `TEST_RUNNER_` prefix in that script is required —
`xcodebuild` does not pass the shell environment to the test runner, and a bare
`SYNTHONE_WRITE_GOLDENS=1` is silently ignored.

## What is fixed, and therefore load-bearing

Changing any of it invalidates all twenty files:

| | |
|---|---|
| Sample rate / block | 44,100 Hz, 512 frames, stereo |
| Settle | 0.75 s rendered before the first note (ADR-013 — the synth sweeps into tune) |
| Notes | A3 (57) at t=0, E4 (64) at t=0.4, both released at t=1.0, velocity 100 |
| Captured | 1.5 s from the first note |
| Tolerance | max sample difference 1e-4, relative RMS difference 1e-5 |

## Why float32 and not 16-bit

16-bit was tried first, to halve the 10 MB. It does not work: **four of the twenty presets render
above full scale** — loud patches through the master compressor, which is the instrument behaving as
designed — and integer PCM clamps them. The worst mismatch was 1.37, entirely a clipped peak.

A golden has to record what the DSP produced, over-full-scale included, because that is the
behaviour being protected.

## How sensitive is it, really?

Measured, not assumed. Changing one internal LFO smoothing constant by **0.24%**
(`kLFOSmoothHalftime`, 0.0053125 → 0.0053) failed **17 of the 20**. The three that passed are the
patches with no LFO — which is the right answer, not a gap.

## Determinism

`testRendersAreBitIdenticalAcrossRuns` asserts two renders of the same preset are identical, because
a flaky golden suite is worse than none. It holds because every render builds a fresh `S1DSPKernel`
and `sp_create` seeds Soundpipe's RNG to zero — so even the presets with noise reproduce exactly.

## Selection

Chosen by greedy coverage over 23 sonic features across all 695 shipped presets, then spread so all
13 banks contribute. Between them they cover every filter type, both LFOs and every LFO routing in
use, arp and sequencer, mono and legato, glide, detune, FM, sub, noise, bitcrush, phaser, delay,
reverb, autopan and widen.

The list lives in `GoldenRenderTests.goldens`. Adding to it is fine; changing an entry orphans a file.
