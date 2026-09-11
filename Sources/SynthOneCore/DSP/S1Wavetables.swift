//  Loading Synth One's band-limited oscillator tables (P4-2).
//
//  Extracted from `AKSynthOne.init()` because the **AUv3 has no `AKSynthOne`**. The
//  plugin is handed an `S1AudioUnit` by its host; there is no node wrapper, no
//  engine and no `AVAudioUnit.instantiate` in that path, so the loading had to
//  stop being a private detail of the standalone synth.
//
//  ## Why this must happen before `allocateRenderResources`
//
//  `S1NoteState::init` passes `ft_array` straight to `sp_oscmorph2d_init`, and
//  `allocateRenderResources` walks every table to rescale `sicvt` for the sample
//  rate. Both dereference tables that `setupWaveform` has to have created first.
//  Get the order wrong and it is a crash, not a silence. See `DSP/PORTING.md`.
//
//  `destroy()` does not free the tables, so loading them once — outside the
//  allocate/deallocate cycle — is correct and they survive sample-rate changes.

import Foundation
import S1Support

public enum S1Wavetables {

    /// 4 waveforms × 13 band-limited tables.
    public static let waveformCount = 4
    public static let bandCount = 13
    public static let tableSize = 4_096

    public struct Tables {
        public let waveforms: [AKTable]
        public let bandlimitFrequencies: [Float]
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case missingResource(String)
        case wrongCount(expected: Int, got: Int)

        public var description: String {
            switch self {
            case .missingResource(let name):
                return "\(name).json is not in SynthOneCore.framework"
            case .wrongCount(let expected, let got):
                return "expected \(expected) wavetables, found \(got)"
            }
        }
    }

    /// Decode every table from the framework bundle.
    ///
    /// Framework, not `Bundle.main`: the app's bundle has none of this, and the
    /// AUv3's bundle is a third place again. There is one copy, inside the
    /// framework both products embed.
    public static func load(from bundle: Bundle = .synthOneCore) throws -> Tables {
        let decoder = JSONDecoder()

        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw Error.missingResource(name)
            }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }

        let names = try decoder.decode([String].self, from: data("bandlimitedWaveforms"))
        guard names.count == waveformCount * bandCount else {
            throw Error.wrongCount(expected: waveformCount * bandCount, got: names.count)
        }
        let waveforms = try names.map { try decoder.decode(AKTable.self, from: data($0)) }
        let frequencies = try decoder.decode(AKTable.self, from: data("bandlimitedWaveformFrequencies"))

        return Tables(waveforms: waveforms, bandlimitFrequencies: Array(frequencies))
    }

    /// Push tables into a freshly created audio unit.
    ///
    /// Must be called after `S1AudioUnit.init` (which builds the kernel) and before
    /// the host calls `allocateRenderResources`.
    public static func apply(_ tables: Tables, to unit: S1AudioUnit) {
        for (index, frequency) in tables.bandlimitFrequencies.enumerated() {
            unit.setBandlimitFrequency(UInt32(index), withFrequency: frequency)
        }
        for (tableIndex, table) in tables.waveforms.enumerated() {
            unit.setupWaveform(UInt32(tableIndex), size: Int32(table.count))
            for (sampleIndex, sample) in table.enumerated() {
                unit.setWaveform(UInt32(tableIndex), withValue: sample, at: UInt32(sampleIndex))
            }
        }
    }

    /// Decode and apply in one step, logging rather than throwing.
    ///
    /// A synth with no wavetables is silent, not broken-looking, so the failure is
    /// worth a loud log line — but it must not stop the plugin from instantiating,
    /// or the host reports a dead plugin instead of a quiet one.
    public static func loadAndApply(to unit: S1AudioUnit, from bundle: Bundle = .synthOneCore) {
        do {
            apply(try load(from: bundle), to: unit)
        } catch {
            AKLog("S1Wavetables: FAILED to load oscillator tables — the synth will be silent: \(error)")
        }
    }
}
