//  The 13 shipped banks, offered to a host as AU factory presets (P4-4).
//
//  ## Why this exists separately from the preset browser
//
//  The standalone app has a whole preset UI — banks, categories, search, favourites
//  — backed by `PresetsViewController` and `Disk`. A plugin gets none of that from
//  the host; what a host offers is a flat list of `AUAudioUnitPreset`, one menu,
//  chosen by index. This maps one onto the other.
//
//  It also has to work where `AKSynthOne` does not exist. The plugin is handed a
//  bare `S1AudioUnit` (P4-2) — no node, no engine — but `Preset.apply(to:)` was
//  written against `AKSynthOne`. Rather than duplicate that 100-line mapping, the
//  mapping now targets `S1PresetSink`, which both satisfy.
//
//  ## All 695, not a curated subset
//
//  695 is a lot for one menu, and the alternative was to expose only the Starter
//  Bank. Rejected: the banks *are* the instrument, hosts let you scroll and search
//  a preset list, and a plugin that silently offers 5% of what the app offers is
//  the more surprising outcome. Names are `Bank: Preset`, so a host's alphabetical
//  list groups by bank on its own.

import Foundation
import S1Support

/// What `Preset.apply(to:)` needs in order to write itself into a synth.
///
/// Exists so one mapping serves both worlds: `AKSynthOne` in the standalone, and a
/// bare `S1AudioUnit` in the plugin, which has no node wrapper to go through.
public protocol S1PresetSink: AnyObject {
    func setSynthParameter(_ parameter: S1Parameter, _ value: Double)
    func setPattern(forIndex index: Int, _ value: Int)
    func setOctaveBoost(forIndex index: Int, _ value: Double)
    func setNoteOn(forIndex index: Int, _ value: Bool)
    func resetSequencer()
}

// `AKSynthOne` already has all five with these signatures — this is the
// conformance, not an implementation.
extension AKSynthOne: S1PresetSink {}

extension S1AudioUnit: S1PresetSink {

    public func setSynthParameter(_ parameter: S1Parameter, _ value: Double) {
        setSynthParameter(parameter, value: Float(value))
    }

    public func setPattern(forIndex index: Int, _ value: Int) {
        guard let parameter = S1HostedSynth.sequencerParameter(.sequencerPattern00, index) else { return }
        setSynthParameter(parameter, value: Float(value))
    }

    public func setOctaveBoost(forIndex index: Int, _ value: Double) {
        guard let parameter = S1HostedSynth.sequencerParameter(.sequencerOctBoost00, index) else { return }
        setSynthParameter(parameter, value: Float(value))
    }

    public func setNoteOn(forIndex index: Int, _ value: Bool) {
        guard let parameter = S1HostedSynth.sequencerParameter(.sequencerNoteOn00, index) else { return }
        setSynthParameter(parameter, value: value ? 1 : 0)
    }
}

/// Loads the shipped banks and applies them by index.
///
/// Conforms to `S1FactoryPresetSource`, the Obj-C protocol `S1AudioUnit` calls from
/// its `factoryPresets` / `currentPreset` overrides — the audio unit is Obj-C++ and
/// the preset codec is Swift, and this is the seam between them.
@objc(S1FactoryPresets)
public final class S1FactoryPresets: NSObject, S1FactoryPresetSource {

    /// Bank load order, which fixes the preset *numbers* a host writes into its
    /// session file. **Do not reorder or insert**: a host stores the number, not the
    /// name, so changing this silently repoints every saved session at a different
    /// sound. Appending at the end is safe.
    static let bankOrder = [
        "BankA", "Bonus", "Brice Beasley", "DJ Puzzle", "Electronisounds",
        "Francis Preve", "JEC", "Red Sky Lullaby", "Sound of Izrael",
        "Sound of Izrael 2", "Spidericemidas", "Starter Bank", "User"
    ]

    private let presets: [(name: String, preset: Preset)]

    /// - Parameter defaults: the DSP's default for a parameter a preset's JSON omits.
    public init(defaults: @escaping PresetDefaults) {
        var loaded: [(String, Preset)] = []
        for bank in Self.bankOrder {
            guard let url = Bundle.synthOneCore.url(forResource: bank, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let array = json as? [Any] else { continue }
            for preset in Preset.parseDataToPresets(jsonArray: array, defaults: defaults) {
                loaded.append(("\(bank): \(preset.name)", preset))
            }
        }
        presets = loaded
        super.init()
    }

    /// Builds a source for `unit` and installs it, using that unit's own defaults.
    ///
    /// Both the app and the plugin call this; it is the counterpart to
    /// `S1Wavetables.loadAndApply(to:)` and, like it, is a step the audio unit
    /// cannot do for itself — `S1AudioUnit` is Obj-C++ and cannot reach the Swift
    /// preset codec.
    @discardableResult
    public static func install(into unit: S1AudioUnit) -> S1FactoryPresets {
        let source = S1FactoryPresets(defaults: { [weak unit] parameter in
            Double(unit?.getDefault(parameter) ?? 0)
        })
        unit.factoryPresetSource = source
        return source
    }

    public var count: Int { presets.count }

    // MARK: - S1FactoryPresetSource

    public func factoryPresetNames() -> [String] { presets.map(\.name) }

    public func applyFactoryPreset(at index: Int, to unit: S1AudioUnit) -> Bool {
        guard presets.indices.contains(index) else { return false }
        presets[index].preset.apply(to: unit)
        return true
    }
}
