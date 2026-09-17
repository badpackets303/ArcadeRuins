//  What the interface needs from "the synth" (P4-6).
//
//  ## Why this exists
//
//  The 12 panels reach the DSP through `Conductor.synth`, which is an `AKSynthOne`
//  — an `AKPolyphonicNode` that creates its own audio unit and lives in an
//  `AVAudioEngine`. A plugin has none of that: the host hands us an `S1AudioUnit`
//  directly, owns the graph, and an AUv3 must never touch `AVAudioEngine.outputNode`
//  (ADR-015).
//
//  Rather than fork the interface, `Conductor.synth` is typed as this protocol and
//  both worlds satisfy it: `AKSynthOne` in the standalone, a bare `S1AudioUnit` in
//  the plugin. **All 153 UI files are unchanged** — hard requirement 1 is preserving
//  the interface, and the cheapest way to preserve something is not to touch it.
//
//  ## Why it is this size
//
//  Measured, not guessed: the whole interface reaches the synth through **15
//  members**, across about forty call sites. That is what is here, plus the four
//  `Conductor` itself needs. Anything the audio *graph* needs — `AKMixer(synth)`,
//  `SDSustainer(synth)`, the output plot — is deliberately absent, because those are
//  exactly the things a plugin does not have.

import Foundation
import AudioToolbox
import S1Support

/// The synth as the user interface sees it.
///
/// Inherits `S1PresetSink` (P4-4), which already covered the write half a preset
/// needs; this adds the reads, the ranges, and the tuning table.
public protocol S1SynthControlling: S1PresetSink, S1TuningTable {

    // MARK: Parameters

    func getSynthParameter(_ parameter: S1Parameter) -> Double

    /// lfo1Rate, lfo2Rate, autoPanFrequency, delayTime, arpSeqTempoMultiplier —
    /// normalised to [0,1] for the UI, because the DSP quantizes them (ADR-022).
    func getDependentParameter(_ parameter: S1Parameter) -> Double
    func setDependentParameter(_ parameter: S1Parameter, _ value: Double, _ payload: Int32)

    // MARK: Ranges

    func getMinimum(_ parameter: S1Parameter) -> Double
    func getMaximum(_ parameter: S1Parameter) -> Double
    func getRange(_ parameter: S1Parameter) -> ClosedRange<Double>
    func getDefault(_ parameter: S1Parameter) -> Double

    /// The DSP's own default for every parameter — what a preset falls back to for a
    /// key its JSON does not carry.
    var presetDefaults: PresetDefaults { get }

    // MARK: Sequencer reads

    func getPattern(forIndex index: Int) -> Int
    func getOctaveBoost(forIndex index: Int) -> Bool
    func isNoteOn(forIndex index: Int) -> Bool

    // MARK: Notes

    /// Every note into release.
    func reset()
    /// Panic. Hard-resets the DSP, with artifacts.
    func resetDSP()
    func stopAllNotes()

    // Tuning comes from `S1TuningTable`, which `AKSynthOne` already conforms to —
    // redeclaring it here with the audio unit's `Float`/`Int32` shapes was the first
    // attempt and it failed the conformance, because the *call sites* use the node's
    // `Double`/`Int` ones.
}

// `AKSynthOne` already has every one of these with these signatures — this is the
// conformance, not an implementation. That it compiles is the evidence that the
// protocol was extracted from the real call sites rather than invented.
extension AKSynthOne: S1SynthControlling {}

// MARK: - The plugin's side

/// Wraps the audio unit a host hands the plugin, so the interface can drive it.
///
/// **A wrapper rather than an extension on `S1AudioUnit`.** The obvious move is to
/// conform the audio unit itself, and it does not work: `S1AudioUnit` is Obj-C++, so
/// its getters already exist in Swift returning `Float`, and adding `Double` versions
/// with the same names overloads purely by return type. Every existing call site then
/// becomes ambiguous — including inside the extension trying to define them. The
/// setters are fine (`setSynthParameter(_:value:)` vs `(_:_:)` differ by label),
/// which is why `S1PresetSink` could be an extension and this cannot.
///
/// It is also the right shape: this is the plugin's stand-in for `AKSynthOne`, and a
/// place for anything else hosted mode needs that the node used to provide.
public final class S1HostedSynth: S1SynthControlling {

    public let audioUnit: S1AudioUnit

