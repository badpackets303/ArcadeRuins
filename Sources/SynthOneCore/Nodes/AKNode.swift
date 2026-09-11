//  Ported from AudioKit 4.9.2 `AKNode.swift` (MIT). Names kept per ADR-009, so
//  `AKSynthOne.swift` and the Phase-3 UI port with their `AK*` references intact.
//
//  Trimmed to what Synth One actually uses. Left behind:
//  - the `AKOutput` connection-point DSL. Synth One never uses it; it builds its
//    graph by hand in `Conductor.start()`.
//  - the deprecated members (`disconnect`, `addConnectionPoint`).
//  - **every reference to the global `AudioKit.engine`.** Upstream nodes attach
//    themselves to a process-wide singleton engine. Ours do not — the engine is
//    an object you hold (`S1AudioEngine`). See ADR-014.

import AVFoundation
import S1Support

/// Parent class for all nodes.
@objc open class AKNode: NSObject {

    /// The internal AVAudioEngine AVAudioNode
    @objc open var avAudioNode: AVAudioNode

    /// The internal AVAudioUnit, which is a subclass of AVAudioNode with more capabilities
    @objc open var avAudioUnit: AVAudioUnit?

    /// Returns either the avAudioUnit (preferred) or the avAudioNode
    @objc open var avAudioUnitOrNode: AVAudioNode {
        return self.avAudioUnit ?? self.avAudioNode
    }

    /// Create the node
    public override init() {
        self.avAudioNode = AVAudioNode()
    }

    /// Initialize the node from an AVAudioUnit
    @objc public init(avAudioUnit: AVAudioUnit) {
        self.avAudioUnit = avAudioUnit
        self.avAudioNode = avAudioUnit
    }

    /// Initialize the node from an AVAudioNode
    @objc public init(avAudioNode: AVAudioNode) {
        self.avAudioNode = avAudioNode
    }

    /// PORT: upstream detaches from `AudioKit.engine`. Ask the node which engine
    /// it is actually attached to instead — there is no singleton to consult.
    open func detach() {
        let node = avAudioUnitOrNode
        node.engine?.detach(node)
    }
}

/// Protocol for responding to play and stop of MIDI notes
public protocol AKPolyphonic {

    /// Play a sound corresponding to a MIDI note
    ///
    /// - Parameters:
    ///   - noteNumber: MIDI Note Number
    ///   - velocity:   MIDI Velocity
    ///   - frequency:  Play this frequency
    func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, frequency: Double, channel: MIDIChannel)

    /// Play a sound corresponding to a MIDI note
    ///
    /// - Parameters:
    ///   - noteNumber: MIDI Note Number
    ///   - velocity:   MIDI Velocity
    ///
    func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel)

    /// Stop a sound corresponding to a MIDI note
    ///
    /// - parameter noteNumber: MIDI Note Number
    ///
    func stop(noteNumber: MIDINoteNumber)
}

/// Bare bones implementation of AKPolyphonic protocol
@objc open class AKPolyphonicNode: AKNode, AKPolyphonic {

    /// Global tuning table used by AKPolyphonicNode (AKNode classes adopting AKPolyphonic protocol).
    ///
    /// Static on purpose: the Tunings panel (Phase 3) sets it and every polyphonic
    /// node reads it. Upstream shape, kept deliberately.
    ///
    /// PORT: upstream marks this `@objc`. We cannot — `AKTuningTable` lives in the
    /// `S1Support` *static library*, and an `@objc` member would put it in
    /// `SynthOneCore-Swift.h`, which every consumer of the framework parses and
    /// none of them can resolve `S1Support` from. See ADR-014. Nothing calls it
    /// from Obj-C.
    public static var tuningTable = AKTuningTable()

    open var midiInstrument: AVAudioUnitMIDIInstrument?

    /// Play a sound corresponding to a MIDI note with frequency
    @objc open func play(noteNumber: MIDINoteNumber,
                         velocity: MIDIVelocity,
                         frequency: Double,
                         channel: MIDIChannel = 0) {
        AKLog("Playing note: \(noteNumber), velocity: \(velocity), frequency: \(frequency), " +
              "channel: \(channel), override in subclass")
    }

    /// Play a sound corresponding to a MIDI note
    @objc open func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel = 0) {
        // MARK: Microtonal pitch lookup

        // default implementation is 12 ET
        let frequency = AKPolyphonicNode.tuningTable.frequency(forNoteNumber: noteNumber)
        self.play(noteNumber: noteNumber, velocity: velocity, frequency: frequency, channel: channel)
    }

    /// Stop a sound corresponding to a MIDI note
    @objc open func stop(noteNumber: MIDINoteNumber) {
        AKLog("Stopping note \(noteNumber), override in subclass")
    }

    deinit {
        detach()
    }
}
