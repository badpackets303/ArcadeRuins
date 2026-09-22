//
//  S1PluginProcessor.h
//  Arcade Ruins
//
//  X2-1 (ADR-072): the first JUCE processor. It hosts Sources/S1Engine the way
//  Tests/Engine/GoldenHarness.cpp's makeEngine does, because that order is the one proved
//  against the goldens (ADR-071):
//
//      construct -> s1::Wavetables::apply -> parameters read and written back
//                -> prepareToRender (prepareToPlay)
//                -> setOutput + processWithEvents (processBlock)
//
//  X2-2 (ADR-073): the 150 parameters. A host writes an S1HostParameter from any thread; the
//  kernel is only ever touched from processBlock, which turns every value that differs from the
//  one it last gave the kernel into an S1Event, and afterwards reads back the few parameters the
//  engine rewrites itself (ADR-022) and reports them to the host. The parameters start as Init.
//
//  X2-4 (ADR-075): MIDI goes through the engine's own router, S1HostMIDI — the render-thread port
//  of the standalone's MIDI chain that the Catalyst AUv3 uses (ADR-031): channel and omni, octave
//  shift, the sustain pedal, hold, mono's return to the highest held key, pitch bend. What the
//  router hands to "the interface" — the mod wheel — is done here, on the render thread too.
//
//  X2-5 (ADR-076): state. The session holds S1PluginState's JSON — the 150 parameters by ID, the
//  engine's preset JSON, the tuning table, the router's settings. It is built from the HOST
//  parameters and the processor's own copies, never from the kernel, because a host saves while
//  audio runs; and a loaded state reaches the kernel the way everything else does, at the top of
//  the next processBlock or in prepareToPlay.
//
//  X2-6 (ADR-077): the host's tempo and transport, read from the play head at the top of every
//  block and given to the kernel's own two handlers, as the AUv3's render block does (ADR-025).
//  While the host has a tempo it IS the tempo: the tempo parameter is reported, not obeyed.
//
#pragma once

#include <array>
#include <memory>
#include <optional>

#include <juce_audio_processors/juce_audio_processors.h>

#include "S1DSPKernel.hpp"
#include "S1HostParameter.h"
#include "S1KernelListener.hpp"
#include "S1ModWheel.hpp"
#include "S1PluginState.hpp"
#include "S1PresetLibrary.hpp"
#include "S1TuningLibrary.hpp"
#include "S1Wavetables.hpp"

/// The 52 tables decoded once per process, however many instances a host opens
/// (juce::SharedResourcePointer). apply() copies them into each kernel.
struct S1SharedWavetables {
    S1SharedWavetables();
    s1::Wavetables tables;
};

/// X2-9 (ADR-080): the preset library, one per process like the tables: the thirteen factory
/// banks from the data linked into the binary (parsed when first asked for, not when a host
/// scans the plugin), and the user's banks in the per-user folder every format on the machine
/// shares. Constructing it touches no disk.
struct S1SharedPresets {
    S1SharedPresets();
    s1plugin::PresetLibrary library;
    /// <per-user application data>/BadPackets/Arcade Ruins/Banks
    static juce::File defaultUserDirectory();
};

