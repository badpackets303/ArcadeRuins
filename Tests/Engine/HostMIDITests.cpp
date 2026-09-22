// X2-4 (ADR-075): S1HostMIDI against what the STANDALONE plays, on every OS.
//
// HostMIDIParityTests (Swift, Mac) drives the same MIDI through the standalone's main-thread chain
// and through this router, and requires the same note calls. It also writes down what the
// standalone played — Tests/Engine/Fixtures/host-midi.txt, guarded by a check-mode test. This
// replays that file's MIDI through the router alone, hosted the way the JUCE plugin hosts it
// (settings in the atomics, beginRenderCycle, MIDI as S1Events), and requires the file's notes.
//
//   argv[1]  Tests/Engine/Fixtures/host-midi.txt
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include "S1DSPKernel.hpp"

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr S1FrameCount kFrames = 64;

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

// The kernel cannot render without its tables; what is in them does not matter here.
void loadSineWavetables(S1DSPKernel &kernel) {
    const uint32_t size = 4096;
    for (uint32_t table = 0; table < S1_NUM_WAVEFORMS * S1_NUM_BANDLIMITED_FTABLES; ++table) {
        kernel.setupWaveform(table, size);
        for (uint32_t i = 0; i < size; ++i) { kernel.setWaveformValue(table, i, float(std::sin(2.0 * kPi * double(i) / size))); }
    }
    for (uint32_t band = 0; band < S1_NUM_BANDLIMITED_FTABLES; ++band) { kernel.setBandlimitFrequency(band, 20.f * std::pow(2.f, float(band))); }
}

/// A kernel hosted as the JUCE plugin hosts one, with the router on and its trace readable.
struct Host {
    std::unique_ptr<S1DSPKernel> kernel = std::make_unique<S1DSPKernel>(2, 44100.0);
    std::vector<float> left = std::vector<float>(kFrames), right = std::vector<float>(kFrames);

    Host() {
        loadSineWavetables(*kernel);
        kernel->prepareToRender(2, 44100.0);
        kernel->hostMIDI.enabled.store(true);
        kernel->hostMIDI.trace.enabled.store(true);
    }
    void render(const S1Event *events = nullptr, int count = 0) {
        kernel->hostMIDI.beginRenderCycle(*kernel);
        kernel->setOutput(left.data(), right.data());
        kernel->processWithEvents(kFrames, events, count);
    }
    void send(uint8_t status, uint8_t data1, uint8_t data2) {
        S1Event event {};
        event.kind = S1EventKind_MIDI;
        event.sampleOffset = 0;
        event.midi.length = 3;
        event.midi.data[0] = status; event.midi.data[1] = data1; event.midi.data[2] = data2;
        render(&event, 1);
    }
    /// The router's note calls since the last take, in HostMIDINote.normalised's form: a run of
    /// stops sorted (KeyboardView.allNotesOff releases in Set order on the Swift side).
    std::string takeNotes() {
        uint32_t entries[S1HostMIDITrace::capacity];
        const int count = kernel->hostMIDI.trace.take(entries, int(S1HostMIDITrace::capacity));
        std::vector<std::string> words;
        std::vector<int> stops;
        auto flush = [&] {
            std::sort(stops.begin(), stops.end());
            for (int note : stops) { words.push_back("-" + std::to_string(note)); }
            stops.clear();
        };
        for (int i = 0; i < count; ++i) {
            const uint32_t op = entries[i] >> 24, note = (entries[i] >> 16) & 0xFF, value = entries[i] & 0xFFFF;
            if (op == S1HostMIDITrace::hostNoteOff) { stops.push_back(int(note)); }
            else if (op == S1HostMIDITrace::hostNoteOn) { flush(); words.push_back("+" + std::to_string(note) + ":" + std::to_string(value)); }
        }
        flush();
        std::string joined;
        for (const std::string &word : words) { joined += (joined.empty() ? "" : " ") + word; }
        return joined;
    }
};

