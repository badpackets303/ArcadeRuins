//  Preset -> synth, extracted from `PresetDataManager.loadPreset()` (P2-4).
//
//  Upstream this lives in an extension on `Manager`, the top-level view
//  controller, tangled up with three things that are genuinely the UI's business:
//  the DEV panel's "freeze delay / reverb / arp" toggles, the tunings panel, and
//  `conductor.updateDefaultValues()`. The *mapping itself* — 100 lines of preset
//  field to `S1Parameter` — is not UI at all, and P2-4 needs it to render the
//  shipped banks as golden audio.
//
//  So the mapping moves here, verbatim and in upstream's order, and Phase 3's
//  `loadPreset()` becomes a thin wrapper that applies the freeze toggles and the
//  tuning around a call to this. Nothing is reordered: `setSynthParameter` writes
//  can be order-dependent through `S1DSPKernel::_setSynthParameter`'s dependent
//  parameters, so keeping upstream's sequence is not cosmetic.

import Foundation
import S1Support

extension Preset {

    /// Apply every parameter this preset carries to `s`.
    ///
    /// Deliberately *not* included, because they belong to the caller:
    /// - the `appSettings.freeze*` toggles, which skip subsets of this
    /// - `tuningsPanel.setTuning(...)` / `setDefaultTuning()`
    /// - `conductor.updateDefaultValues()`
    /// PORT (P4-4): upstream's parameter is `AKSynthOne`. It is now `S1PresetSink`,
    /// which `AKSynthOne` conforms to unchanged — the plugin is handed a bare
    /// `S1AudioUnit` with no node wrapper, and duplicating this hundred-line mapping
    /// to serve it would be two places to get the order wrong. The body is untouched.
    func apply(to s: S1PresetSink) {
        s.setSynthParameter(.delayOn, self.delayToggled)
        s.setSynthParameter(.delayFeedback, self.delayFeedback)
        s.setSynthParameter(.delayMix, self.delayMix)
        s.setSynthParameter(.delayTime, self.delayTime)
        s.setSynthParameter(.delayInputCutoffTrackingRatio, self.delayInputCutoffTrackingRatio)
        s.setSynthParameter(.delayInputResonance, self.delayInputResonance)
        s.setSynthParameter(.reverbOn, self.reverbToggled)
        s.setSynthParameter(.reverbFeedback, self.reverbFeedback)
        s.setSynthParameter(.reverbHighPass, self.reverbHighPass)
        s.setSynthParameter(.reverbMix, self.reverbMix)
        s.setSynthParameter(.compressorReverbInputRatio, self.compressorReverbInputRatio)
        s.setSynthParameter(.compressorReverbWetRatio, self.compressorReverbWetRatio)
        s.setSynthParameter(.compressorReverbInputThreshold, self.compressorReverbInputThreshold)
        s.setSynthParameter(.compressorReverbWetThreshold, self.compressorReverbWetThreshold)
        s.setSynthParameter(.compressorReverbInputAttack, self.compressorReverbInputAttack)
        s.setSynthParameter(.compressorReverbWetAttack, self.compressorReverbWetAttack)
        s.setSynthParameter(.compressorReverbInputRelease, self.compressorReverbInputRelease)
        s.setSynthParameter(.compressorReverbWetRelease, self.compressorReverbWetRelease)
        s.setSynthParameter(.compressorReverbInputMakeupGain, self.compressorReverbInputMakeupGain)
        s.setSynthParameter(.compressorReverbWetMakeupGain, self.compressorReverbWetMakeupGain)
        s.setSynthParameter(.arpRate, self.arpRate)
        s.setSynthParameter(.arpIsOn, self.isArpMode)
        s.setSynthParameter(.arpIsSequencer, self.arpIsSequencer ? 1 : 0 )
        s.setSynthParameter(.arpDirection, self.arpDirection)
        s.setSynthParameter(.arpInterval, self.arpInterval)
        s.setSynthParameter(.arpOctave, self.arpOctave)
        s.setSynthParameter(.arpTotalSteps, self.arpTotalSteps )
        s.setSynthParameter(.arpSeqTempoMultiplier, self.arpSeqTempoMultiplier)
        for i in 0..<16 {
            s.setPattern(forIndex: i, self.seqPatternNote[i])
            s.setOctaveBoost(forIndex: i, self.seqOctBoost[i] ? 1 : 0)
            s.setNoteOn(forIndex: i, self.seqNoteOn[i])
        }
        s.setSynthParameter(.tempoSyncToArpRate, self.tempoSyncToArpRate)
        s.setSynthParameter(.lfo1Rate, self.lfoRate)
        s.setSynthParameter(.lfo2Rate, self.lfo2Rate)
        s.setSynthParameter(.autoPanFrequency, self.autoPanFrequency)
        s.setSynthParameter(.masterVolume, self.masterVolume)
        s.setSynthParameter(.isMono, self.isMono)
        s.setSynthParameter(.glide, self.glide)
        s.setSynthParameter(.widen, self.widen)
        s.setSynthParameter(.index1, self.waveform1)
        s.setSynthParameter(.index2, self.waveform2)
        s.setSynthParameter(.morph1SemitoneOffset, self.vco1Semitone)
        s.setSynthParameter(.morph2SemitoneOffset, self.vco2Semitone)
        s.setSynthParameter(.morph2Detuning, self.vco2Detuning)
        s.setSynthParameter(.morph1Volume, self.vco1Volume)
        s.setSynthParameter(.morph2Volume, self.vco2Volume)
        s.setSynthParameter(.morphBalance, self.vcoBalance)
        s.setSynthParameter(.subVolume, self.subVolume)
        s.setSynthParameter(.subOctaveDown, self.subOsc24Toggled)
        s.setSynthParameter(.subIsSquare, self.subOscSquareToggled)
        s.setSynthParameter(.fmVolume, self.fmVolume)
        s.setSynthParameter(.fmAmount, self.fmAmount)
        s.setSynthParameter(.noiseVolume, self.noiseVolume)
        s.setSynthParameter(.cutoff, self.cutoff)
        s.setSynthParameter(.resonance, self.resonance)
        s.setSynthParameter(.filterADSRMix, self.filterADSRMix)
        s.setSynthParameter(.filterAttackDuration, self.filterAttack)
        s.setSynthParameter(.filterDecayDuration, self.filterDecay)
        s.setSynthParameter(.filterSustainLevel, self.filterSustain)
        s.setSynthParameter(.filterReleaseDuration, self.filterRelease)
        s.setSynthParameter(.attackDuration, self.attackDuration)
        s.setSynthParameter(.decayDuration, self.decayDuration)
        s.setSynthParameter(.sustainLevel, self.sustainLevel)
        s.setSynthParameter(.releaseDuration, self.releaseDuration)
        s.setSynthParameter(.bitCrushSampleRate, self.crushFreq)
        s.setSynthParameter(.autoPanAmount, self.autoPanAmount)
        s.setSynthParameter(.lfo1Index, self.lfoWaveform)
        s.setSynthParameter(.lfo1Amplitude, self.lfoAmplitude)
        s.setSynthParameter(.lfo2Index, self.lfo2Waveform)
        s.setSynthParameter(.lfo2Amplitude, self.lfo2Amplitude)
        s.setSynthParameter(.cutoffLFO, self.cutoffLFO)
        s.setSynthParameter(.resonanceLFO, self.resonanceLFO)
        s.setSynthParameter(.oscMixLFO, self.oscMixLFO)
        s.setSynthParameter(.reverbMixLFO, self.reverbMixLFO)
        s.setSynthParameter(.decayLFO, self.decayLFO)
        s.setSynthParameter(.noiseLFO, self.noiseLFO)
        s.setSynthParameter(.fmLFO, self.fmLFO)
        s.setSynthParameter(.detuneLFO, self.detuneLFO)
        s.setSynthParameter(.filterEnvLFO, self.filterEnvLFO)
        s.setSynthParameter(.pitchLFO, self.pitchLFO)
        s.setSynthParameter(.bitcrushLFO, self.bitcrushLFO)
        s.setSynthParameter(.tremoloLFO, self.tremoloLFO)
        s.setSynthParameter(.monoIsLegato, self.isLegato )
        s.setSynthParameter(.phaserMix, self.phaserMix)
        s.setSynthParameter(.phaserRate, self.phaserRate)
        s.setSynthParameter(.phaserFeedback, self.phaserFeedback)
        s.setSynthParameter(.phaserNotchWidth, self.phaserNotchWidth)
        s.setSynthParameter(.filterType, self.filterType)
        s.setSynthParameter(.compressorMasterThreshold, self.compressorMasterThreshold)
        s.setSynthParameter(.compressorMasterRatio, self.compressorMasterRatio)
        s.setSynthParameter(.compressorMasterAttack, self.compressorMasterAttack)
        s.setSynthParameter(.compressorMasterRelease, self.compressorMasterRelease)
        s.setSynthParameter(.compressorMasterMakeupGain, self.compressorMasterMakeupGain)
        s.setSynthParameter(.pitchbendMinSemitones, self.pitchbendMinSemitones)
        s.setSynthParameter(.pitchbendMaxSemitones, self.pitchbendMaxSemitones)
        s.setSynthParameter(.frequencyA4, self.frequencyA4)
        s.setSynthParameter(.oscBandlimitEnable, self.oscBandlimitEnable)
        s.setSynthParameter(.transpose, Double(self.transpose))
        s.setSynthParameter(.adsrPitchTracking, self.adsrPitchTracking)
        s.resetSequencer()
    }
}