    /// One `AUParameter` per address, looked up once. The UI writes on every drag
    /// tick, and `parameter(withAddress:)` walks the tree each time.
    private let parameters: [AUParameter?]

    /// Identifies *us* as the originator of a write, so the observer below does not
    /// hear our own changes and echo them back at the host as fresh automation.
    ///
    /// ⚠️ **Only within one process.** See `echoWindow`.
    private var observerToken: AUParameterObserverToken?

    /// How long after the interface writes a parameter that a host report of a change
    /// to it is taken to be the host **echoing that write back**.
    ///
    /// The originator token is not enough on its own. Out of process — which is how
    /// Logic runs the plugin — every write comes back into the extension's tree as if
    /// the host had made it. Measured in Logic on 2026-09-10 with a debugger on the
    /// running extension: dragging the mod wheel fired the observer 574 times in two
    /// minutes, each echo tens of milliseconds behind its write and carrying values from
    /// earlier in the drag, and every one landed on the controls as a host move. The
    /// in-process tests could not see it, because there the token works. ADR-030.
    ///
    /// Internal so tests can shorten it.
    var echoWindow: TimeInterval = 0.5

    /// When the interface last wrote each address, and what it wrote. Written by the
    /// interface and read on the main queue, so it is locked.
    private var localWrites: [AUParameterAddress: (time: TimeInterval, value: AUValue, before: AUValue)] = [:]
    private let localWritesLock = NSLock()

    /// Addresses with a reconciliation already scheduled. Main queue only.
    private var pendingReconciles: Set<AUParameterAddress> = []

    public init(audioUnit: S1AudioUnit) {
        self.audioUnit = audioUnit
        let tree = audioUnit.parameterTree
        parameters = (0..<Int(S1Parameter.S1ParameterCount.rawValue)).map {
            tree?.parameter(withAddress: AUParameterAddress($0))
        }
    }

    private func auParameter(_ parameter: S1Parameter) -> AUParameter? {
        let index = Int(parameter.rawValue)
        return parameters.indices.contains(index) ? parameters[index] : nil
    }

    // MARK: - Host binding (P4-6)

    /// Report host-originated parameter changes, on the main thread.
    ///
    /// Changes *we* make are excluded: `token(byAddingParameterObserver:)` does not
    /// call back for writes whose originator is its own token, which is the standard
    /// way to avoid the loop where a host move updates a knob, the knob writes back,
    /// and the host records an automation point the user never made.
    public func observeHostChanges(_ onChange: @escaping (S1Parameter, Double) -> Void) {
        guard let tree = audioUnit.parameterTree else { return }
        // Weak: the tree belongs to the audio unit, which this object holds.
        observerToken = tree.token(byAddingParameterObserver: { [weak self] address, value in
            // The observer is called on an arbitrary thread — often the render
            // thread's automation dispatch — and this ends in UIKit.
            DispatchQueue.main.async { self?.hostChanged(address, value, onChange) }
        })
    }

    private func hostChanged(_ address: AUParameterAddress, _ value: AUValue,
                             _ onChange: @escaping (S1Parameter, Double) -> Void) {
        guard let parameter = S1Parameter(rawValue: Int32(address)) else { return }
        if isInsideEchoWindow(address) {
            // Almost certainly our own write coming back. It *could* be automation that
            // landed while the control was moving, so look again once the interface has
            // gone quiet rather than dropping it outright.
            reconcileWhenQuiet(address, parameter, onChange)
            return
        }
        onChange(parameter, Double(value))
    }

    private func localWrite(_ address: AUParameterAddress) -> (time: TimeInterval, value: AUValue, before: AUValue)? {
        localWritesLock.lock()
        defer { localWritesLock.unlock() }
        return localWrites[address]
    }

    private func isInsideEchoWindow(_ address: AUParameterAddress) -> Bool {
        guard let write = localWrite(address) else { return false }
        return ProcessInfo.processInfo.systemUptime - write.time < echoWindow
    }

