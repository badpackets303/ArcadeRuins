//
//  S1PluginProcessor.cpp
//  Arcade Ruins
//
//  X2-1 (ADR-072). See the header for the hosting order and where it comes from.
//

#include "S1PluginProcessor.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <string>

#include "S1BinaryData.h"
#include "S1PresetData.h"
#include "UI/S1PluginEditor.h"
#include "S1Preset.hpp"
#include "S1Rate.hpp"

// MARK: - The oscillator tables, from the data linked into the binary

S1SharedWavetables::S1SharedWavetables() {
    // juce_add_binary_data names a resource after its file, every character that cannot be in
    // an identifier replaced by '_': sawtooth_0002.json is sawtooth_0002_json.
    tables = s1::Wavetables::load([](const std::string &name) -> std::optional<std::string> {
        int size = 0;
        const char *data = S1BinaryData::getNamedResource((name + "_json").c_str(), size);
        if (data == nullptr) { return std::nullopt; }
        return std::string(data, size_t(size));
    });
    // load() throws when a table is missing or short. It is not caught: the data is part of
    // this binary, so a throw here is a broken build, which PluginRenderTests fails on in CI —
    // and a kernel without its tables crashes on its first frame, which is worse than not loading.
}

// MARK: - The preset library, from the data linked into the binary (ADR-080)

namespace {

std::optional<std::string> factoryBankText(const std::string &bankName) {
    // juce_add_binary_data mangles "Sound of Izrael 2.json" into an identifier; the list of
    // original file names is the dependable way back.
    for (int i = 0; i < S1PresetData::namedResourceListSize; ++i) {
        if (bankName + ".json" != S1PresetData::originalFilenames[i]) { continue; }
        int size = 0;
        const char *data = S1PresetData::getNamedResource(S1PresetData::namedResourceList[i], size);
        if (data != nullptr) { return std::string(data, size_t(size)); }
    }
    return std::nullopt;
}

s1::PresetDefaults kernelDefaults() {
    // The DSP's default for a parameter a preset's JSON omits, read once from a kernel.
    auto values = std::make_shared<std::array<double, S1Parameter::S1ParameterCount>>();
    S1DSPKernel kernel(2, 44100.0);
    for (int i = 0; i < S1Parameter::S1ParameterCount; ++i) { (*values)[size_t(i)] = double(kernel.defaultValue(S1Parameter(i))); }
    return [values](S1Parameter p) { return (*values)[size_t(p)]; };
}

} // namespace

juce::File S1SharedPresets::defaultUserDirectory() {
    // userApplicationDataDirectory: ~/Library on macOS (JUCE leaves "Application Support" to the
    // caller), %APPDATA% on Windows, ~/.config on Linux. Not the Catalyst products' App Group
    // container: the two libraries sit side by side and neither writes in the other's (ADR-080).
    juce::File base = juce::File::getSpecialLocation(juce::File::userApplicationDataDirectory);
   #if JUCE_MAC
    base = base.getChildFile("Application Support");
   #endif
    return base.getChildFile("BadPackets").getChildFile("Arcade Ruins").getChildFile("Banks");
}

S1SharedPresets::S1SharedPresets() : library(factoryBankText, kernelDefaults()) {
    library.setUserDirectory(defaultUserDirectory().getFullPathName().toStdString());
}

// MARK: - Lifecycle