std::string trimmed(const std::string &text) {
    const auto first = text.find_first_not_of(" \t\r");
    if (first == std::string::npos) { return {}; }
    return text.substr(first, text.find_last_not_of(" \t\r") - first + 1);
}
} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc != 2) { std::printf("usage: HostMIDITests <host-midi.txt>\n"); return 2; }
    std::ifstream in(argv[1], std::ios::binary);
    if (!in) { std::printf("FAIL  cannot read %s\n", argv[1]); return 1; }

    std::unique_ptr<Host> host;
    std::string scenario, line;
    bool hold = false, mono = false;
    int scenarios = 0, events = 0, wrong = 0, wrongInScenario = 0, whiteKeysWrong = -1;
    auto closeScenario = [&] {
        if (!scenario.empty() && wrongInScenario > 0) { std::printf("FAIL  scenario \"%s\": %d events played other notes\n", scenario.c_str(), wrongInScenario); }
        wrongInScenario = 0;
    };
    while (std::getline(in, line)) {
        line = trimmed(line);
        if (line.empty() || line[0] == '#') { continue; }
        std::istringstream words(line);
        std::string word;
        words >> word;
        if (word == "scenario") {
            closeScenario();
            scenario = trimmed(line.substr(8));
            ++scenarios;
        } else if (word == "settings") {
            int octave = 0, channel = -1, white = 0, holdSetting = 0, monoSetting = 0;
            words >> octave >> channel >> white >> holdSetting >> monoSetting;
            // HostMIDIParityTests.begin: a new audio unit, mono set, the settings stored, one render.
            host = std::make_unique<Host>();
            hold = holdSetting != 0; mono = monoSetting != 0;
            host->kernel->setSynthParameter(isMono, mono ? 1.f : 0.f);
            host->kernel->hostMIDI.octaveShift.store(octave * 12);
            host->kernel->hostMIDI.midiChannel.store(channel < 0 ? 0 : channel);
            host->kernel->hostMIDI.omniMode.store(channel < 0);
            host->kernel->hostMIDI.whiteKeysOnly.store(white != 0);
            host->kernel->hostMIDI.holdMode.store(hold);
            host->render();
            host->takeNotes();
        } else if (word == "whitekeys") {
            Host keys;
            keys.kernel->hostMIDI.whiteKeysOnly.store(true);
            whiteKeysWrong = 0;
            for (int note = 0; note < 128; ++note) {
                int expected = -1;
                words >> expected;
                keys.send(0x90, uint8_t(note), 100);
                keys.send(0x80, uint8_t(note), 0);
                const std::string played = keys.takeNotes();
                if (played.rfind("+" + std::to_string(expected) + ":100", 0) != 0) { ++whiteKeysWrong; }
            }
        } else if (host) {
            const size_t arrow = line.find("=>");
            const std::string expected = arrow == std::string::npos ? "" : trimmed(line.substr(arrow + 2));
            int a = 0, b = 0, c = 0;
            if (word == "on") { words >> a >> b >> c; host->send(uint8_t(0x90 | c), uint8_t(a), uint8_t(b)); }
            else if (word == "off") { words >> a >> b >> c; host->send(uint8_t(0x80 | c), uint8_t(a), uint8_t(b)); }
            else if (word == "pedal") { words >> a >> b; host->send(uint8_t(0xB0 | b), 64, uint8_t(a)); }
            else if (word == "octave") { words >> a; host->kernel->hostMIDI.octaveShift.store(a * 12); }
            else if (word == "hold") { hold = !hold; host->kernel->hostMIDI.holdMode.store(hold); host->render(); }
            else if (word == "mono") { mono = !mono; host->kernel->setSynthParameter(isMono, mono ? 1.f : 0.f); host->render(); }
            else { std::printf("FAIL  unknown fixture line: %s\n", line.c_str()); ++failures; continue; }
            ++events;
            const std::string played = host->takeNotes();
            if (played != expected) {
                ++wrong; ++wrongInScenario;
                if (wrong <= 10) { std::printf("      \"%s\", %s: the standalone played [%s], the router [%s]\n", scenario.c_str(), line.substr(0, arrow).c_str(), expected.c_str(), played.c_str()); }
            }
        }
    }
    closeScenario();
    check(scenarios == 15 && events > 1200, "the fixture holds the 7 scripted and 8 random scenarios", events);
    check(wrong == 0, "for every one of its " + std::to_string(events) + " events the router plays the notes the standalone played", wrong);
    check(whiteKeysWrong == 0, "white-keys-only maps all 128 keys as the standalone's table does", whiteKeysWrong);

    // What the fixture cannot say, because the standalone has no such route (HostMIDIRouterTests' cases).
    {
        Host bend;
        bend.send(0xE0, 0x00, 0x60);   // 14-bit 0x3000 = 12288
        check(std::fabs(bend.kernel->getSynthParameter(pitchbend) - 12288.f) < 0.5f, "a pitch wheel message sets the pitchbend parameter to its 14-bit value", bend.kernel->getSynthParameter(pitchbend));
        bend.send(0xE0, 0x00, 0x40);
        check(std::fabs(bend.kernel->getSynthParameter(pitchbend) - 8192.f) < 0.5f, "and back to the centre", bend.kernel->getSynthParameter(pitchbend));

        Host panic;
        panic.send(0x90, 60, 100); panic.send(0x90, 64, 100); panic.takeNotes();
        panic.send(0xB0, 123, 0);
        check(panic.takeNotes() == "-60 -64", "CC 123 releases every key host MIDI holds", 0);
        panic.send(0x90, 60, 100);
        check(panic.takeNotes() == "+60:100", "and the keys are forgotten: the same key plays again", 0);

        Host shifted;
        shifted.kernel->hostMIDI.octaveShift.store(-120);
        shifted.send(0x90, 60, 100);
        check(shifted.takeNotes().empty(), "a note shifted out of the MIDI range is dropped, not clamped", 0);

        Host off;
        off.kernel->hostMIDI.enabled.store(false);
        off.send(0x90, 60, 100);
        check(off.takeNotes().empty() && off.kernel->getSynthParameter(pitchbend) == 8192.f, "with the router off, upstream's handler plays and the router records nothing", 0);
    }

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