    /// Once the interface has left `address` alone for a whole window, report what the
    /// DSP holds — but only if it is not what the interface last wrote. A pure echo ends
    /// with the two agreeing, and reports nothing.
    private func reconcileWhenQuiet(_ address: AUParameterAddress, _ parameter: S1Parameter,
                                    _ onChange: @escaping (S1Parameter, Double) -> Void) {
        guard pendingReconciles.insert(address).inserted else { return }
        let elapsed = localWrite(address).map { ProcessInfo.processInfo.systemUptime - $0.time } ?? echoWindow
        let wait = max(echoWindow - elapsed, 0) + 0.01

        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.pendingReconciles.remove(address)
            if self.isInsideEchoWindow(address) {
                // Written again since: wait for that window to close instead.
                self.reconcileWhenQuiet(address, parameter, onChange)
                return
            }
            guard let written = self.localWrite(address)?.value,
                  let auParameter = self.auParameter(parameter) else { return }
            // The DSP clamps to the same range the tree declares.
            let expected = min(max(written, auParameter.minValue), auParameter.maxValue)
            let actual = self.audioUnit.getSynthParameter(parameter)
            let tolerance = max((auParameter.maxValue - auParameter.minValue) * 1e-5, 1e-6)
            if abs(actual - expected) > tolerance {
                onChange(parameter, Double(actual))
            }
        }
    }

    // MARK: S1PresetSink

    /// **Writes go through the parameter tree, not straight to the DSP.**
    ///
    /// This is the difference between a plugin whose knobs work and a plugin a host
    /// can automate. Setting `AUParameter.value` tells the host — so Logic records a
    /// knob move — and reaches the DSP through `implementorValueObserver` and
    /// `startRamp` (ADR-022), which is the same path host automation takes. Writing
    /// to the kernel directly would move the sound and leave the host knowing
    /// nothing.
    ///
    /// The originator token marks the write as ours, so `observeHostChanges` does not
    /// hear it and push it back into the control that just moved — and `localWrites`
    /// catches the copy a host sends back when the plugin runs out of process.
    public func setSynthParameter(_ parameter: S1Parameter, _ value: Double) {
        guard let auParameter = auParameter(parameter) else {
            // No address in the tree — nothing to record, so go straight to the DSP.
            audioUnit.setSynthParameter(parameter, value: Float(value))
            return
        }
        localWritesLock.lock()
        localWrites[auParameter.address] = (ProcessInfo.processInfo.systemUptime, AUValue(value),
                                            audioUnit.getSynthParameter(parameter))
        localWritesLock.unlock()
        auParameter.setValue(AUValue(value), originator: observerToken)
    }

    public func setPattern(forIndex index: Int, _ value: Int) {
        audioUnit.setPattern(forIndex: index, value)
    }

    public func setOctaveBoost(forIndex index: Int, _ value: Double) {
        audioUnit.setOctaveBoost(forIndex: index, value)
    }

    public func setNoteOn(forIndex index: Int, _ value: Bool) {
        audioUnit.setNoteOn(forIndex: index, value)
    }

    public func resetSequencer() { audioUnit.resetSequencer() }

    // MARK: Parameters

    /// **A read sees the interface's own write while it is still on its way** (ADR-063). A
    /// write goes through the parameter tree and, once render resources are allocated, reaches
    /// the DSP at the next render (ADR-022); for up to a block the kernel holds the old value.
    /// Upstream's interface reads straight back after writing, as it could when the kernel was
    /// written directly: the mod wheel sets the cutoff and tells the Cutoff knob
    /// `getSynthParameter(.cutoff)`; the XY pads settle and ask where the cutoff is. Answered
    /// from the kernel, those put the knob and the wheel back where they were, and nothing
    /// corrected them, because a write that lands as written is never reported.
    ///
    /// This is **not a cache** (`testParametersRoundTripThroughTheDSP` forbids one, rightly: it
    /// would be wrong the moment a host automated anything). The written value is the answer
    /// only while the kernel still holds exactly what it held when the write was made — that is,
    /// while nothing at all has reached it. The moment it holds anything else, ours or the
    /// host's, the kernel answers.
    public func getSynthParameter(_ parameter: S1Parameter) -> Double {
        let actual = audioUnit.getSynthParameter(parameter)
        if let auParameter = auParameter(parameter), let write = localWrite(auParameter.address),
           actual == write.before, write.before != write.value, isInsideEchoWindow(auParameter.address) {
            return Double(min(max(write.value, auParameter.minValue), auParameter.maxValue))
        }
        return Double(actual)
    }

    public func getDependentParameter(_ parameter: S1Parameter) -> Double {
        Double(audioUnit.getDependentParameter(parameter))
    }

    public func setDependentParameter(_ parameter: S1Parameter, _ value: Double, _ payload: Int32) {
        audioUnit.setDependentParameter(parameter, value: Float(value), payload: payload)
    }

    // MARK: Ranges

    public func getMinimum(_ parameter: S1Parameter) -> Double { Double(audioUnit.getMinimum(parameter)) }
    public func getMaximum(_ parameter: S1Parameter) -> Double { Double(audioUnit.getMaximum(parameter)) }
    public func getDefault(_ parameter: S1Parameter) -> Double { Double(audioUnit.getDefault(parameter)) }

    public func getRange(_ parameter: S1Parameter) -> ClosedRange<Double> {
        let low = getMinimum(parameter)
        let high = getMaximum(parameter)
        // Defensive: a reversed range traps, and a wrong knob does not.
        return low <= high ? low...high : high...low
    }

    public var presetDefaults: PresetDefaults {
        { [weak self] parameter in self?.getDefault(parameter) ?? 0 }
    }

    // MARK: Sequencer reads

    public func getPattern(forIndex index: Int) -> Int {
        guard let parameter = S1HostedSynth.sequencerParameter(.sequencerPattern00, index) else { return 0 }
        return Int(audioUnit.getSynthParameter(parameter))
    }

    public func getOctaveBoost(forIndex index: Int) -> Bool {
        guard let parameter = S1HostedSynth.sequencerParameter(.sequencerOctBoost00, index) else { return false }
        return audioUnit.getSynthParameter(parameter) > 0
    }

    public func isNoteOn(forIndex index: Int) -> Bool {
        guard let parameter = S1HostedSynth.sequencerParameter(.sequencerNoteOn00, index) else { return false }
        return audioUnit.getSynthParameter(parameter) > 0
    }

    /// The 16 sequencer steps are contiguous parameter addresses, so a step is
    /// `base + index`.
    static func sequencerParameter(_ base: S1Parameter, _ index: Int) -> S1Parameter? {
        guard (0...15).contains(index) else { return nil }
        return S1Parameter(rawValue: base.rawValue + Int32(index))
    }

    // MARK: Notes

    // ADR-031: all three run on the render thread, where host MIDI is handled. See
    // `playKeyOnRenderThread` in S1AudioUnit.h for why the main thread no longer calls them.
    public func reset() { audioUnit.resetOnRenderThread() }
    public func resetDSP() { audioUnit.resetDSPOnRenderThread() }
    public func stopAllNotes() { audioUnit.stopAllNotesOnRenderThread() }

    // MARK: S1TuningTable

    public func setTuningTable(_ frequency: Double, index: Int) {
        audioUnit.setTuningTable(Float(frequency), index: Int32(index))
    }

    public func getTuningTableFrequency(_ index: Int) -> Double {
        Double(audioUnit.getTuningTableFrequency(Int32(index)))
    }

    public func setTuningTableNPO(_ npo: Int) { audioUnit.setTuningTableNPO(Int32(npo)) }
}