S1PluginProcessor::S1PluginProcessor()
    : juce::AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    kernel = std::make_unique<S1DSPKernel>(2, 44100.0);             // S1AudioUnit.init
    // ADR-074: what a host renders must not depend on its buffer size — an offline bounce and the
    // live session it came from are the same performance. Upstream's path frees released voices
    // once per process() call, and an arpeggio then renders differently at every buffer size.
    kernel->freeReleasedVoicesEveryFrame = true;
    // ADR-075: host MIDI through the engine's router, as in the Catalyst AUv3 (ADR-031). Its
    // settings keep the standalone's out-of-the-box values (omni, no octave shift, no hold)
    // until there is an interface to change them; what it forwards arrives at this listener.
    kernel->hostMIDI.enabled.store(true, std::memory_order_relaxed);
    kernel->listener = this;
    wavetables->tables.apply(*kernel);                              // AKSynthOne.init: the tables…
    float parameters[S1Parameter::S1ParameterCount];                // …then every value read and written back
    for (int i = 0; i < S1Parameter::S1ParameterCount; ++i) {
        parameters[i] = kernel->parameters[size_t(i)];
    }
    kernel->setParameters(parameters);

    // The parameters start as Init: applied to the kernel the way every preset is, then read
    // back, so the host's list and the kernel agree from the first block.
    // Init is the SHIPPED Init — factory bank "User" — not the preset model's bare defaults
    // (ADR-080: 28 parameters apart; this one bends, and is the golden "User--Init").
    identity = presets->library.initialPreset();
    identity.apply(*kernel);
    // ADR-082: from here on the tempo PARAMETER moves what is synced to it by note value, as a
    // host's tempo does. (Presets reach this kernel as parameter values, never through `apply`.)
    kernel->tempoParameterKeepsNoteValues = true;
    const auto rateContext = [this] {
        return s1plugin::RateContext { hostParameter(S1Parameter::tempoSyncToArpRate).plainValue() >= 0.5f,
                                       hostParameter(S1Parameter::arpRate).plainValue() };
    };
    for (const s1plugin::ParameterDescription &description : s1plugin::makeParameterCatalog(*kernel)) {
        const size_t i = size_t(description.address);
        auto parameter = std::make_unique<S1HostParameter>(description, rateContext);
        parameterMinimum[i] = description.minimum;
        parameterMaximum[i] = description.maximum;
        parameterDefault[i] = description.defaultValue;
        engineValues[i] = kernel->getSynthParameter(description.address);
        parameter->setPlainValueFromEngine(engineValues[i]);
        hostParameters[i] = parameter.get();
        // MIDI moves these two in the engine as well (ADR-075): the pitch wheel, and the mod
        // wheel's default routing. The LFO rates it can also be routed to are in the list already.
        const bool midiDriven = description.address == S1Parameter::pitchbend || description.address == S1Parameter::cutoff;
        // And the host's tempo moves this one (ADR-077).
        const bool hostDriven = description.address == S1Parameter::arpRate;
        if (description.engineMayChange || midiDriven || hostDriven) { engineDriven.push_back(int(i)); }
        addParameter(parameter.release());     // enum order = the host's order
    }

    // What is state and not a parameter starts as the kernel has it: 12-tone equal temperament.
    for (int note = 0; note < 128; ++note) { tuningFrequencies[size_t(note)].store(kernel->getTuningTableFrequency(note), std::memory_order_relaxed); }
    tuningNotesPerOctave.store(kernel->getTuningTableNPO(), std::memory_order_relaxed);
    if (identity.uid.empty()) { identity.uid = s1::Preset::newUID(); }

    // The order values go to the kernel in: the sync switch and the tempo first, so that a rate
    // written in the same block is read under the sync and tempo written with it — the kernel
    // quantises a rate as it arrives, by the switch as it stands at that moment.
    sendOrder.reserve(size_t(kParameterCount));
    sendOrder.push_back(int(S1Parameter::tempoSyncToArpRate));
    sendOrder.push_back(int(S1Parameter::arpRate));
    for (int i = 0; i < kParameterCount; ++i) {
        if (i != int(S1Parameter::tempoSyncToArpRate) && i != int(S1Parameter::arpRate)) { sendOrder.push_back(i); }
    }
}

S1PluginProcessor::~S1PluginProcessor() = default;

void S1PluginProcessor::prepareToPlay(double sampleRate, int) {
    // The kernel renders any number of frames into the host's own buffers, so the block size
    // is of no interest to it.
    deliverPendingToKernel();   // a loaded tuning, before prepareToRender carries the table across
    // Nothing is rendering now, so the kernel can be written directly: whatever the host has set
    // since the last block (a whole session's state, typically) goes in before the kernel is
    // prepared, and prepareToRender carries it across its re-initialisation (ADR-073's PORT FIX).
    for (const int i : sendOrder) {
        const float value = hostParameters[size_t(i)]->plainValue();
        if (juce::exactlyEqual(value, engineValues[size_t(i)])) { continue; }
        engineValues[size_t(i)] = value;
        kernel->setSynthParameter(S1Parameter(i), value);
    }
    kernel->prepareToRender(2, sampleRate);                         // allocateRenderResources
    // What the engine made of the rates (ADR-022) is NOT reported here any more (ADR-093). It was,
    // quietly — and Apple's auval sets a parameter, re-initialises with no audio between, reads it
    // back, and fails the plugin when it has moved ("did not retain set value when Initialized":
    // Seq Step Length, 0.309 written, 0.249 back — its nearest note value). Logic will not load an
    // AU that fails auval. `engineValues` keeps what was WRITTEN, so the first rendered block sees
    // the difference and reports it the way every later one does: as the engine's report, with a
    // notification, not as a silent change under the host.
}

void S1PluginProcessor::releaseResources() {}

