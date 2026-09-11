//
//  AKSynthOne.swift
//  AudioKit
//
//  Created by AudioKit Contributors, revision history on Github.
//  Join us at AudioKitPro.com, github.com/audiokit
//

import Foundation
import AVFoundation
// PORT: `import AudioKit`. This file now lives *inside* SynthOneCore, so it
// imports the AK* replacements directly rather than through the framework's
// re-export (ADR-009).
import S1Support

@objc open class AKSynthOne: AKPolyphonicNode, AKComponent, S1Protocol {

    static let SFTABLESIZE = 4_096
    static let SNUMWAVEFORMS = 4
    static let SNUMBANDLIMITEDFTABLES = 13

    /// PORT: upstream reads the wavetables out of `Bundle.main`, where they sat in
    /// the iOS app. Ours are resources of SynthOneCore, which is also the only
    /// place the AUv3 extension can find them.
    static let bundle = Bundle(for: AKSynthOne.self)

    public typealias AKAudioUnitType = S1AudioUnit

    /// Four letter unique description of the node
    public static let ComponentDescription = AudioComponentDescription(instrument: "ruin")

    // MARK: - Properties

    public var internalAU: AKAudioUnitType?
    public var token: AUParameterObserverToken?

    fileprivate var waveformArray = [AKTable]()
    fileprivate var auParameters: [AUParameter] = []

    /// The DSP's own default for every parameter — what a preset falls back to for
    /// a key its JSON does not carry. See `PresetDefaults`.
    open var presetDefaults: PresetDefaults {
        { [weak self] parameter in Double(self?.internalAU?.getDefault(parameter) ?? 0) }
    }

    ///Hard-reset of DSP...for PANIC
    open func resetDSP() {
        internalAU?.resetDSP()
    }

    open func resetSequencer() {
        internalAU?.resetSequencer()
    }

    ///Puts all playing notes into release mode.
    open func stopAllNotes() {
        internalAU?.stopAllNotes()
    }

    open func setSynthParameter(_ parameter: S1Parameter, _ value: Double) {
        internalAU?.setSynthParameter(parameter, value: Float(value))
    }

    open func getSynthParameter(_ parameter: S1Parameter) -> Double {
        return Double(internalAU?.getSynthParameter(parameter) ?? 0)
    }

    open func getDependentParameter(_ parameter: S1Parameter) -> Double {
        return Double(internalAU?.getDependentParameter(parameter) ?? 0)
    }
    open func setDependentParameter(_ parameter: S1Parameter, _ value: Double, _ payload: Int32) {
        internalAU?.setDependentParameter(parameter, value: Float(value), payload: payload)
    }

    open func getMinimum(_ parameter: S1Parameter) -> Double {
        return Double(internalAU?.getMinimum(parameter) ?? 0)
    }

    open func getMaximum(_ parameter: S1Parameter) -> Double {
        return Double(internalAU?.getMaximum(parameter) ?? 1)
    }

    open func getRange(_ parameter: S1Parameter) -> ClosedRange<Double> {
        
        let min = Double(internalAU?.getMinimum(parameter) ?? 0)
        let max = Double(internalAU?.getMaximum(parameter) ?? 1)
        return min ... max
    }

    open func getDefault(_ parameter: S1Parameter) -> Double {

        return Double(internalAU?.getDefault(parameter) ?? 0)
    }

    open func getPattern(forIndex inputIndex: Int) -> Int {

        let index = (0...15).clamp(inputIndex)
        let aspi = Int32(Int(S1Parameter.sequencerPattern00.rawValue) + index)
        guard let aspp = S1Parameter(rawValue: aspi) else { return 0 }
        return Int(getSynthParameter(aspp))
    }

    open func setPattern(forIndex inputIndex: Int, _ value: Int) {

        let index = Int32((0...15).clamp(inputIndex))
        let aspi = Int32(S1Parameter.sequencerPattern00.rawValue + index)
        guard let aspp = S1Parameter(rawValue: aspi) else { return }
        internalAU?.setSynthParameter(aspp, value: Float(value) )
    }

    open func getOctaveBoost(forIndex inputIndex: Int) -> Bool {

        let index = (0...15).clamp(inputIndex)
        let asni = Int32(Int(S1Parameter.sequencerOctBoost00.rawValue) + index)
        guard let asnp = S1Parameter(rawValue: asni) else { return false }
        return getSynthParameter(asnp) > 0 ? true : false
    }

    open func setOctaveBoost(forIndex inputIndex: Int, _ value: Double) {

        let index = Int32((0...15).clamp(inputIndex))
        let aspi = Int32(S1Parameter.sequencerOctBoost00.rawValue + index)
        guard let aspp = S1Parameter(rawValue: aspi) else { return }
        internalAU?.setSynthParameter(aspp, value: Float(value) )
    }

    open func isNoteOn(forIndex inputIndex: Int) -> Bool {

        let index = (0...15).clamp(inputIndex)
        let asoi = Int32(Int(S1Parameter.sequencerNoteOn00.rawValue) + index)
        guard let asop = S1Parameter(rawValue: asoi) else { return false }
        return ( getSynthParameter(asop) > 0 ) ? true : false
    }

    open func setNoteOn(forIndex inputIndex: Int, _ value: Bool) {

        let index = Int32((0...15).clamp(inputIndex))
        let aspi = Int32(S1Parameter.sequencerNoteOn00.rawValue + index)
        guard let aspp = S1Parameter(rawValue: aspi) else { return }
        internalAU?.setSynthParameter(aspp, value: Float(value == true ? 1 : 0) )
    }

