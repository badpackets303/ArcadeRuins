# Soundpipe — vendoring record

> **This supersedes the original P1-2 record.** P1-2 vendored *canonical* Soundpipe. P1-5 proved
> that was wrong, and it was re-vendored from AudioKit's fork. See **ADR-011** for why.

## Source

**AudioKit 4.9.2's vendored Soundpipe**, from `github.com/AudioKit/AudioKit` @ `03fecf80`
(recorded in `.upstream-revision`):

- `AudioKit/Core/Soundpipe/` — the fork itself (MIT; see `README-Soundpipe.md`, `LICENSE-AudioKit`)
- `AudioKit/Core/SoundpipeExtension/` — AudioKit's additions, i.e. `sp_oscmorph2d`

## Why not canonical Soundpipe

Canonical upstream (`PaulBatchelor/Soundpipe`) has diverged from the fork Synth One was built
against, in two ways that matter:

| | Canonical | AudioKit's fork |
|---|---|---|
| `sp_port` | fields `smooth`, `a1`, `b0`, `y0`; `sp_port_init(sp, p)` | fields `htime`, `c1`, `c2`, `yt1`; **`sp_port_init(sp, p, htime)`** |
| `sp_oscmorph2d` | not present at all | **band-limited**: `nbl`, `fbl`, `enableBandlimit`, `bandlimitIndexOverride` |

`sp_port`'s *difference equation is the same* in both (`c2 = pow(0.5, onedsr/htime)`), so only the
field names and init signature differ — annoying but harmless.

**`sp_oscmorph2d` is the one that mattered.** AudioKit's version selects among 13 band-limited
tables per waveform according to pitch; that is Synth One's anti-aliasing. The 54 JSON files in
`DSP/BandlimitedWavetables/` exist solely to feed it. Vendoring the non-band-limited version would
have compiled, run, and quietly made the synth alias at high frequencies — a fidelity regression
that no build error would have caught.

### The red herring

`upstream/AudioKitSynthOne/DSP/Kernel/oscmorph2d.c` looks like the implementation and is *not* — it
is a stale, non-band-limited copy with no `enableBandlimit`. The real one is
`AudioKit/Core/SoundpipeExtension/modules/oscmorph2d.c`. P1-2 vendored the stale in-tree file; the
mismatch only surfaced at P1-5 when `S1NoteState.mm` failed to compile against it.

## What is vendored

**19 modules** from the fork: `base` `ftbl` `randmt` · `adsr` `butbp` `buthp` `compressor`
`crossfade` `delay` `fosc` `moogladder` `noise` `osc` `pan2` `phaser` `phasor` `port` `revsc`
`vdelay`, plus **`oscmorph2d`** from SoundpipeExtension.

`base` and `randmt` are not on the kernel's call-site list — they are needed transitively
(`sp_auxdata_*` for delay/revsc/vdelay; `sp_randmt_*` from `ftbl.c`).

Headers, verbatim: `soundpipe.h` (the fork ships it pre-assembled, so **no assembly script is
needed** — the P1-2 one was deleted), `soundpipeextension.h`, `lib/faust/CUI.h`, and
`lib/dr_wav/dr_wav.h`.

**Everything here is byte-for-byte as AudioKit shipped it. Do not edit.**

## Build configuration

- `NO_LIBSNDFILE=1` — `base.c`/`ftbl.c` guard their file I/O behind it; we never load files.
- `CLANG_ENABLE_MODULES: NO` **on the Soundpipe target only.** The module map exists for Swift
  consumers. The C sources must compile textually: `oscmorph2d.c` includes `soundpipeextension.h`
  directly, and with modules on, Clang also pulls it in via the Soundpipe module, defining
  `sp_oscmorph2d` twice.
- `dr_wav` is on the header search path for **declarations only**. `soundpipe.h` declares `sp_wavin`,
  whose struct embeds a `drwav`. We never compile `dr_wav.c` and never call `sp_wavin_*`.
- `GCC_C_LANGUAGE_STANDARD: gnu11` (project-wide) — TAAE uses `typeof()`.

## ⚠️ Trap: `sp_create` does not return `SP_OK`

`SP_OK` is `1`, but `base.c`'s `sp_create`, `sp_createn` and `sp_destroy` `return 0`. Every
*module's* `*_create` returns `SP_OK`. Check the out-pointer, not the return code. (True of both
forks.)

## Verified

- Builds for Mac Catalyst, arm64 + x86_64.
- All 21 entry points the kernel calls are present; undefined externals are libc/libm only.
- `Tests/SynthOneTests/SoundpipeTests.swift` asserts behaviour, not linkage: oscillator frequency to
  ±2 Hz, `moogladder` attenuating above cutoff, `adsr` reaching sustain then releasing, and
  `oscmorph2d` producing correct-pitch audio through the band-limited API.
- **The S1 kernel compiles against it unmodified** — no `sp_port` or `oscmorph2d` edits were needed
  once the correct fork was in place.

## Local changes

The fork is otherwise byte-for-byte AudioKit's. Each change is marked `PORT FIX` in the source.

| File | Change | Why |
|---|---|---|
| `modules/revsc.c` | `(p->aux.ptr) + nBytes` → `(void *)((char *)(p->aux.ptr) + nBytes)` | X1-1, ADR-065. Arithmetic on `void *` is a GNU extension; MSVC stops with C2036. GCC and Clang step `void *` in bytes, so the address — and the reverb — is unchanged there. Found by the Windows job of the `engine` workflow on its first run. |