bool S1PluginProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const {
    // The engine is stereo from the oscillators' detune to the reverb; there is no mono render.
    return layouts.getMainOutputChannelSet() == juce::AudioChannelSet::stereo()
        && layouts.getMainInputChannelSet().isDisabled();
}

// MARK: - Render

void S1PluginProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &midi) S1_NONBLOCKING {
    // X2-7 (ADR-078): flush-to-zero and denormals-are-zero for the whole call, the caller's mode
    // put back on the way out. First, so that everything below — the play head included, which
    // is how PluginDenormalTests sees it — runs under it.
    const juce::ScopedNoDenormals noDenormals;
    const int frameCount = buffer.getNumSamples();
    if (buffer.getNumChannels() < 2) { buffer.clear(); return; }
    float *left = buffer.getWritePointer(0);
    float *right = buffer.getWritePointer(1);
    for (int channel = 2; channel < buffer.getNumChannels(); ++channel) { buffer.clear(channel, 0, frameCount); }

    // The block is rendered in one piece unless it carries more events than `events` holds;
    // then it is cut at the event that did not fit. Offsets are relative to the piece's start.
    int start = 0, count = 0;

    // Every parameter a host (or the editor) has moved since the last block, as an event at the
    // block's first sample. JUCE hands a plugin one value per parameter per block; sample-accurate
    // automation and ramps are X2-3.
    const HostTransport transport = readHostTransport();
    hostTempoInUse.store(transport.tempo.has_value(), std::memory_order_relaxed);
    for (const int i : sendOrder) {
        // ADR-077: while the host has a tempo, the tempo parameter is reported and not obeyed.
        if (i == int(S1Parameter::arpRate) && transport.tempo) { continue; }
        const float value = hostParameters[size_t(i)]->plainValue();
        if (juce::exactlyEqual(value, engineValues[size_t(i)])) { continue; }
        engineValues[size_t(i)] = value;
        S1Event &event = events[size_t(count++)];
        event = S1Event {};
        event.kind = S1EventKind_Parameter;
        event.address = S1ParameterAddress(i);
        event.value = value;
    }

    deliverPendingToKernel();

    // The host's tempo and transport, before anything of this block is rendered and in the AUv3's
    // order (ADR-025). Both calls act on a difference only: the tempo against `arpRate` as the
    // kernel holds it — so a preset's or a session's tempo is corrected before its first sample —
    // and the transport on the edge to stopped.
    if (transport.tempo) { kernel->handleTempoSetting(*transport.tempo); }
    if (transport.playing) { kernel->handleTransportState(*transport.playing); }

    // The router's once-a-cycle checks (mono or hold switched: every held key is released), before
    // this block's events and on the thread that plays them — as the AUv3's render block does.
    kernel->hostMIDI.beginRenderCycle(*kernel);

    auto render = [&](int upTo) {
        kernel->setOutput(left + start, right + start);
        kernel->processWithEvents(S1FrameCount(upTo - start), events.data(), count);
        start = upTo;
        count = 0;
    };

    if (panicRequested.exchange(false, std::memory_order_relaxed)) {
        // The interface's Panic (X3-3): CC 123 at the block's first sample, as a host would send it
        S1Event &event = events[size_t(count++)];
        event = S1Event {};
        event.kind = S1EventKind_MIDI;
        event.sampleOffset = 0;
        event.midi.length = 3;
        event.midi.data[0] = 0xB0; event.midi.data[1] = 123; event.midi.data[2] = 0;
    }
    // X3-8: what the interface's own keyboard played since the last block, at this block's first
    // sample and through the router — the same events, in the same array, as the host's.
    {
        const int written = interfaceMIDIWritten.load(std::memory_order_acquire);
        int read = interfaceMIDIRead.load(std::memory_order_relaxed);
        while (read != written) {
            if (count == kMaximumEventsPerRender) { render(start); }
            const juce::uint32 packed = interfaceMIDI[size_t(read % kInterfaceMIDIQueue)].load(std::memory_order_relaxed);
            read = (read + 1) % (kInterfaceMIDIQueue * 2);
            S1Event &event = events[size_t(count++)];
            event = S1Event {};
            event.kind = S1EventKind_MIDI;
            event.sampleOffset = 0;
            event.midi.length = 3;
            event.midi.data[0] = juce::uint8((packed >> 16) & 0xFF);
            event.midi.data[1] = juce::uint8((packed >> 8) & 0xFF);
            event.midi.data[2] = juce::uint8(packed & 0xFF);
        }
        interfaceMIDIRead.store(read, std::memory_order_release);
    }
    for (const juce::MidiMessageMetadata metadata : midi) {
        if (metadata.numBytes < 1 || metadata.numBytes > 3) { continue; }   // no SysEx in this engine
        const int position = std::clamp(metadata.samplePosition, start, std::max(start, frameCount - 1));
        if (count == kMaximumEventsPerRender) { render(position); }

        S1Event &event = events[size_t(count++)];
        event = S1Event {};
        event.kind = S1EventKind_MIDI;
        event.sampleOffset = S1FrameCount(position - start);
        event.midi.length = uint16_t(metadata.numBytes);
        std::copy_n(metadata.data, metadata.numBytes, event.midi.data);   // the router reads a note-on at velocity 0 as a note-off
    }
    render(frameCount);

    // The scope's ring (X3-3): plain stores, no lock, nothing allocated
    int written = scopeWritten.load(std::memory_order_relaxed);
    for (int frame = 0; frame < frameCount; ++frame) {
        scopeRing[size_t(written)].store(left[frame], std::memory_order_relaxed);   // the left channel, as the Mac's plot: a widened sound's two sides cancel in a sum
        written = (written + 1) % kScopeLength;
    }
    scopeWritten.store(written, std::memory_order_relaxed);

    // What the engine made of it (ADR-022): a rate written while tempo sync is on is now the
    // nearest note value, and a new tempo or sync setting has re-driven all four rates. The
    // host is told — off the message thread that is a VST3 output parameter change, a report
    // and not an edit — unless it wrote the parameter again while this block rendered.
    for (const int i : engineDriven) {
        const float value = kernel->getSynthParameter(S1Parameter(i));
        float written = engineValues[size_t(i)];
        // Under a host tempo a value written to the tempo parameter never went to the kernel, so
        // it is the parameter itself that is compared, and put back (ADR-077).
        if (i == int(S1Parameter::arpRate) && transport.tempo) { written = hostParameters[size_t(i)]->plainValue(); }
        if (juce::exactlyEqual(value, written)) { continue; }
        engineValues[size_t(i)] = value;
        S1HostParameter &parameter = *hostParameters[size_t(i)];
        // If the host wrote it again meanwhile, its value stays, differs from `value`, and goes out next block.
        if (parameter.replacePlainValueFromEngine(written, value)) {
            parameter.sendValueChangedMessageToListeners(parameter.getValue());
        }
    }
}

