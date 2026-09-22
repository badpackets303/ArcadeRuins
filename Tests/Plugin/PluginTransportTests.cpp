// X2-6 (ADR-077): the host's tempo and transport, as a host gives them — through a play head,
// read inside processBlock — and what comes out: step times measured from the rendered audio,
// the tempo-dependent parameters reported, the transport's stop heard.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"

namespace {

constexpr double kSampleRate = 44100.0;

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

struct HostEars final : juce::AudioProcessorParameter::Listener {
    int values = 0, gestures = 0;
    void parameterValueChanged(int, float) override { ++values; }
    void parameterGestureChanged(int, bool) override { ++gestures; }
};

/// A host's transport: whatever the test says it is.
struct PlayHead final : juce::AudioPlayHead {
    bool hasPosition = true;
    juce::Optional<double> bpm;
    bool playing = false;
    juce::Optional<PositionInfo> getPosition() const override {
        if (!hasPosition) { return {}; }
        PositionInfo info;
        info.setBpm(bpm);
        info.setIsPlaying(playing);
        return info;
    }
};

/// A plugin in a host with a transport, rendered block by block.
struct Session {
    S1PluginProcessor processor;
    PlayHead playHead;
    int blockSize;
    juce::AudioBuffer<float> buffer;
    std::vector<float> recorded;   // left channel

    explicit Session(bool withPlayHead = true, int block = 512) : blockSize(block), buffer(2, block) {
        processor.setPlayConfigDetails(0, 2, kSampleRate, blockSize);
        if (withPlayHead) { processor.setPlayHead(&playHead); }
        processor.prepareToPlay(kSampleRate, blockSize);
    }
    void block(const juce::MidiBuffer &midi = {}) {
        juce::MidiBuffer copy = midi;
        processor.processBlock(buffer, copy);
        recorded.insert(recorded.end(), buffer.getReadPointer(0), buffer.getReadPointer(0) + blockSize);
    }
    void run(double seconds) {
        for (int i = 0; i < int(seconds * kSampleRate / blockSize) + 1; ++i) { block(); }
    }
    void send(const juce::MidiMessage &message, int sample = 0) {
        juce::MidiBuffer midi;
        midi.addEvent(message, sample);
        block(midi);
    }
    S1HostParameter &parameter(S1Parameter p) { return processor.hostParameter(p); }
    void hostWrites(S1Parameter p, float plain) { parameter(p).setValueNotifyingHost(parameter(p).convertTo0to1(plain)); }
    float plain(S1Parameter p) { return parameter(p).plainValue(); }

    /// A sound whose every note is a click: nothing before it, gone long before the next step.
    /// The arpeggiator goes up through the held keys, one sixteenth a step.
    void makeClicks() {
        hostWrites(S1Parameter::attackDuration, parameter(S1Parameter::attackDuration).getNormalisableRange().start);
        hostWrites(S1Parameter::decayDuration, 0.01f);
        hostWrites(S1Parameter::sustainLevel, 0.f);
        hostWrites(S1Parameter::releaseDuration, 0.01f);
        hostWrites(S1Parameter::filterADSRMix, 0.f);
        hostWrites(S1Parameter::cutoff, 20000.f);
        hostWrites(S1Parameter::reverbOn, 0.f);
        hostWrites(S1Parameter::delayOn, 0.f);
        hostWrites(S1Parameter::arpIsOn, 1.f);
        hostWrites(S1Parameter::arpIsSequencer, 0.f);
        hostWrites(S1Parameter::arpDirection, 0.f);
        hostWrites(S1Parameter::arpOctave, 0.f);
        hostWrites(S1Parameter::arpSeqTempoMultiplier, 0.25f);
        run(2.0);                  // every parameter's glide from 0 has arrived (ADR-013)
        recorded.clear();
    }

