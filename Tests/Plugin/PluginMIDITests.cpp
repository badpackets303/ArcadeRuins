// X2-4 (ADR-075): MIDI as a host sends it — through processBlock, the engine's router, and out
// as sound and as parameter reports. The router's rules themselves are held to the standalone's
// by Tests/Engine/HostMIDITests (1,237 events); this is the plugin around it.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"

namespace {

constexpr double kSampleRate = 44100.0;
constexpr int kBlock = 512;

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

/// A plugin in a host: prepared, and rendered block by block with whatever MIDI the test adds.
struct Session {
    S1PluginProcessor processor;
    juce::AudioBuffer<float> buffer { 2, kBlock };
    std::vector<float> recorded;   // left channel, everything rendered since the last clear

    Session() {
        processor.setPlayConfigDetails(0, 2, kSampleRate, kBlock);
        processor.prepareToPlay(kSampleRate, kBlock);
        processor.hostMIDITrace().enabled.store(true);
        run(2.0);                  // every parameter's glide from 0 has arrived (ADR-013)
        takeNotes();
    }
    void block(const juce::MidiBuffer &midi) {
        juce::MidiBuffer copy = midi;
        processor.processBlock(buffer, copy);
        recorded.insert(recorded.end(), buffer.getReadPointer(0), buffer.getReadPointer(0) + kBlock);
    }
    void run(double seconds) {
        const juce::MidiBuffer none;
        for (int i = 0; i < int(seconds * kSampleRate / kBlock) + 1; ++i) { block(none); }
    }
    void send(const juce::MidiMessage &message, int sample = 0) {
        juce::MidiBuffer midi;
        midi.addEvent(message, sample);
        block(midi);
    }
    /// "+note:velocity" and "-note", as the router played them, since the last call.
    std::string takeNotes() {
        uint32_t entries[S1HostMIDITrace::capacity];
        const int count = processor.hostMIDITrace().take(entries, int(S1HostMIDITrace::capacity));
        std::string notes;
        for (int i = 0; i < count; ++i) {
            const uint32_t op = entries[i] >> 24, note = (entries[i] >> 16) & 0xFF, value = entries[i] & 0xFFFF;
            if (op == S1HostMIDITrace::hostNoteOn) { notes += (notes.empty() ? "+" : " +") + std::to_string(note) + ":" + std::to_string(value); }
            if (op == S1HostMIDITrace::hostNoteOff) { notes += (notes.empty() ? "-" : " -") + std::to_string(note); }
        }
        return notes;
    }
    double level(double lastSeconds) const {
        const size_t count = std::min(recorded.size(), size_t(lastSeconds * kSampleRate));
        double squares = 0;
        for (size_t i = recorded.size() - count; i < recorded.size(); ++i) { squares += double(recorded[i]) * double(recorded[i]); }
        return std::sqrt(squares / double(std::max<size_t>(count, 1)));
    }
    /// The fundamental of the last `lastSeconds`, by autocorrelation between 90 and 960 Hz.
    double pitch(double lastSeconds) const {
        const size_t count = size_t(lastSeconds * kSampleRate), from = recorded.size() - count;
        const size_t shortest = size_t(kSampleRate / 960.0), longest = size_t(kSampleRate / 90.0);
        std::vector<double> score(longest + 2, 0.0);
        double best = -1e30; size_t bestLag = shortest + 1;
        for (size_t lag = shortest; lag <= longest + 1; ++lag) {
            double sum = 0;
            for (size_t i = from; i + lag < recorded.size(); ++i) { sum += double(recorded[i]) * double(recorded[i + lag]); }
            score[lag] = sum / double(count - lag);
        }
        // The first lag that is a local maximum near the global one: a multiple of the period scores as well.
        for (size_t lag = shortest + 1; lag <= longest; ++lag) { best = std::max(best, score[lag]); }
        for (size_t lag = shortest + 1; lag <= longest; ++lag) {
            if (score[lag] > 0.9 * best && score[lag] >= score[lag - 1] && score[lag] >= score[lag + 1]) { bestLag = lag; break; }
        }
        const double a = score[bestLag - 1], b = score[bestLag], c = score[bestLag + 1];
        return kSampleRate / (double(bestLag) + (a - c) / (2 * (a - 2 * b + c)));
    }
    S1HostParameter &parameter(S1Parameter p) { return processor.hostParameter(p); }
    void hostWrites(S1Parameter p, float plain) { parameter(p).setValueNotifyingHost(parameter(p).convertTo0to1(plain)); }
};

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);

    // MARK: one key plays once (ADR-031's reason for being)
    {
        Session s;
        s.send(juce::MidiMessage::noteOn(1, 60, juce::uint8(100)), 17);
        s.run(0.2);
        check(s.takeNotes() == "+60:100", "one key from the host is played once, at the velocity it was sent with", 0);
        check(s.level(0.1) > 0.01, "and it sounds", s.level(0.1));
        s.send(juce::MidiMessage(0x90, 60, 0));
        check(s.takeNotes() == "-60", "a note-on with velocity 0 releases it (the router's rule now, not the processor's)", 0);
        s.send(juce::MidiMessage::noteOn(6, 64, juce::uint8(90)));
        check(s.takeNotes() == "+64:90", "omni: a key on channel 6 plays", 0);
    }

    // MARK: the sustain pedal
    {
        Session s;
        s.send(juce::MidiMessage::noteOn(1, 60, juce::uint8(100)));
        s.send(juce::MidiMessage::controllerEvent(1, 64, 127));
        s.send(juce::MidiMessage::noteOff(1, 60));
        s.run(1.0);
        check(s.takeNotes() == "+60:100", "with the pedal down a released key is not stopped", 0);
        check(s.level(0.2) > 0.01, "and still sounds a second later", s.level(0.2));
        s.send(juce::MidiMessage::controllerEvent(1, 64, 0));
        check(s.takeNotes() == "-60", "lifting the pedal stops it", 0);
        s.run(3.0);
        check(s.level(0.2) < 1e-4, "and it dies away", s.level(0.2));
    }

    // MARK: mono, switched by a host parameter, with the router's return to the highest held key
    {
        Session s;
        s.hostWrites(S1Parameter::isMono, 1.f);
        s.run(0.05);
        s.send(juce::MidiMessage::noteOn(1, 60, juce::uint8(100)));
        s.send(juce::MidiMessage::noteOn(1, 67, juce::uint8(100)));
        s.send(juce::MidiMessage::noteOn(1, 64, juce::uint8(100)));
        s.takeNotes();
        s.send(juce::MidiMessage::noteOff(1, 64, juce::uint8(40)));
        check(s.takeNotes() == "-64 +67:40", "mono: releasing the sounding key returns to the highest key still held", 0);
    }

    // MARK: pitch bend — heard, and reported to the host
    {
        Session s;
        HostEars ears;
        s.parameter(S1Parameter::pitchbend).addListener(&ears);
        // The shipped Init bends an octave (since X2-9, ADR-080; the preset model's bare defaults,
        // which the plugin started with before, have a range of 0 — as 230 of the 695 factory
        // presets do, where the wheel does nothing by the preset's choice). Set here all the same:
        check(s.processor.engineValue(S1Parameter::pitchbendMaxSemitones) == 12.f, "(the shipped Init's own bend range is an octave)", s.processor.engineValue(S1Parameter::pitchbendMaxSemitones));
        s.hostWrites(S1Parameter::pitchbendMaxSemitones, 12.f);
        const double semitonesUp = 12.0;
        s.send(juce::MidiMessage::noteOn(1, 57, juce::uint8(100)));
        s.run(0.6);
        const double centred = s.pitch(0.3);
        check(std::fabs(centred - 220.0) < 2.2, "A3 with the wheel centred is 220 Hz", centred);

        s.send(juce::MidiMessage::pitchWheel(1, 16383));
        s.run(1.0);
        const double bent = s.pitch(0.3);
        const double semitones = 12.0 * std::log2(bent / centred);
        check(std::fabs(semitones - semitonesUp) < 0.1, "the wheel at the top bends it up by the preset's range (" + std::to_string(int(semitonesUp)) + " semitones)", semitones);
        check(s.parameter(S1Parameter::pitchbend).plainValue() == 16383.f, "the host's pitchbend parameter follows the wheel", s.parameter(S1Parameter::pitchbend).plainValue());
        check(ears.values == 1 && ears.gestures == 0, "told once, as a report with no gesture", ears.values);

        s.send(juce::MidiMessage::pitchWheel(1, 8192));
        s.run(1.0);
        check(std::fabs(s.pitch(0.3) - centred) < 0.5, "and back to the centre", s.pitch(0.3));
        s.parameter(S1Parameter::pitchbend).removeListener(&ears);
    }

    // MARK: the mod wheel — the Mac wheel's arithmetic, on the render thread
    {
        Session s;
        HostEars ears;
        s.parameter(S1Parameter::cutoff).addListener(&ears);
        s.send(juce::MidiMessage::controllerEvent(1, 1, 127));
        check(std::fabs(s.processor.engineValue(S1Parameter::cutoff) - 360.f) < 0.01f, "the wheel at the top sets the cutoff to 360 Hz, as the Mac's wheel does", s.processor.engineValue(S1Parameter::cutoff));
        check(s.parameter(S1Parameter::cutoff).plainValue() == s.processor.engineValue(S1Parameter::cutoff) && ears.values == 1 && ears.gestures == 0,
              "the host's cutoff parameter follows, told once with no gesture", s.parameter(S1Parameter::cutoff).plainValue());
        s.send(juce::MidiMessage::controllerEvent(1, 1, 0));
        check(s.processor.engineValue(S1Parameter::cutoff) == s.parameter(S1Parameter::cutoff).getNormalisableRange().end, "the wheel at the bottom opens the filter to the top of its range (3 x 7,600 Hz, clamped)", s.processor.engineValue(S1Parameter::cutoff));
        s.run(0.1);
        const float settled = s.processor.engineValue(S1Parameter::cutoff);
        s.hostWrites(S1Parameter::cutoff, 1000.f);
        s.run(0.05);
        check(s.processor.engineValue(S1Parameter::cutoff) == s.parameter(S1Parameter::cutoff).plainValue() && settled != s.processor.engineValue(S1Parameter::cutoff),
              "and the host can still write the cutoff afterwards", s.processor.engineValue(S1Parameter::cutoff));

        s.processor.setModWheelRouting(s1plugin::ModWheelRouting::lfo1Rate);
        s.hostWrites(S1Parameter::tempoSyncToArpRate, 0.f);
        s.run(0.05);
        const float cutoffBefore = s.processor.engineValue(S1Parameter::cutoff), rateBefore = s.processor.engineValue(S1Parameter::lfo1Rate);
        s.send(juce::MidiMessage::controllerEvent(1, 1, 100));
        check(s.processor.engineValue(S1Parameter::cutoff) == cutoffBefore && s.processor.engineValue(S1Parameter::lfo1Rate) != rateBefore
                  && s.parameter(S1Parameter::lfo1Rate).plainValue() == s.processor.engineValue(S1Parameter::lfo1Rate),
              "routed to LFO 1's rate, the wheel moves that and leaves the cutoff alone", s.processor.engineValue(S1Parameter::lfo1Rate));
        s.parameter(S1Parameter::cutoff).removeListener(&ears);
    }

    // MARK: all notes off
    {
        Session s;
        s.send(juce::MidiMessage::noteOn(1, 60, juce::uint8(100)));
        s.send(juce::MidiMessage::noteOn(1, 64, juce::uint8(100)));
        s.takeNotes();
        s.send(juce::MidiMessage::allNotesOff(1));
        check(s.takeNotes() == "-60 -64", "CC 123 releases what the host was holding", 0);
    }

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