// MARK: - The host's tempo and transport (ADR-077)

S1PluginProcessor::HostTransport S1PluginProcessor::readHostTransport() const {
    // Only valid inside processBlock. A standalone has no play head, and a host need not fill in
    // either field: what is missing is left alone — the plugin's own tempo, no transport edges.
    HostTransport transport;
    const juce::AudioPlayHead *playHead = getPlayHead();
    if (playHead == nullptr) { return transport; }
    const juce::Optional<juce::AudioPlayHead::PositionInfo> position = playHead->getPosition();
    if (!position.hasValue()) { return transport; }
    if (const juce::Optional<double> bpm = position->getBpm(); bpm.hasValue() && std::isfinite(*bpm) && *bpm > 0) {
        transport.tempo = float(*bpm);
    }
    transport.playing = position->getIsPlaying() || position->getIsRecording();
    return transport;
}

// MARK: - State (ADR-076)

void S1PluginProcessor::deliverPendingToKernel() {
    // X3-6: the interface's own mod wheel (the cabinet's joystick), through the same call CC 1
    // takes. Allocation-free, on the audio thread, like the panic flag.
    if (interfaceModWheelPending.exchange(false, std::memory_order_acquire)) {
        const float position = interfaceModWheel.load(std::memory_order_relaxed);
        s1plugin::applyModWheel(*kernel, getModWheelRouting(), int(std::lround(position * 127.0f)));
    }
    if (tuningPending.exchange(false, std::memory_order_acquire)) {
        for (int note = 0; note < 128; ++note) { kernel->setTuningTable(tuningFrequencies[size_t(note)].load(std::memory_order_relaxed), note); }
        kernel->setTuningTableNPO(tuningNotesPerOctave.load(std::memory_order_relaxed));
    }
    if (sequencerResetPending.exchange(false, std::memory_order_acquire)) {
        kernel->resetSequencer();
    }
}

