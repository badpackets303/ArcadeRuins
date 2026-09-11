//  Thin Swift view of the vendored C library. Exists so the link path and the
//  DSP primitives are exercised from Phase 1 rather than first being trusted at
//  P1-5, when they would be buried under the S1 kernel.
//
//  These helpers grow into the headless render harness at P1-6.

import Foundation
import Soundpipe

enum SoundpipeBridge {

    static func canAllocate() -> Bool {
        // NB: sp_create returns 0, NOT SP_OK (which is 1). Only base.c deviates
        // like this; every module's *_create returns SP_OK. Check the pointer.
        var handle: UnsafeMutablePointer<sp_data>?
        sp_create(&handle)
        guard let sp = handle else { return false }
        defer { var t: UnsafeMutablePointer<sp_data>? = sp; sp_destroy(&t) }
        return sp.pointee.sr == 44_100
    }

    /// Runs `body` with an initialised `sp_data` at the given sample rate.
    private static func withSP<T>(sampleRate: Int32 = 44_100,
                                  _ body: (UnsafeMutablePointer<sp_data>) -> T) -> T? {
        // NB: sp_create returns 0, not SP_OK. See canAllocate().
        var handle: UnsafeMutablePointer<sp_data>?
        sp_create(&handle)
        guard let sp = handle else { return nil }
        defer { var t: UnsafeMutablePointer<sp_data>? = sp; sp_destroy(&t) }
        sp.pointee.sr = sampleRate
        return body(sp)
    }

    /// A 4096-point sine wavetable, as the S1 kernel builds for its oscillators.
    private static func withSineTable<T>(_ sp: UnsafeMutablePointer<sp_data>,
                                         _ body: (UnsafeMutablePointer<sp_ftbl>) -> T) -> T? {
        var ft: UnsafeMutablePointer<sp_ftbl>?
        guard sp_ftbl_create(sp, &ft, 4_096) == SP_OK, let ft else { return nil }
        defer { var t: UnsafeMutablePointer<sp_ftbl>? = ft; sp_ftbl_destroy(&t) }
        sp_gen_sine(sp, ft)
        return body(ft)
    }

    // MARK: - Render helpers (used by tests; the P1-6 harness builds on these)

    static func renderSine(frequency: Float, amplitude: Float = 1.0,
                           frames: Int, sampleRate: Int32 = 44_100) -> [Float] {
        withSP(sampleRate: sampleRate) { sp in
            withSineTable(sp) { ft -> [Float] in
                var osc: UnsafeMutablePointer<sp_osc>?
                guard sp_osc_create(&osc) == SP_OK, let osc else { return [] }
                defer { var o: UnsafeMutablePointer<sp_osc>? = osc; sp_osc_destroy(&o) }
                sp_osc_init(sp, osc, ft, 0)
                osc.pointee.freq = frequency
                osc.pointee.amp = amplitude

                var out = [Float](repeating: 0, count: frames)
                var sample: Float = 0
                for i in 0..<frames {
                    sp_osc_compute(sp, osc, nil, &sample)
                    out[i] = sample
                }
                return out
            } ?? []
        } ?? []
    }

    static func moogladder(_ input: [Float], cutoff: Float, resonance: Float = 0,
                           sampleRate: Int32 = 44_100) -> [Float] {
        withSP(sampleRate: sampleRate) { sp -> [Float] in
            var filt: UnsafeMutablePointer<sp_moogladder>?
            guard sp_moogladder_create(&filt) == SP_OK, let filt else { return [] }
            defer { var f: UnsafeMutablePointer<sp_moogladder>? = filt; sp_moogladder_destroy(&f) }
            sp_moogladder_init(sp, filt)
            filt.pointee.freq = cutoff
            filt.pointee.res = resonance

            var out = [Float](repeating: 0, count: input.count)
            for i in 0..<input.count {
                var sample = input[i]
                var result: Float = 0
                sp_moogladder_compute(sp, filt, &sample, &result)
                out[i] = result
            }
            return out
        } ?? []
    }

    /// Renders an ADSR envelope: `gateFrames` of gate-on, then gate-off.
    static func renderADSR(attack: Float, decay: Float, sustain: Float, release: Float,
                           gateFrames: Int, totalFrames: Int,
                           sampleRate: Int32 = 44_100) -> [Float] {
        withSP(sampleRate: sampleRate) { sp -> [Float] in
            var env: UnsafeMutablePointer<sp_adsr>?
            guard sp_adsr_create(&env) == SP_OK, let env else { return [] }
            defer { var e: UnsafeMutablePointer<sp_adsr>? = env; sp_adsr_destroy(&e) }
            sp_adsr_init(sp, env)
            env.pointee.atk = attack
            env.pointee.dec = decay
            env.pointee.sus = sustain
            env.pointee.rel = release

            var out = [Float](repeating: 0, count: totalFrames)
            for i in 0..<totalFrames {
                var gate: Float = i < gateFrames ? 1 : 0
                var result: Float = 0
                sp_adsr_compute(sp, env, &gate, &result)
                out[i] = result
            }
            return out
        } ?? []
    }

    /// Exercises Synth One's own `sp_oscmorph2d` — the one module that is not
    /// stock Soundpipe (see Sources/Soundpipe/VENDORING.md).
    static func renderOscMorph2D(frequency: Float, morphPosition: Float,
                                 frames: Int, sampleRate: Int32 = 44_100) -> [Float] {
        withSP(sampleRate: sampleRate) { sp -> [Float] in
            // Two identical sine tables is enough to prove the morph path runs;
            // the real band-limited tables arrive with the kernel at P1-5.
            // nft waveforms x nbl band-limited tables each. One band-limit table
            // is enough here; the real 13-per-waveform set arrives with the
            // kernel's BandlimitedWavetables at P1-5.
            let nft: Int32 = 2
            let nbl: Int32 = 1
            var tables = [UnsafeMutablePointer<sp_ftbl>?](repeating: nil, count: Int(nft * nbl))
            for i in 0..<tables.count {
                guard sp_ftbl_create(sp, &tables[i], 4_096) == SP_OK else { return [] }
                sp_gen_sine(sp, tables[i])
            }
            defer { for i in 0..<tables.count { sp_ftbl_destroy(&tables[i]) } }
            var bandlimitFrequencies: [Float] = [20_000]

            var osc: UnsafeMutablePointer<sp_oscmorph2d>?
            guard sp_oscmorph2d_create(&osc) == SP_OK, let osc else { return [] }
            defer { var o: UnsafeMutablePointer<sp_oscmorph2d>? = osc; sp_oscmorph2d_destroy(&o) }

            var out = [Float](repeating: 0, count: frames)
            tables.withUnsafeMutableBufferPointer { buf in
                bandlimitFrequencies.withUnsafeMutableBufferPointer { fbl in
                    sp_oscmorph2d_init(sp, osc, buf.baseAddress, nft, nbl, fbl.baseAddress, 0)
                }
                osc.pointee.enableBandlimit = 0
                osc.pointee.freq = frequency
                osc.pointee.amp = 1
                osc.pointee.wtpos = morphPosition

                var sample: Float = 0
                for i in 0..<frames {
                    sp_oscmorph2d_compute(sp, osc, nil, &sample)
                    out[i] = sample
                }
            }
            return out
        } ?? []
    }
}