    /// "parameter[i]" syntax is inefficient...use getter/setters above
    open var parameters: [Double] {

        get {
            var result: [Double] = []
            if let floatParameters = internalAU?.parameters as? [NSNumber] {
                for number in floatParameters {
                    result.append(number.doubleValue)
                }
            }
            return result
        }
        set {
            internalAU?.parameters = newValue

            if internalAU?.isSetUp ?? false {
                if let existingToken = token {
                    for (index, parameter) in auParameters.enumerated() {
                        if Double(parameter.value) != newValue[index] {
                            parameter.setValue( Float( newValue[index]), originator: existingToken)
                        }
                    }
                }
            } else {
                internalAU?.parameters = newValue
            }
        }
    }

    /// Ramp Time represents the speed at which parameters are allowed to change
    @objc open dynamic var rampDuration: Double = 0.0 {

        willSet {
            internalAU?.rampDuration = newValue
        }
    }

    // MARK: - Initialization

    /// Initialize the synth with defaults
    // PORT (P4-2): upstream decodes the 52 wavetables inline here. That loading is
    // now `S1Wavetables`, because the **AUv3 has no `AKSynthOne`** — the plugin is
    // handed an `S1AudioUnit` by its host and needs the same tables. One copy, two
    // callers.
    public convenience override init() {
        let tables = (try? S1Wavetables.load()) ?? S1Wavetables.Tables(waveforms: [],
                                                                      bandlimitFrequencies: [])
        if tables.waveforms.isEmpty {
            AKLog("AKSynthOne: no oscillator tables — the synth will be silent")
        }
        self.init(waveformArray: tables.waveforms, bandlimitArray: tables.bandlimitFrequencies)
    }

    /// Initialize this synth
    ///
    /// - parameter waveformArray: An array of 4 waveforms
    ///
    public init(waveformArray: [AKTable], bandlimitArray: [Float]) {

        self.waveformArray = waveformArray
        _Self.register()

        super.init()
        AVAudioUnit._instantiate(with: _Self.ComponentDescription) { [weak self] avAudioUnit in

            self?.avAudioNode = avAudioUnit
            self?.midiInstrument = avAudioUnit as? AVAudioUnitMIDIInstrument
            self?.internalAU = avAudioUnit.auAudioUnit as? AKAudioUnitType
            for i in 0..<AKSynthOne.SNUMBANDLIMITEDFTABLES {
                self?.internalAU?.setBandlimitFrequency(UInt32(i), withFrequency: bandlimitArray[i])
                for j in 0..<AKSynthOne.SNUMWAVEFORMS {
                    let tableIndex = i * AKSynthOne.SNUMWAVEFORMS + j
                    self?.internalAU?.setupWaveform(UInt32(tableIndex), size: Int32(AKSynthOne.SFTABLESIZE))
                    let waveform: AKTable = waveformArray[tableIndex]
                    for (k, sample) in waveform.enumerated() {
                        self?.internalAU?.setWaveform(UInt32(tableIndex), withValue: sample, at: UInt32(k))
                    }
                }
            }
            self?.internalAU?.parameters = self?.parameters
            self?.internalAU?.s1Delegate = self
        }

        guard let tree = internalAU?.parameterTree else {
            return
        }
        auParameters = tree.allParameters

        token = tree.token(byAddingParameterObserver: { address, value in
            guard let parameter: S1Parameter = S1Parameter(rawValue: Int32(address)) else {
                return
            }
            self.postNotification(parameter, Double(value) )
        })

        internalAU?.s1Delegate = self
    }

    @objc open weak var delegate: S1Protocol?

    internal func postNotification(_ parameter: S1Parameter, _ value: Double) {

        AKLog("unused")
    }

    /// stops all notes
    open func reset() {

        internalAU?.reset()
    }

    // MARK: - AKPolyphonic

    // Function to start, play, or activate the node at frequency
    open override func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, frequency: Double, channel: MIDIChannel) {

        internalAU?.startNote(noteNumber, velocity: velocity, frequency: Float(frequency))
    }

    /// Function to stop or bypass the node, both are equivalent
    open override func stop(noteNumber: MIDINoteNumber) {

        internalAU?.stopNote(noteNumber)
    }

    // MARK: - Passthroughs for AKSynthOneProtocol called by DSP on main thread

    @objc public func dependentParameterDidChange(_ parameter: DependentParameter) {

        delegate?.dependentParameterDidChange(parameter)
    }

    @objc public func arpBeatCounterDidChange(_ beat: S1ArpBeatCounter) {

        delegate?.arpBeatCounterDidChange(beat)
    }

    @objc public func heldNotesDidChange(_ heldNotes: HeldNotes) {

        delegate?.heldNotesDidChange(heldNotes)
    }

    @objc public func playingNotesDidChange(_ playingNotes: PlayingNotes) {

        delegate?.playingNotesDidChange(playingNotes)
    }

}


extension AKSynthOne: S1TuningTable {

    public func setTuningTableNPO(_ npo: Int) {

        internalAU?.setTuningTableNPO(Int32(npo))
    }

    public func setTuningTable(_ frequency: Double, index: Int) {

        internalAU?.setTuningTable(Float(frequency), index: Int32(index))
    }

    public func getTuningTableFrequency(_ index: Int) -> Double {

        return Double(internalAU?.getTuningTableFrequency(Int32(index)) ?? 440)
    }

}