s1plugin::PluginState S1PluginProcessor::currentState() const {
    s1plugin::PluginState state;
    for (int i = 0; i < kParameterCount; ++i) { state.parameters[size_t(i)] = hostParameters[size_t(i)]->plainValue(); }
    for (int note = 0; note < 128; ++note) { state.tuningFrequencies[size_t(note)] = tuningFrequencies[size_t(note)].load(std::memory_order_relaxed); }
    state.tuningNotesPerOctave = tuningNotesPerOctave.load(std::memory_order_relaxed);
    {
        const juce::ScopedLock lock(identityLock);
        state.preset = identity;
    }
    state.preset.modWheelRouting = double(modWheelRouting.load(std::memory_order_relaxed));
    const S1HostMIDI &router = kernel->hostMIDI;   // atomics, written only from here and from an interface
    state.midi.octaveShift = router.octaveShift.load(std::memory_order_relaxed);
    state.midi.channel = router.midiChannel.load(std::memory_order_relaxed);
    state.midi.omni = router.omniMode.load(std::memory_order_relaxed);
    state.midi.whiteKeysOnly = router.whiteKeysOnly.load(std::memory_order_relaxed);
    state.midi.hold = router.holdMode.load(std::memory_order_relaxed);
    state.window.keyboardShown = drawerShown.load(std::memory_order_relaxed);
    return state;
}

void S1PluginProcessor::applyState(const s1plugin::PluginState &state) {
    // The parameters: the plain value exactly as the state has it (no trip through 0…1), then the
    // listeners — an editor, and the host's wrapper, which inside its own setState does not take
    // this for an edit. processBlock or prepareToPlay carries the values to the kernel.
    for (const int i : sendOrder) {
        S1HostParameter &parameter = *hostParameters[size_t(i)];
        const float value = parameter.getNormalisableRange().snapToLegalValue(state.parameters[size_t(i)]);
        if (juce::exactlyEqual(value, parameter.plainValue())) { continue; }
        parameter.setPlainValueFromEngine(value);
        parameter.sendValueChangedMessageToListeners(parameter.getValue());
    }
    for (int note = 0; note < 128; ++note) { tuningFrequencies[size_t(note)].store(state.tuningFrequencies[size_t(note)], std::memory_order_relaxed); }
    tuningNotesPerOctave.store(state.tuningNotesPerOctave, std::memory_order_relaxed);
    tuningPending.store(true, std::memory_order_release);
    sequencerResetPending.store(true, std::memory_order_release);

    const int routing = int(std::lround(state.preset.modWheelRouting));
    modWheelRouting.store(juce::jlimit(0, 2, routing), std::memory_order_relaxed);
    {
        const juce::ScopedLock lock(identityLock);
        identity = state.preset;
    }
    // A session that was on a factory preset shows the host that program again.
    if (const int program = factoryProgramOf(state.preset); program >= 0) { currentProgram.store(program, std::memory_order_relaxed); }
    S1HostMIDI &router = kernel->hostMIDI;
    router.octaveShift.store(state.midi.octaveShift, std::memory_order_relaxed);
    router.midiChannel.store(state.midi.channel, std::memory_order_relaxed);
    router.omniMode.store(state.midi.omni, std::memory_order_relaxed);
    router.whiteKeysOnly.store(state.midi.whiteKeysOnly, std::memory_order_relaxed);
    router.holdMode.store(state.midi.hold, std::memory_order_relaxed);
    drawerShown.store(state.window.keyboardShown, std::memory_order_relaxed);
}

void S1PluginProcessor::getStateInformation(juce::MemoryBlock &destination) {
    const std::string text = currentState().toJSON(JucePlugin_VersionString);
    destination.replaceAll(text.data(), text.size());
}

void S1PluginProcessor::setStateInformation(const void *data, int size) {
    if (data == nullptr || size <= 0) { return; }
    const s1::PresetDefaults defaults = [this](S1Parameter p) { return double(parameterDefault[size_t(p)]); };
    // Anything that is not a state of this format changes nothing: a host handing back another
    // plugin's chunk, or a truncated file, must not leave half a sound behind.
    if (const auto state = s1plugin::PluginState::fromJSON(std::string(static_cast<const char *>(data), size_t(size)),
                                                           currentState(), parameterMinimum, parameterMaximum, defaults)) {
        applyState(*state);
    }
}

// MARK: - What the router forwards (render thread)

void S1PluginProcessor::hostMIDIControlDidArrive(const S1HostMIDIMessage &message) {
    // The router forwards every controller before it looks at the channel; `receivedMIDIController`
    // on the Mac checks it first. Omni is the only setting there is until an interface brings another.
    if ((message.status & 0xF0) != 0xB0) { return; }      // program change and bank select: X2-9's presets
    if (message.data1 == 1) {
        s1plugin::applyModWheel(*kernel, getModWheelRouting(), message.data2);
    }
}

// MARK: - Programs and presets (ADR-080)

