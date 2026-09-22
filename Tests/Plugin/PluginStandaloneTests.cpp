// X2-10 (ADR-081): the plugin as the standalone runs it — through juce::AudioProcessorPlayer,
// the class JUCE's standalone holder plays a processor with — across what an audio device does
// to it: starts, stops, comes back at another sample rate and buffer size (headphones plugged
// in, the rate changed in Audio MIDI Setup: ADR-043's failure in the Catalyst standalone), and
// hands over fewer frames than it promised. With MIDI arriving as a device delivers it, through
// the player's collector. (The app itself — window, settings, MIDI inputs opening by themselves —
// is checked by hand: docs in ADR-081.)
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include <juce_audio_utils/juce_audio_utils.h>

#include "S1PluginProcessor.h"

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

/// An audio device as far as the player looks at one: a rate, a buffer size, two outputs.
struct Device final : juce::AudioIODevice {
    double rate; int buffer;
    Device(double sampleRate, int bufferSize) : juce::AudioIODevice("Test device", "Test"), rate(sampleRate), buffer(bufferSize) {}
    juce::StringArray getOutputChannelNames() override { return { "L", "R" }; }
    juce::StringArray getInputChannelNames() override { return {}; }
    juce::Array<double> getAvailableSampleRates() override { return { rate }; }
    juce::Array<int> getAvailableBufferSizes() override { return { buffer }; }
    int getDefaultBufferSize() override { return buffer; }
    juce::String open(const juce::BigInteger &, const juce::BigInteger &, double, int) override { return {}; }
    void close() override {}
    bool isOpen() override { return true; }
    void start(juce::AudioIODeviceCallback *) override {}
    void stop() override {}
    bool isPlaying() override { return true; }
    juce::String getLastError() override { return {}; }
    int getCurrentBufferSizeSamples() override { return buffer; }
    double getCurrentSampleRate() override { return rate; }
    int getCurrentBitDepth() override { return 32; }
    juce::BigInteger getActiveOutputChannels() const override { juce::BigInteger b; b.setRange(0, 2, true); return b; }
    juce::BigInteger getActiveInputChannels() const override { return {}; }
    int getOutputLatencyInSamples() override { return 0; }
    int getInputLatencyInSamples() override { return 0; }
};

struct Rig {
    S1PluginProcessor processor;
    juce::AudioProcessorPlayer player;
    std::vector<float> recorded;     // left channel since the last clear
    double rate = 0;

    Rig() { player.setProcessor(&processor); }
    ~Rig() { player.setProcessor(nullptr); }

    void deviceStarts(Device &device) { rate = device.rate; player.audioDeviceAboutToStart(&device); }
    void deviceStops() { player.audioDeviceStopped(); }