class S1PluginProcessor final : public juce::AudioProcessor, private S1KernelListener {
public:
    S1PluginProcessor();
    ~S1PluginProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) S1_NONBLOCKING override;
    using juce::AudioProcessor::processBlock;

    juce::AudioProcessorEditor *createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return JucePlugin_Name; }
    bool acceptsMidi() const override { return true; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    /// An estimate from the release, delay and reverb parameters as they stand (ADR-073).
    double getTailLengthSeconds() const override;

    // X2-9 (ADR-080): a host's programs are the 695 factory presets, in the Mac AUv3's order and
    // under its names ("Bank: Preset") — never empty; Steinberg's validator fails a program with
    // no name (ADR-079). A host calls these on its controller thread, never the audio thread.
    int getNumPrograms() override;
    int getCurrentProgram() override;
    void setCurrentProgram(int) override;
    const juce::String getProgramName(int) override;
    void changeProgramName(int, const juce::String &) override {}

    /// The library: factory banks, and the user's on disk. Any thread but the audio thread.
    s1plugin::PresetLibrary &presetLibrary() { return presets->library; }

    // X3-5 (ADR-087): the tunings.
    /// The tuning banks and what is chosen, read from disk on first use — never on a host's scan.
    /// Per instance, as a session's tuning is: two instances can be in two tunings. Message thread.
    s1plugin::TuningLibrary &tuningLibrary();
    /// `tunings_v1.json` sits in the folder ABOVE the banks: `PresetLibrary::userBanks` reads
    /// every ".json" beside the banks as a bank.
    static juce::File defaultTuningDirectory();
    /// Rebuilds the 128 frequencies from the tuning that is chosen and the A4 parameter as it
    /// stands, and hands them to the kernel at the top of the next block. Also what names the
    /// tuning in a saved sound. Message thread.
    void retune();
    /// Whether a preset carries its tuning, and takes it when it is loaded
    /// (`AppSettings.saveTuningWithPreset`, true on the Mac too). Message thread.
    bool savesTuningWithPreset() const { return tuningTravelsWithPreset; }
    void setSavesTuningWithPreset(bool yes) { tuningTravelsWithPreset = yes; }
    /// The A4 the table was last built at — for tests, and for an interface watching it move.
    double tuningA4() const { return lastTuningA4; }

    // X3-6 (ADR-088): which skin the window opens in. Not a sound, so it is not a parameter and
    // not in the session's state: it is the person's, kept beside the banks and shared by every
    // instance and both formats, as the Mac keeps its own in preferences. Message thread.
    juce::String interfaceSkin() const;
    void setInterfaceSkin(const juce::String &key);
    /// Makes `preset` the sound: its 150 values as a new engine plays them (through a scratch
    /// kernel, in upstream's order — ADR-076), the wheel centred, its name and routing, the
    /// sequencer reset. The tuning table stays as it is (presets' tunings are X3-5's). `asEdit`:
    /// chosen by a person in an interface — every changed parameter inside a gesture, so a host
    /// records it; otherwise reported without one, as a host's own program change is.
    /// Message thread.
    void loadPreset(const s1::Preset &preset, bool asEdit);
    /// The sound as it stands, into the user bank `bankName` under `name`; it becomes the
    /// current preset. Empty on success, else why not. Any thread but the audio thread.
    juce::String saveCurrentPreset(const juce::String &bankName, const juce::String &name);

    void getStateInformation(juce::MemoryBlock &) override;
    void setStateInformation(const void *, int) override;

    /// The state as it stands, and a state put in place — what the two calls above wrap, and
    /// what a preset browser will use (X2-9). Any thread but the audio thread.
    s1plugin::PluginState currentState() const;
    void applyState(const s1plugin::PluginState &);

    /// Events one call to processWithEvents can carry: every parameter at once and then some
    /// MIDI. A block with more is rendered in pieces, so nothing is dropped and nothing is
    /// allocated on the audio thread.
    static constexpr int kMaximumEventsPerRender = 512;

    static constexpr int kParameterCount = S1Parameter::S1ParameterCount;
    /// In enum order, which is the order a host lists them in. Owned by juce::AudioProcessor.
    S1HostParameter &hostParameter(S1Parameter p) const { return *hostParameters[size_t(p)]; }
    /// For tests: what the kernel holds. Only meaningful while no render is running.
    float engineValue(S1Parameter p) const { return kernel->getSynthParameter(p); }
    /// The preset's mod wheel routing. Not one of the 150 parameters: it travels with the plugin's
    /// state (X2-5). Any thread.
    void setModWheelRouting(s1plugin::ModWheelRouting routing) { modWheelRouting.store(int(routing), std::memory_order_relaxed); }
    s1plugin::ModWheelRouting getModWheelRouting() const { return s1plugin::ModWheelRouting(modWheelRouting.load(std::memory_order_relaxed)); }

    /// Whether the last block was rendered at a tempo the host gave — an interface shows its
    /// tempo control as the host's then. Any thread.
    bool isUsingHostTempo() const { return hostTempoInUse.load(std::memory_order_relaxed); }
    /// The sequencer's step count as the kernel last reported it, for an interface's step lights
    /// (and for tests). Any thread.
    int arpBeatCounter() const { return lastArpBeatCounter.load(std::memory_order_relaxed); }

    // X3-3 (ADR-085): what the interface needs besides the parameters.
    /// The current sound's bank and name, as the toolbar shows them. Message thread.
    juce::String currentPresetBank() const;
    juce::String currentPresetName() const;
    /// X3-6 (ADR-088): the cabinet's joystick moves the mod wheel. It cannot touch the kernel
    /// from the message thread, so it leaves the wheel's position here and the next block applies
    /// it through the same call a CC 1 takes. 0…1. Any thread.
    void setModWheelFromInterface(float position01) {
        interfaceModWheel.store(juce::jlimit(0.0f, 1.0f, position01), std::memory_order_relaxed);
        interfaceModWheelPending.store(true, std::memory_order_release);
    }
    /// Panic: every note off at the top of the next block, through the router's own CC 123 — the
    /// kernel is never touched from the message thread. Any thread.
    void requestAllNotesOff() { panicRequested.store(true, std::memory_order_relaxed); }

    // X3-8 (ADR-090): the interface's own keyboard.
    /// One MIDI message from the interface — a key pressed on the drawer, Hold as a damper pedal,
    /// a wheel moved — delivered at the top of the next block, **before** the host's own events
    /// and through the same router. It is not "like" the host's route: it IS the host's route, so
    /// the octave shift, white keys, hold, mono, the arpeggiator and every held-key bookkeeping
    /// happen once, in one place (ADR-031). False: the queue is full and the message was dropped.
    /// Any thread but the audio thread; nothing here allocates.
    bool sendMIDIFromInterface(juce::uint8 status, juce::uint8 data1, juce::uint8 data2);
    /// Hold (`KeyboardView.holdMode`): a note-off is ignored while it is on, and turning it off
    /// releases every key — the router does both. Per instance, in the session's state. Any thread.
    bool isHolding() const;
    void setHolding(bool holding);
    /// The `Octave:` shift the router gives every note that arrives, the drawer's and the host's
    /// alike (upstream's `soundingNote(for:)`). Per instance. Any thread.
    int octaveShift() const;
    void setOctaveShift(int octaves);
    /// Whether this instance's window shows the keyboard drawer. Not a sound and not shared with
    /// other instances: it travels in the session's state, closed by default (X3-8). Any thread.
    bool keyboardShown() const { return drawerShown.load(std::memory_order_relaxed); }
    void setKeyboardShown(bool shown) { drawerShown.store(shown, std::memory_order_relaxed); }
    /// Which notes the router is holding, as a 128-bit set: the drawer lights them, whoever played
    /// them — `KeyboardView.hostOnKeys` does the same on the Mac. Reported from the render thread,
    /// read anywhere.
    void heldKeys(juce::uint64 &low, juce::uint64 &high) const {
        low = heldKeysLow.load(std::memory_order_relaxed);
        high = heldKeysHigh.load(std::memory_order_relaxed);
    }
    /// The scope: the last `kScopeLength` samples of the left output, oldest first,
    /// copied from a ring the render thread writes without locks. A torn read costs one frame of
    /// a picture. Any thread but the audio thread.
    static constexpr int kScopeLength = 1024;
    void readScope(std::array<float, kScopeLength> &into) const;

    /// For tests: a note's frequency as the kernel has it. Only meaningful while no render is running.
    float engineTuningFrequency(int note) const { return kernel->getTuningTableFrequency(note); }
    /// For tests: the router's trace of the notes it played (S1HostMIDITrace).
    S1HostMIDITrace &hostMIDITrace() { return kernel->hostMIDI.trace; }
    /// For tests: where a smoothed parameter's glide has got to (the value the DSP is using now).
    float engineValueInUse(S1Parameter p) const { return kernel->parameters[size_t(p)]; }

private:
    // S1KernelListener — every one of these is called on the render thread, inside processBlock.
    // Only the controllers the router forwards are acted on; the rest is for an interface (X3).
    void hostMIDIControlDidArrive(const S1HostMIDIMessage &message) override;
    void hostTempoDidChange(float) override {}
    void dependentParameterDidChange(const DependentParameter &) override {}
    void arpBeatCounterDidChange(const S1ArpBeatCounter &counter) override { lastArpBeatCounter.store(counter.beatCounter, std::memory_order_relaxed); }
    void playingNotesDidChange(const PlayingNotes &) override {}
    void heldNotesDidChange(const HeldNotes &) override {}
    /// X3-8: kept for the drawer to light. Render thread, so it is only two relaxed stores.
    bool hostHeldKeysDidChange(const S1HostKeys &keysDown) override {
        heldKeysLow.store(keysDown.low, std::memory_order_relaxed);
        heldKeysHigh.store(keysDown.high, std::memory_order_relaxed);
        return true;
    }

    juce::SharedResourcePointer<S1SharedWavetables> wavetables;
    juce::SharedResourcePointer<S1SharedPresets> presets;
    std::unique_ptr<s1plugin::TuningLibrary> tunings;
    bool tuningTravelsWithPreset = true;
    double lastTuningA4 = 440.0;
    std::atomic<int> currentProgram { -1 };               ///< -1: the sound a new instance starts with, the list's last, "User: Init"
    /// The factory program `preset` is, or -1: same uid and name (23 uids are shared in the banks).
    int factoryProgramOf(const s1::Preset &preset);
    std::unique_ptr<S1DSPKernel> kernel;
    std::array<S1Event, kMaximumEventsPerRender> events {};
    std::array<S1HostParameter *, kParameterCount> hostParameters {};
    /// What the kernel was last given (or last reported) for each parameter. Audio thread only,
    /// after the constructor.
    std::array<float, kParameterCount> engineValues {};
    /// The indices of the parameters the engine rewrites itself, to read back after a render.
    std::vector<int> engineDriven;
    /// Every parameter index, in the order changed values are given to the kernel.
    std::vector<int> sendOrder;
    /// What the play head said at the top of this block; an empty field is one the host did not give.
    struct HostTransport {
        std::optional<float> tempo;
        std::optional<bool> playing;
    };
    HostTransport readHostTransport() const;               ///< audio thread, inside processBlock
    std::atomic<bool> hostTempoInUse { false };
    std::atomic<int> lastArpBeatCounter { 0 };
    std::atomic<int> modWheelRouting { int(s1plugin::ModWheelRouting::cutoff) };
    std::atomic<float> interfaceModWheel { 0.0f };
    std::atomic<bool> interfaceModWheelPending { false };

    // State that is not a parameter. The processor's copies are the authority, as the host
    // parameters are for the sound: a state read back before any block has run is still right.
    std::array<std::atomic<float>, 128> tuningFrequencies {};
    std::atomic<int> tuningNotesPerOctave { 12 };
    std::atomic<bool> tuningPending { false };           ///< the kernel has not got the table above yet
    std::atomic<bool> sequencerResetPending { false };   ///< Preset::apply's resetSequencer, owed to the kernel
    void deliverPendingToKernel();                        ///< audio thread, or prepareToPlay
    std::atomic<bool> panicRequested { false };
    /// X3-8: the interface's MIDI, one writer (the message thread) and one reader (the audio
    /// thread). A fixed ring of packed `[status][data1][data2]`, so nothing allocates and nothing
    /// locks; a full queue drops, which needs about 250 keys pressed inside one block.
    static constexpr int kInterfaceMIDIQueue = 256;
    std::array<std::atomic<juce::uint32>, kInterfaceMIDIQueue> interfaceMIDI {};
    std::atomic<int> interfaceMIDIWritten { 0 }, interfaceMIDIRead { 0 };
    std::atomic<juce::uint64> heldKeysLow { 0 }, heldKeysHigh { 0 };
    std::atomic<bool> drawerShown { false };
    std::array<std::atomic<float>, kScopeLength> scopeRing {};
    std::atomic<int> scopeWritten { 0 };                  ///< samples written so far, modulo the ring
    mutable juce::CriticalSection identityLock;           ///< never taken on the audio thread
    s1::Preset identity;                                  ///< name, bank, uid, text, tuning name… (not the values)
    std::array<float, kParameterCount> parameterMinimum {}, parameterMaximum {}, parameterDefault {};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(S1PluginProcessor)
};