int S1PluginProcessor::getNumPrograms() { return std::max(1, presets->library.factoryProgramCount()); }

int S1PluginProcessor::getCurrentProgram() {
    // A new instance plays Init, and Init is in the list: its last entry, "User: Init". Found out
    // when a host asks, not when the plugin is made — the banks are not parsed for a scan.
    const int program = currentProgram.load(std::memory_order_relaxed);
    return program >= 0 ? program : std::max(0, presets->library.factoryProgramCount() - 1);
}

const juce::String S1PluginProcessor::getProgramName(int program) {
    // The name exactly as the AUv3 gives it — four factory presets end in a space — and "Init"
    // only where there is none at all (outside the list).
    const juce::String name = juce::String::fromUTF8(presets->library.factoryProgramName(program).c_str());
    return name.trim().isEmpty() ? juce::String("Init") : name;
}

void S1PluginProcessor::setCurrentProgram(int program) {
    const s1::Preset *preset = presets->library.factoryProgram(program);
    if (preset == nullptr) { return; }
    loadPreset(*preset, false);
}

int S1PluginProcessor::factoryProgramOf(const s1::Preset &preset) {
    for (int program = 0; program < presets->library.factoryProgramCount(); ++program) {
        const s1::Preset *candidate = presets->library.factoryProgram(program);
        if (candidate->uid == preset.uid && candidate->name == preset.name) { return program; }
    }
    return -1;
}

void S1PluginProcessor::loadPreset(const s1::Preset &preset, bool asEdit) {
    s1plugin::PresetParameters values = s1plugin::presetParameters(preset);
    values[size_t(S1Parameter::pitchbend)] = parameterDefault[size_t(S1Parameter::pitchbend)];   // a wheel's position is no part of a sound
    // ADR-082: under a host's tempo the preset's own tempo is not played — so what it has synced
    // is moved to the host's tempo by NOTE VALUE here (a quarter-note delay saved at 100 BPM is a
    // quarter note at the project's 140), where sending the preset's seconds to a kernel at 140
    // would have had them re-quantised to whatever note lies nearest.
    if (isUsingHostTempo() && values[size_t(S1Parameter::tempoSyncToArpRate)] >= 0.5f) {
        S1Rate rates;
        const float presetTempo = values[size_t(S1Parameter::arpRate)];
        const float hostTempo = hostParameter(S1Parameter::arpRate).plainValue();
        for (const S1Parameter p : { S1Parameter::lfo1Rate, S1Parameter::lfo2Rate, S1Parameter::autoPanFrequency }) {
            const float low = parameterMinimum[size_t(p)], high = parameterMaximum[size_t(p)];
            const float kept = rates.frequency(hostTempo, rates.nearestFrequency(values[size_t(p)], presetTempo, low, high).rate);
            if (kept >= low && kept <= high) { values[size_t(p)] = kept; }
        }
        const float low = parameterMinimum[size_t(S1Parameter::delayTime)], high = parameterMaximum[size_t(S1Parameter::delayTime)];
        const float kept = rates.time(hostTempo, rates.nearestTime(values[size_t(S1Parameter::delayTime)], presetTempo, low, high).rate);
        if (kept >= low && kept <= high) { values[size_t(S1Parameter::delayTime)] = kept; }
        values[size_t(S1Parameter::arpRate)] = hostTempo;
    }
    for (const int i : sendOrder) {
        S1HostParameter &parameter = *hostParameters[size_t(i)];
        const float value = parameter.getNormalisableRange().snapToLegalValue(values[size_t(i)]);
        if (juce::exactlyEqual(value, parameter.plainValue())) { continue; }
        // The plain value exactly, as a state's is (ADR-076) — not through 0…1 and back.
        if (asEdit) { parameter.beginChangeGesture(); }
        parameter.setPlainValueFromEngine(value);
        parameter.sendValueChangedMessageToListeners(parameter.getValue());
        if (asEdit) { parameter.endChangeGesture(); }
    }
    sequencerResetPending.store(true, std::memory_order_release);     // Preset::apply ends with it
    modWheelRouting.store(juce::jlimit(0, 2, int(std::lround(preset.modWheelRouting))), std::memory_order_relaxed);
    {
        const juce::ScopedLock lock(identityLock);
        identity = preset;
    }
    // X3-5 (ADR-087): the preset's own tuning, as `PresetDataManager` applies it under
    // `saveTuningWithPreset` (true on the Mac too) — the master set it carries, or 12 ET when it
    // carries none. Then the table is rebuilt at the A4 the preset just set.
    if (tuningTravelsWithPreset) {
        s1plugin::TuningLibrary &library = tuningLibrary();
        if (preset.tuningMasterSet && !preset.tuningMasterSet->empty()) {
            library.setTuning(preset.tuningName.value_or(s1plugin::TuningLibrary::defaultTuningName()), *preset.tuningMasterSet);
        } else {
            library.resetTuning();
        }
    }
    if (tunings != nullptr) { retune(); }
    const int program = factoryProgramOf(preset);
    if (program >= 0 && program != currentProgram.exchange(program, std::memory_order_relaxed)) {
        updateHostDisplay(juce::AudioProcessor::ChangeDetails().withProgramChanged(true));
    }
}