    void callback(int frames) {
        std::vector<float> left(static_cast<size_t>(frames)), right(static_cast<size_t>(frames));
        float *outputs[2] = { left.data(), right.data() };
        player.audioDeviceIOCallbackWithContext(nullptr, 0, outputs, 2, frames, {});
        recorded.insert(recorded.end(), left.begin(), left.end());
    }
    void run(double seconds, int frames) { for (int done = 0; done < int(seconds * rate); done += frames) { callback(frames); } }
    void midi(const juce::MidiMessage &message) {
        juce::MidiMessage stamped = message;
        stamped.setTimeStamp(juce::Time::getMillisecondCounterHiRes() * 0.001);
        player.getMidiMessageCollector().addMessageToQueue(stamped);
    }
    double level(double lastSeconds) const {
        const size_t count = std::min(recorded.size(), size_t(lastSeconds * rate));
        double squares = 0;
        for (size_t i = recorded.size() - count; i < recorded.size(); ++i) { squares += double(recorded[i]) * double(recorded[i]); }
        return std::sqrt(squares / double(std::max<size_t>(count, 1)));
    }
    /// The fundamental of the last `lastSeconds`, by autocorrelation between 90 and 960 Hz.
    double pitch(double lastSeconds) const {
        const size_t count = size_t(lastSeconds * rate), from = recorded.size() - count;
        const size_t shortest = size_t(rate / 960.0), longest = size_t(rate / 90.0);
        std::vector<double> score(longest + 2, 0.0);
        for (size_t lag = shortest; lag <= longest + 1; ++lag) {
            double sum = 0;
            for (size_t i = from; i + lag < recorded.size(); ++i) { sum += double(recorded[i]) * double(recorded[i + lag]); }
            score[lag] = sum / double(count - lag);
        }
        double best = -1e30; size_t bestLag = shortest + 1;
        for (size_t lag = shortest + 1; lag <= longest; ++lag) { best = std::max(best, score[lag]); }
        for (size_t lag = shortest + 1; lag <= longest; ++lag) {
            if (score[lag] > 0.9 * best && score[lag] >= score[lag - 1] && score[lag] >= score[lag + 1]) { bestLag = lag; break; }
        }
        const double a = score[bestLag - 1], b = score[bestLag], c = score[bestLag + 1];
        return rate / (double(bestLag) + (a - c) / (2 * (a - 2 * b + c)));
    }
};

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    Device builtIn(48000.0, 512), headphones(96000.0, 256), interface441(44100.0, 1024);

    Rig rig;
    S1HostParameter &cutoff = rig.processor.hostParameter(S1Parameter::cutoff);
    cutoff.setValueNotifyingHost(cutoff.convertTo0to1(5000.f));      // something a device change must not lose
    rig.processor.hostParameter(S1Parameter::reverbOn).setValueNotifyingHost(0.f);

    // MARK: the device starts, a key is played from a MIDI device
    rig.deviceStarts(builtIn);
    rig.run(2.0, 512);                                                // the glides from 0 (ADR-013)
    check(rig.level(0.2) < 1e-4, "started on a 48 kHz device: running, and silent with nothing played", rig.level(0.2));
    rig.midi(juce::MidiMessage::noteOn(1, 57, juce::uint8(110)));
    rig.run(0.6, 512);
    check(rig.level(0.2) > 0.01, "a key from a MIDI device, through the player's collector, sounds", rig.level(0.2));
    check(std::fabs(rig.pitch(0.3) - 220.0) < 2.2, "A3 at 220 Hz", rig.pitch(0.3));
    check(!rig.processor.isUsingHostTempo(), "no play head in a standalone: the tempo is the plugin's own (ADR-077)", 0);

    // MARK: the device goes away and comes back as another one — the key still held down
    rig.deviceStops();
    rig.recorded.clear();
    rig.deviceStarts(headphones);
    rig.run(1.0, 256);
    check(std::fabs(cutoff.plainValue() - 5000.f) < 0.5f && std::fabs(rig.processor.engineValue(S1Parameter::cutoff) - 5000.f) < 0.5f,
          "restarted at 96 kHz with 256-frame buffers: the sound's settings are kept, in the host's list and in the kernel", rig.processor.engineValue(S1Parameter::cutoff));
    check(rig.level(0.2) < 1e-4, "the note that was sounding is gone with the engine that played it — silence, not a drone or a crash", rig.level(0.2));
    // The key was never released (the player's hands did not move). Played again, it must sound:
    // a router that still believed it down would swallow it (ADR-077's fault, from another door).
    rig.midi(juce::MidiMessage::noteOn(1, 57, juce::uint8(110)));
    rig.run(0.6, 256);
    check(rig.level(0.2) > 0.01, "the same key, played again without ever having been released, sounds", rig.level(0.2));
    check(std::fabs(rig.pitch(0.3) - 220.0) < 2.2, "at 220 Hz at the new rate", rig.pitch(0.3));
    rig.midi(juce::MidiMessage::noteOff(1, 57));
    rig.run(1.5, 256);
    check(rig.level(0.2) < 1e-4, "and stops when released", rig.level(0.2));

    // MARK: a third device; fewer frames than promised; more
    rig.deviceStops();
    rig.recorded.clear();
    rig.deviceStarts(interface441);
    rig.run(1.0, 1024);
    rig.midi(juce::MidiMessage::noteOn(1, 69, juce::uint8(110)));
    for (int i = 0; i < 120; ++i) { rig.callback(i % 3 == 0 ? 1024 : (i % 3 == 1 ? 37 : 480)); }
    check(std::fabs(rig.pitch(0.3) - 440.0) < 4.4, "on a 44.1 kHz device, in callbacks of 1,024, 37 and 480 frames: A4 at 440 Hz", rig.pitch(0.3));
    bool finite = true;
    for (const float x : rig.recorded) { finite = finite && std::isfinite(x) && std::fabs(x) < 4.f; }
    check(finite, "every sample through three devices finite and in range", 0);
    rig.midi(juce::MidiMessage::noteOff(1, 69));
    rig.run(0.5, 1024);
    rig.deviceStops();

    // MARK: many restarts leak nothing and keep working (a flaky USB interface)
    for (int i = 0; i < 25; ++i) { rig.deviceStarts(i % 2 ? builtIn : headphones); rig.callback(64); rig.deviceStops(); }
    rig.recorded.clear();
    rig.deviceStarts(builtIn);
    rig.run(1.0, 512);
    rig.midi(juce::MidiMessage::noteOn(1, 57, juce::uint8(110)));
    rig.run(0.6, 512);
    check(rig.level(0.2) > 0.01 && std::fabs(rig.pitch(0.3) - 220.0) < 2.2, "after 25 more device restarts it still plays, in tune", rig.pitch(0.3));
    rig.deviceStops();

    std::printf(failures == 0 ? "\nall passed\n" : "\n%d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