    /// Where each click begins: the first sample over a twentieth of the recording's peak after
    /// at least 25 ms under it. A recording that begins in the middle of a click says so, or the
    /// click's remainder counts as one.
    std::vector<size_t> onsets(bool beginsInSilence = true) const {
        float peak = 0;
        for (const float x : recorded) { peak = std::max(peak, std::fabs(x)); }
        const float threshold = peak / 20;
        const size_t quiet = size_t(0.025 * kSampleRate);
        std::vector<size_t> found;
        size_t under = beginsInSilence ? quiet : 0;
        for (size_t i = 0; i < recorded.size(); ++i) {
            if (std::fabs(recorded[i]) > threshold) {
                if (under >= quiet) { found.push_back(i); }
                under = 0;
            } else {
                ++under;
            }
        }
        return found;
    }
    /// The mean time between clicks in milliseconds, and the worst single departure from it.
    struct Steps { int count; double mean, worst; };
    Steps steps(bool beginsInSilence = true) const {
        const std::vector<size_t> at = onsets(beginsInSilence);
        if (at.size() < 3) { return { int(at.size()), 0, 1e9 }; }
        const double mean = double(at.back() - at.front()) / double(at.size() - 1);
        double worst = 0;
        for (size_t i = 1; i < at.size(); ++i) { worst = std::max(worst, std::fabs(double(at[i] - at[i - 1]) - mean)); }
        return { int(at.size()), mean * 1000.0 / kSampleRate, worst * 1000.0 / kSampleRate };
    }
    double level(double lastSeconds) const {
        const size_t count = std::min(recorded.size(), size_t(lastSeconds * kSampleRate));
        double squares = 0;
        for (size_t i = recorded.size() - count; i < recorded.size(); ++i) { squares += double(recorded[i]) * double(recorded[i]); }
        return std::sqrt(squares / double(std::max<size_t>(count, 1)));
    }
    /// The fundamental of `seconds` of the recording from sample `from`, by autocorrelation.
    double pitch(size_t from, double seconds) const {
        const size_t count = size_t(seconds * kSampleRate), end = std::min(recorded.size(), from + count);
        const size_t shortest = size_t(kSampleRate / 960.0), longest = size_t(kSampleRate / 90.0);
        std::vector<double> score(longest + 2, 0.0);
        for (size_t lag = shortest; lag <= longest + 1; ++lag) {
            double sum = 0;
            for (size_t i = from; i + lag < end; ++i) { sum += double(recorded[i]) * double(recorded[i + lag]); }
            score[lag] = sum / double(count - lag);
        }
        double best = -1e30; size_t bestLag = shortest + 1;
        for (size_t lag = shortest + 1; lag <= longest; ++lag) { best = std::max(best, score[lag]); }
        for (size_t lag = shortest + 1; lag <= longest; ++lag) {
            if (score[lag] > 0.9 * best && score[lag] >= score[lag - 1] && score[lag] >= score[lag + 1]) { bestLag = lag; break; }
        }
        const double a = score[bestLag - 1], b = score[bestLag], c = score[bestLag + 1];
        return kSampleRate / (double(bestLag) + (a - c) / (2 * (a - 2 * b + c)));
    }
    void holdChord() {
        juce::MidiBuffer midi;
        for (const int note : { 48, 55, 64 }) { midi.addEvent(juce::MidiMessage::noteOn(1, note, juce::uint8(110)), 0); }
        block(midi);
    }
    void releaseChord() {
        juce::MidiBuffer midi;
        for (const int note : { 48, 55, 64 }) { midi.addEvent(juce::MidiMessage::noteOff(1, note), 0); }
        block(midi);
    }
};

bool near(double value, double expected, double tolerance) { return std::fabs(value - expected) <= tolerance; }

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);

    // MARK: the host's tempo is the tempo
    {
        Session s;
        s.playHead.bpm = 120.0;
        s.playHead.playing = true;
        s.hostWrites(S1Parameter::arpRate, 90.f);      // the plugin's own tempo says otherwise
        s.makeClicks();
        // Upstream's sequencer counts BEATS and steps every `arpSeqTempoMultiplier` of one, while
        // its readout names the value as a fraction of a bar: a sixteenth-note step is 0.25 and
        // reads "1/4 note", in the Mac app too ("Divisions: 1/4 note"). Kept, and pinned here.
        check(s.plain(S1Parameter::arpSeqTempoMultiplier) == 0.25f && s.parameter(S1Parameter::arpSeqTempoMultiplier).getCurrentValueAsText() == "1/4 note",
              "the step under test is a quarter of a beat — a sixteenth note — which upstream's readout calls \"1/4 note\"", s.plain(S1Parameter::arpSeqTempoMultiplier));
        s.holdChord();
        s.run(3.0);
        const Session::Steps steps = s.steps();
        check(steps.count >= 20, "at 120 BPM from the host the arpeggiator is heard step by step", steps.count);
        check(near(steps.mean, 125.0, 0.02), "a 1/16 step is 125 ms, measured from the rendered output", steps.mean);
        check(steps.worst < 1.0, "and no step departs from that by a millisecond", steps.worst);
        check(s.processor.engineValue(S1Parameter::arpRate) == 120.f, "the kernel's tempo is the host's", s.processor.engineValue(S1Parameter::arpRate));
        check(s.plain(S1Parameter::arpRate) == 120.f, "and the tempo parameter shows it, whatever was written to it", s.plain(S1Parameter::arpRate));
        check(s.processor.isUsingHostTempo(), "the processor says the tempo is the host's", 0);

        // The host changes tempo while it plays.
        s.playHead.bpm = 150.0;
        s.block();
        s.recorded.clear();
        s.run(3.0);
        check(near(s.steps(false).mean, 100.0, 0.02), "at 150 BPM a 1/16 step is 100 ms", s.steps(false).mean);
    }


    // MARK: the same at other buffer sizes — a tempo arrives with a block, a step on its sample
    for (const int size : { 64, 1024, 37 }) {
        Session s(true, size);
        s.playHead.bpm = 120.0;
        s.makeClicks();
        s.holdChord();
        s.run(2.0);
        check(near(s.steps().mean, 125.0, 0.02) && s.steps().worst < 1.0,
              "125 ms in blocks of " + std::to_string(size), s.steps().mean);
    }

    // MARK: no tempo from the host — the plugin's own applies
    {
        Session standalone(false);
        standalone.hostWrites(S1Parameter::arpRate, 90.f);
        standalone.makeClicks();
        standalone.holdChord();
        standalone.run(3.0);
        check(near(standalone.steps().mean, 60000.0 / 90.0 / 4.0, 0.02), "with no play head (a standalone) the tempo parameter's 90 BPM: 166.67 ms", standalone.steps().mean);
        check(!standalone.processor.isUsingHostTempo(), "and the processor says the tempo is its own", 0);

        Session noPosition;
        noPosition.playHead.hasPosition = false;
        noPosition.hostWrites(S1Parameter::arpRate, 90.f);
        noPosition.makeClicks();
        noPosition.holdChord();
        noPosition.run(2.0);
        check(near(noPosition.steps().mean, 60000.0 / 90.0 / 4.0, 0.02), "a play head with no position: the same", noPosition.steps().mean);

        Session noTempo;
        noTempo.playHead.playing = true;               // a transport, but no bpm
        noTempo.hostWrites(S1Parameter::arpRate, 90.f);
        noTempo.makeClicks();
        noTempo.holdChord();
        noTempo.run(2.0);
        check(near(noTempo.steps().mean, 60000.0 / 90.0 / 4.0, 0.02), "a position with no bpm: the same", noTempo.steps().mean);

        // A host whose tempo goes away (it happens when a plugin is moved between hosts' graphs):
        // the last tempo stays, and the parameter is obeyed again.
        Session leaving;
        leaving.playHead.bpm = 120.0;
        leaving.makeClicks();
        leaving.playHead.bpm = {};
        leaving.block();
        check(leaving.plain(S1Parameter::arpRate) == 120.f, "when the host's tempo goes away the last one stays", leaving.plain(S1Parameter::arpRate));
        leaving.hostWrites(S1Parameter::arpRate, 100.f);
        leaving.block();
        check(leaving.processor.engineValue(S1Parameter::arpRate) == 100.f, "and the tempo parameter is obeyed again", leaving.processor.engineValue(S1Parameter::arpRate));
    }

    // MARK: the tempo parameter under a host tempo — reported, not obeyed
    {
        Session s;
        s.playHead.bpm = 120.0;
        s.run(0.1);
        HostEars ears;
        s.parameter(S1Parameter::arpRate).addListener(&ears);
        s.run(0.2);
        check(ears.values == 0, "a steady host tempo reports nothing", ears.values);
        s.playHead.bpm = 133.0;
        s.run(0.2);
        check(ears.values == 1 && ears.gestures == 0, "a new host tempo is reported once, with no gesture", ears.values);
        check(s.plain(S1Parameter::arpRate) == 133.f, "as the tempo parameter's value", s.plain(S1Parameter::arpRate));
        s.parameter(S1Parameter::arpRate).removeListener(&ears);

        s.hostWrites(S1Parameter::arpRate, 70.f);
        s.block();
        check(s.processor.engineValue(S1Parameter::arpRate) == 133.f, "a value written to the tempo parameter does not reach the kernel", s.processor.engineValue(S1Parameter::arpRate));
        check(s.plain(S1Parameter::arpRate) == 133.f, "and the parameter is put back to the host's tempo within the block", s.plain(S1Parameter::arpRate));

        // Out of the parameter's range: clamped once, then quiet (ADR-025).
        const float maximum = s.parameter(S1Parameter::arpRate).getNormalisableRange().end;
        const float minimum = s.parameter(S1Parameter::arpRate).getNormalisableRange().start;
        s.playHead.bpm = 5000.0;
        s.block();
        s.parameter(S1Parameter::arpRate).addListener(&ears);
        ears.values = 0;
        s.run(0.2);
        check(s.plain(S1Parameter::arpRate) == maximum && ears.values == 0, "a tempo over the range settles at the maximum and reports nothing more", s.plain(S1Parameter::arpRate));
        s.playHead.bpm = 0.25;
        s.run(0.1);
        check(s.plain(S1Parameter::arpRate) == minimum, "one under it at the minimum", s.plain(S1Parameter::arpRate));
        s.playHead.bpm = std::nan("");
        s.run(0.1);
        check(s.plain(S1Parameter::arpRate) == minimum, "and a tempo that is not a number is no tempo", s.plain(S1Parameter::arpRate));
        s.parameter(S1Parameter::arpRate).removeListener(&ears);
    }

    // MARK: what is synced to the tempo follows it
    {
        Session s;
        s.playHead.bpm = 120.0;
        s.hostWrites(S1Parameter::tempoSyncToArpRate, 1.f);
        s.hostWrites(S1Parameter::delayTime, 0.5f);
        s.hostWrites(S1Parameter::lfo1Rate, 2.f);
        s.run(0.1);
        check(near(s.plain(S1Parameter::delayTime), 0.5, 1e-6) && s.parameter(S1Parameter::delayTime).getCurrentValueAsText() == "1/4 note",
              "synced at 120: a 0.5 s delay is a quarter note", s.plain(S1Parameter::delayTime));
        HostEars delay, lfo;
        s.parameter(S1Parameter::delayTime).addListener(&delay);
        s.parameter(S1Parameter::lfo1Rate).addListener(&lfo);
        s.playHead.bpm = 125.0;
        s.run(0.1);
        check(near(s.plain(S1Parameter::delayTime), 60.0 / 125.0, 1e-6), "the host goes to 125: the delay is 0.48 s", s.plain(S1Parameter::delayTime));
        check(s.parameter(S1Parameter::delayTime).getCurrentValueAsText() == "1/4 note", "still a quarter note", 0);
        check(near(s.plain(S1Parameter::lfo1Rate), 125.0 / 60.0, 1e-5), "and the 2 Hz LFO is 2.083 Hz, a quarter note too", s.plain(S1Parameter::lfo1Rate));
        check(delay.values == 1 && lfo.values == 1 && delay.gestures == 0 && lfo.gestures == 0, "each reported once, no gesture", delay.values + lfo.values);
        check(near(s.processor.engineValue(S1Parameter::delayTime), 60.0 / 125.0, 1e-6), "the kernel has it", s.processor.engineValue(S1Parameter::delayTime));

        // A jump far enough that upstream's re-quantising by TIME landed on a neighbour (125 -> 90:
        // the quarter note became a "1/4 triplet", 0.444 s). Since the X2 gate (ADR-082) the note
        // value is kept, however far the tempo goes.
        s.playHead.bpm = 90.0;
        s.run(0.1);
        check(near(s.plain(S1Parameter::delayTime), 60.0 / 90.0, 1e-6) && s.parameter(S1Parameter::delayTime).getCurrentValueAsText() == "1/4 note",
              "the host jumps 125 -> 90: the delay is still a quarter note, 0.667 s", s.plain(S1Parameter::delayTime));
        check(near(s.plain(S1Parameter::lfo1Rate), 90.0 / 60.0, 1e-5) && s.parameter(S1Parameter::lfo1Rate).getCurrentValueAsText() == "1/4 note",
              "and the LFO a quarter note, 1.5 Hz", s.plain(S1Parameter::lfo1Rate));
        s.playHead.bpm = 60.0;
        s.run(0.1);
        s.playHead.bpm = 180.0;
        s.run(0.1);
        s.playHead.bpm = 120.0;
        s.run(0.1);
        check(near(s.plain(S1Parameter::delayTime), 0.5, 1e-6) && near(s.plain(S1Parameter::lfo1Rate), 2.0, 1e-5), "through 60 and 180 and back to 120: a quarter note throughout, 0.5 s and 2 Hz again", s.plain(S1Parameter::delayTime));
        // A note value the new tempo cannot give within the parameter's range falls back to the nearest that it can.
        s.hostWrites(S1Parameter::delayTime, 1.0f);     // a half note at 120
        s.run(0.1);
        s.playHead.bpm = 40.0;                          // a half note at 40 BPM is 3 s: over the delay's maximum
        s.run(0.1);
        const float maximumDelay = s.parameter(S1Parameter::delayTime).getNormalisableRange().end;
        check(s.plain(S1Parameter::delayTime) <= maximumDelay && s.plain(S1Parameter::delayTime) > 0.f, "a note value that does not fit at the new tempo becomes the nearest that does", s.plain(S1Parameter::delayTime));
        std::printf("note  a half-note delay at 40 BPM (3 s, over the %.2f s maximum) reads \"%s\"\n", double(maximumDelay), s.parameter(S1Parameter::delayTime).getCurrentValueAsText().toRawUTF8());
        s.playHead.bpm = 120.0;
        s.run(0.1);
        s.parameter(S1Parameter::delayTime).removeListener(&delay);
        s.parameter(S1Parameter::lfo1Rate).removeListener(&lfo);
    }

    // MARK: the plugin's own tempo (a standalone) keeps note values too
    {
        Session s(false);
        s.hostWrites(S1Parameter::tempoSyncToArpRate, 1.f);
        s.hostWrites(S1Parameter::arpRate, 120.f);
        s.hostWrites(S1Parameter::delayTime, 0.5f);
        s.run(0.1);
        s.hostWrites(S1Parameter::arpRate, 90.f);
        s.run(0.1);
        check(near(s.plain(S1Parameter::delayTime), 60.0 / 90.0, 1e-6) && s.parameter(S1Parameter::delayTime).getCurrentValueAsText() == "1/4 note",
              "with no host, the Tempo control 120 -> 90: the quarter-note delay is a quarter note at 90", s.plain(S1Parameter::delayTime));
        // Sync off: nothing is synced, nothing moves.
        s.hostWrites(S1Parameter::tempoSyncToArpRate, 0.f);
        s.hostWrites(S1Parameter::delayTime, 0.3f);
        s.run(0.1);
        s.hostWrites(S1Parameter::arpRate, 140.f);
        s.run(0.1);
        check(near(s.plain(S1Parameter::delayTime), 0.3, 1e-6), "with tempo sync off a tempo change leaves the delay's 0.3 s alone", s.plain(S1Parameter::delayTime));
    }

    // MARK: a preset made at one tempo, loaded under a host at another
    {
        Session s;
        s.playHead.bpm = 140.0;
        s.run(0.1);
        s1::Preset preset = s.processor.presetLibrary().initialPreset();
        preset.tempoSyncToArpRate = 1;
        preset.arpRate = 100;
        preset.delayTime = 0.6;          // a quarter note at 100 BPM
        preset.lfoRate = 100.0 / 60.0 / 2.0;   // a half note at 100 BPM
        s.processor.loadPreset(preset, false);
        s.run(0.1);
        check(near(s.plain(S1Parameter::delayTime), 60.0 / 140.0, 1e-6) && s.parameter(S1Parameter::delayTime).getCurrentValueAsText() == "1/4 note",
              "a preset saved at 100 BPM with a quarter-note delay, loaded in a 140 BPM project: a quarter note at 140 (0.4286 s)", s.plain(S1Parameter::delayTime));
        check(near(s.processor.engineValue(S1Parameter::delayTime), 60.0 / 140.0, 1e-6) && s.processor.engineValue(S1Parameter::arpRate) == 140.f, "in the kernel too, at the host's tempo", s.processor.engineValue(S1Parameter::delayTime));
        check(s.parameter(S1Parameter::lfo1Rate).getCurrentValueAsText() == "1/2 note", "and its half-note LFO is a half note", s.plain(S1Parameter::lfo1Rate));
    }

    // MARK: a saved tempo does not override the host's
    {
        Session saved(false);
        saved.hostWrites(S1Parameter::arpRate, 90.f);
        saved.makeClicks();
        juce::MemoryBlock state;
        saved.processor.getStateInformation(state);

        Session s;
        s.playHead.bpm = 120.0;
        s.processor.setStateInformation(state.getData(), int(state.getSize()));
        s.processor.prepareToPlay(kSampleRate, 512);   // as a host does after restoring a session
        check(s.plain(S1Parameter::arpRate) == 90.f, "a session saved at 90 BPM is restored: the parameter reads 90 before any audio", s.plain(S1Parameter::arpRate));
        s.run(2.0);
        s.recorded.clear();
        s.holdChord();
        s.run(2.0);
        check(near(s.steps().mean, 125.0, 0.02), "but it plays at the host's 120: 125 ms", s.steps().mean);
        check(s.plain(S1Parameter::arpRate) == 120.f, "and the parameter says so", s.plain(S1Parameter::arpRate));

        // The very first block is already at the host's tempo: keys held from its first sample.
        Session first;
        first.playHead.bpm = 120.0;
        first.processor.setStateInformation(state.getData(), int(state.getSize()));
        first.processor.prepareToPlay(kSampleRate, 512);
        first.holdChord();
        check(first.processor.engineValue(S1Parameter::arpRate) == 120.f, "the first block after a restore is rendered at the host's tempo", first.processor.engineValue(S1Parameter::arpRate));
    }

    // MARK: the transport
    {
        // A held note, no arpeggiator, no note-off from the host: stopping releases it.
        Session s;
        s.playHead.bpm = 120.0;
        s.playHead.playing = true;
        s.hostWrites(S1Parameter::releaseDuration, 0.05f);
        s.hostWrites(S1Parameter::reverbOn, 0.f);
        s.hostWrites(S1Parameter::delayOn, 0.f);
        s.run(2.0);
        s.send(juce::MidiMessage::noteOn(1, 57, juce::uint8(110)));
        s.run(0.5);
        const double sounding = s.level(0.1);
        check(sounding > 0.01, "a key held while the transport runs sounds", sounding);
        s.playHead.playing = false;
        s.run(1.0);
        check(s.level(0.1) < sounding / 1000, "the transport stops: the note is released though the host sent no note-off", s.level(0.1));
        s.recorded.clear();
        s.playHead.playing = true;
        s.run(0.5);
        check(s.level(0.4) < sounding / 1000, "starting again plays nothing by itself", s.level(0.4));
        s.send(juce::MidiMessage::noteOn(1, 57, juce::uint8(110)));
        s.run(0.3);
        check(s.level(0.1) > 0.01, "and the same key, which the host never released, sounds when it is played again", s.level(0.1));
    }
    {
        // The arpeggiator: the stop rewinds it within the block the stop arrives in.
        Session s;
        s.playHead.bpm = 120.0;
        s.playHead.playing = true;
        s.makeClicks();
        s.holdChord();
        s.run(0.7);                                     // some steps in
        check(s.processor.arpBeatCounter() >= 4, "the arpeggiator has counted some steps", s.processor.arpBeatCounter());
        s.playHead.playing = false;
        s.block();
        check(s.processor.arpBeatCounter() == 0, "the block the stop arrives in puts the sequencer back to step 0", s.processor.arpBeatCounter());

        // The host's note-offs arrive with the stop, as they do; then nothing plays.
        s.releaseChord();
        s.recorded.clear();
        s.run(1.0);
        check(s.onsets().empty(), "with the keys released and the transport stopped nothing more is played", double(s.onsets().size()));

        // Start, and play again: from the first step, on the key's own sample.
        s.playHead.playing = true;
        s.run(0.3);
        s.recorded.clear();
        juce::MidiBuffer midi;
        for (const int note : { 48, 55, 64 }) { midi.addEvent(juce::MidiMessage::noteOn(1, note, juce::uint8(110)), 200); }
        s.block(midi);
        s.run(1.0);
        const std::vector<size_t> at = s.onsets();
        check(at.size() >= 6 && at.front() >= 200 && at.front() < 200 + 64, "started again, the arpeggiator begins on the sample the keys arrive on", at.empty() ? -1 : double(at.front()));
        const double first = at.size() >= 2 ? s.pitch(at[0], 0.03) : 0;
        check(near(first, 130.81, 2.0), "with step 0: the lowest key, C3", first);
        const double second = at.size() >= 3 ? s.pitch(at[1], 0.03) : 0;
        check(near(second, 196.0, 3.0), "then the next, G3", second);
    }
    {
        // Keys still down when the transport stops — a host that sends no note-offs, or a player's
        // hands — are released with it, as by CC123: nothing goes on playing, and the same keys
        // play when they arrive again though no note-off ever came.
        Session s;
        s.playHead.bpm = 120.0;
        s.playHead.playing = true;
        s.makeClicks();
        s.holdChord();
        s.run(0.7);
        s.playHead.playing = false;
        s.block();
        s.recorded.clear();
        s.run(1.0);
        check(s.onsets(false).empty(), "keys still down when the transport stops do not go on arpeggiating", double(s.onsets(false).size()));
        s.playHead.playing = true;
        s.block();
        s.recorded.clear();
        s.holdChord();
        s.run(1.0);
        const std::vector<size_t> at = s.onsets();
        check(at.size() >= 6 && at.front() < 64, "and the same keys, never released by the host, play when they arrive again", at.empty() ? -1 : double(at.front()));
        check(!at.empty() && near(s.pitch(at[0], 0.03), 130.81, 2.0), "from step 0", at.empty() ? 0 : s.pitch(at[0], 0.03));
    }
    {
        // The same without the arpeggiator: a sound with no sustain, its key held until it has
        // died away, then the stop. No voice may be left with its envelope's gate up. (With the
        // arpeggiator on — above — the P4-5 handler left it up, and the next phrase lost its first note.)
        Session s;
        s.playHead.bpm = 120.0;
        s.playHead.playing = true;
        s.makeClicks();
        s.hostWrites(S1Parameter::arpIsOn, 0.f);
        s.run(0.1);
        for (int round = 0; round < 8; ++round) {       // every voice of the six, and then some
            s.playHead.playing = true;
            s.send(juce::MidiMessage::noteOn(1, 50 + round, juce::uint8(110)));
            s.run(0.3);
            s.playHead.playing = false;
            s.block();
            s.send(juce::MidiMessage::noteOff(1, 50 + round));
        }
        s.playHead.playing = true;
        int heard = 0;
        for (int round = 0; round < 8; ++round) {
            s.recorded.clear();
            s.send(juce::MidiMessage::noteOn(1, 50 + round, juce::uint8(110)));
            s.run(0.2);
            if (!s.onsets().empty() && s.onsets().front() < 64) { ++heard; }
            s.send(juce::MidiMessage::noteOff(1, 50 + round));
            s.run(0.1);
        }
        check(heard == 8, "after stops that caught decayed voices, every one of eight new notes is heard", heard);
    }
    {
        // A host that never moves its transport (playing live with it stopped) is no stop.
        Session s;
        s.playHead.bpm = 120.0;
        s.playHead.playing = false;
        s.hostWrites(S1Parameter::reverbOn, 0.f);
        s.run(2.0);
        s.send(juce::MidiMessage::noteOn(1, 57, juce::uint8(110)));
        s.run(1.0);
        check(s.level(0.1) > 0.01, "a key played with the transport stopped all along sounds and stays", s.level(0.1));
    }

    std::printf(failures == 0 ? "\nall passed\n" : "\n%d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