// MARK: - The interface's own settings (X3-6, ADR-088)

namespace {
/// `interface.json` beside the banks' folder, next to `tunings_v1.json`. Tiny, and shared: the
/// standalone and the VST3 open in the same skin.
juce::File interfaceSettingsFile(const s1plugin::PresetLibrary &library) {
    const std::string banks = library.userDirectory();
    if (banks.empty()) { return {}; }
    return juce::File(juce::String::fromUTF8(banks.c_str())).getParentDirectory().getChildFile("interface.json");
}
} // namespace

juce::String S1PluginProcessor::interfaceSkin() const {
    const juce::File file = interfaceSettingsFile(presets->library);
    if (file == juce::File() || !file.existsAsFile()) { return {}; }
    const juce::var json = juce::JSON::parse(file.loadFileAsString());
    return json.isObject() ? json.getProperty("skin", juce::var()).toString() : juce::String();
}

void S1PluginProcessor::setInterfaceSkin(const juce::String &key) {
    const juce::File file = interfaceSettingsFile(presets->library);
    if (file == juce::File()) { return; }
    juce::DynamicObject::Ptr json = new juce::DynamicObject();
    if (file.existsAsFile()) {
        const juce::var had = juce::JSON::parse(file.loadFileAsString());
        if (auto *object = had.getDynamicObject()) { json = new juce::DynamicObject(*object); }
    }
    json->setProperty("skin", key);
    file.getParentDirectory().createDirectory();
    file.replaceWithText(juce::JSON::toString(juce::var(json.get()), true));
}

// MARK: - Tunings (X3-5, ADR-087)

juce::File S1PluginProcessor::defaultTuningDirectory() {
    // Beside the Banks folder, not inside it: `PresetLibrary::userBanks` reads every ".json"
    // there as a bank, and tunings_v1.json would have shown up as one.
    return S1SharedPresets::defaultUserDirectory().getParentDirectory();
}

s1plugin::TuningLibrary &S1PluginProcessor::tuningLibrary() {
    if (tunings == nullptr) {
        // The tunings FOLLOW THE BANKS: their folder is the banks' parent, whatever the banks'
        // folder is. So a test that redirects the preset library — which every test that can
        // reach a bank must, because the real one is the owner's (ADR-036) — redirects these
        // too, and nothing here can write in the owner's folder by being forgotten.
        const std::string banks = presets->library.userDirectory();
        const std::string folder = banks.empty() ? std::string()
                                                 : juce::File(juce::String::fromUTF8(banks.c_str())).getParentDirectory().getFullPathName().toStdString();
        tunings = std::make_unique<s1plugin::TuningLibrary>(folder);
        tunings->load();
        retune();
    }
    return *tunings;
}

void S1PluginProcessor::retune() {
    if (tunings == nullptr) { return; }
    // A4 is a parameter of the sound; the table is built at whatever it holds now. Upstream
    // STORES frequencyA4 and reads it nowhere (ADR-087): here it moves the table's reference.
    const double a4 = double(hostParameter(S1Parameter::frequencyA4).plainValue());
    const std::array<double, S1TuningTable::midiNoteCount> table = tunings->frequencies(a4);
    for (int note = 0; note < 128; ++note) { tuningFrequencies[size_t(note)].store(float(table[size_t(note)]), std::memory_order_relaxed); }
    tuningNotesPerOctave.store(tunings->notesPerOctave(), std::memory_order_relaxed);
    tuningPending.store(true, std::memory_order_release);
    lastTuningA4 = a4;
    // A saved sound must name the tuning it is actually in.
    const juce::ScopedLock lock(identityLock);
    identity.tuningName = tunings->tuningName();
    identity.tuningMasterSet = tunings->masterSet();
}