// MARK: - Notes

/// The on-screen keyboard and the sustain pedal play through `SDSustainer`, which
/// wrapped an `AKPolyphonicNode`. In the plugin there is no node, so it wraps this
/// instead — the three requirements are all the sustainer ever used.
///
/// **Queued to the render thread (ADR-031).** Host notes are played there, and the kernel's
/// note bookkeeping is not safe to touch from two threads at once. A key sounds at the start of
/// the host's next render cycle.
extension S1HostedSynth: AKPolyphonic {

    /// `frequency` is not passed on, and never mattered: `S1DSPKernel::startNote` recomputes
    /// it from the tuning table and `transpose` whatever it is handed.
    public func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity,
                     frequency: Double, channel: MIDIChannel = 0) {
        audioUnit.playKeyOnRenderThread(noteNumber, velocity: velocity)
    }

    /// Microtonal lookup, exactly as `AKPolyphonicNode` does it — the Tunings panel
    /// writes the shared table and this is what reads it.
    public func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel = 0) {
        let frequency = AKPolyphonicNode.tuningTable.frequency(forNoteNumber: noteNumber)
        play(noteNumber: noteNumber, velocity: velocity, frequency: Double(frequency), channel: channel)
    }

    public func stop(noteNumber: MIDINoteNumber) {
        audioUnit.releaseKeyOnRenderThread(noteNumber)
    }
}