juce::String S1PluginProcessor::saveCurrentPreset(const juce::String &bankName, const juce::String &name) {
    if (name.trim().isEmpty()) { return "the preset needs a name"; }
    s1::Preset preset = currentState().capturedPreset();      // the identity with the 150 values as they stand
    if (preset.name != name.toStdString() || preset.bank != bankName.toStdString()) { preset.uid = s1::Preset::newUID(); }   // a new sound, not the old one moved
    preset.name = name.trim().toStdString();
    preset.bank = bankName.toStdString();
    const std::string problem = presets->library.savePreset(bankName.toStdString(), preset);
    if (!problem.empty()) { return juce::String::fromUTF8(problem.c_str()); }
    const juce::ScopedLock lock(identityLock);
    identity.name = preset.name;
    identity.bank = preset.bank;
    identity.uid = preset.uid;
    return {};
}

// MARK: - Tail

double S1PluginProcessor::getTailLengthSeconds() const {
    auto value = [this](S1Parameter p) { return double(hostParameter(p).plainValue()); };
    double tail = value(S1Parameter::releaseDuration);
    if (value(S1Parameter::delayOn) >= 0.5 && value(S1Parameter::delayMix) > 0) {
        // Repeats until the feedback has taken them 60 dB down.
        const double feedback = juce::jlimit(0.01, 0.99, value(S1Parameter::delayFeedback));
        tail += value(S1Parameter::delayTime) * std::ceil(std::log(0.001) / std::log(feedback));
    }
    if (value(S1Parameter::reverbOn) >= 0.5 && value(S1Parameter::reverbMix) > 0) {
        // sp_revsc's delay lines are some 0.1 s long: RT60 is about -3 * 0.1 / log10(feedback).
        const double feedback = juce::jlimit(0.01, 0.995, value(S1Parameter::reverbFeedback));
        tail += std::min(30.0, -0.3 / std::log10(feedback));
    }
    return std::min(tail, 60.0);
}

// MARK: - Editor

juce::String S1PluginProcessor::currentPresetBank() const {
    const juce::ScopedLock lock(identityLock);
    return juce::String::fromUTF8(identity.bank.c_str());
}

juce::String S1PluginProcessor::currentPresetName() const {
    const juce::ScopedLock lock(identityLock);
    return juce::String::fromUTF8(identity.name.c_str());
}

// MARK: - The interface's own keyboard (X3-8, ADR-090)

bool S1PluginProcessor::sendMIDIFromInterface(juce::uint8 status, juce::uint8 data1, juce::uint8 data2) {
    // One writer, one reader. The counters run to twice the ring's length so that "full" and
    // "empty" are told apart without a third variable; the slot is the counter modulo its length.
    constexpr int wrap = kInterfaceMIDIQueue * 2;
    const int written = interfaceMIDIWritten.load(std::memory_order_relaxed);
    const int read = interfaceMIDIRead.load(std::memory_order_acquire);
    if ((written - read + wrap) % wrap == kInterfaceMIDIQueue) { return false; }
    interfaceMIDI[size_t(written % kInterfaceMIDIQueue)].store(
        (juce::uint32(status) << 16) | (juce::uint32(data1) << 8) | juce::uint32(data2), std::memory_order_relaxed);
    interfaceMIDIWritten.store((written + 1) % wrap, std::memory_order_release);
    return true;
}

bool S1PluginProcessor::isHolding() const { return kernel->hostMIDI.holdMode.load(std::memory_order_relaxed); }

void S1PluginProcessor::setHolding(bool holding) {
    // The router notices the change at the top of the next block and releases every key when it
    // goes off (`KeyboardView.holdMode`'s didSet) — it is never touched from here.
    kernel->hostMIDI.holdMode.store(holding, std::memory_order_relaxed);
}

int S1PluginProcessor::octaveShift() const {
    return kernel->hostMIDI.octaveShift.load(std::memory_order_relaxed) / 12;
}

void S1PluginProcessor::setOctaveShift(int octaves) {
    // Semitones in the router, as `Manager.midiOctaveShift` is: `typedOctave * 12`.
    kernel->hostMIDI.octaveShift.store(juce::jlimit(-4, 4, octaves) * 12, std::memory_order_relaxed);
}

void S1PluginProcessor::readScope(std::array<float, kScopeLength> &into) const {
    const int written = scopeWritten.load(std::memory_order_relaxed);
    for (int i = 0; i < kScopeLength; ++i) { into[size_t(i)] = scopeRing[size_t((written + i) % kScopeLength)].load(std::memory_order_relaxed); }
}

juce::AudioProcessorEditor *S1PluginProcessor::createEditor() {
    return new S1PluginEditor(*this);           // X3-3 (ADR-085); every parameter is still listed, from Settings
}

juce::AudioProcessor *JUCE_CALLTYPE createPluginFilter() {
    return new S1PluginProcessor();
}
