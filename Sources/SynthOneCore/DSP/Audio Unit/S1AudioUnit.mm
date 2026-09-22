//
//  S1AudioUnit.mm
//  AudioKit
//
//  Created by AudioKit Contributors, revision history on Github.
//  Join us at AudioKitPro.com, github.com/audiokit
//

#import "S1AudioUnit.h"
#import "S1DSPKernel.hpp"
#import "AudioKit/AKDSPKernel.hpp"   // X1-3: DSPKernel and AKOutputBuffered, for the adapter below
#import "AEMessageQueue.h"
#import "AudioKit/BufferedAudioBus.hpp"
// PORT: AKSettings is Swift in a static library, so it has no Obj-C
// interface header here. Its three DSP-facing scalars are read through
// C storage instead (ADR-010).
#import "AKSettingsBridge.h"

#include <atomic>
#include <fenv.h>   // X2-7: FE_DFL_DISABLE_DENORMS_ENV

namespace {

/// The last `S1_SCOPE_CAPACITY` output samples, handed from the render thread to the
/// waveform display without a lock (P4-6).
///
/// **Why the traffic runs this way round.** The standalone's plot calls
/// `AVAudioNode.installTap`, which allocates a buffer and `dispatch_async`es it to the
/// main thread. A plugin has no node to tap — the host owns the graph — and neither
/// allocating nor dispatching is legal on the render thread. So the render thread
/// writes into fixed storage it already owns, and the main thread pulls a copy when it
/// is ready to draw.
///
/// A seqlock, which is the standard shape for one real-time writer and one lazy reader.
/// `seq` is odd while a write is in progress; a reader that sees it odd, or sees it
/// change across the copy, retries a few times and then gives up. **The writer never
/// waits.** That is the property that matters: a torn read costs one frame of a
/// decoration, and a blocked render thread costs an audible dropout.
///
/// Every field is atomic because the reader deliberately races the writer. The samples
/// use relaxed ordering — they compile to plain loads and stores — and the
/// acquire/release pair on `seq` is what actually orders the two sides.
struct S1Scope {
    std::atomic<bool>     enabled{false};
    std::atomic<uint32_t> seq{0};
    std::atomic<uint32_t> write{0};
    std::atomic<float>    ring[S1_SCOPE_CAPACITY];

    S1Scope() {
        // Explicit: a default-constructed `std::atomic<float>` does not initialise its
        // value before C++20, and this array is read by the other thread.
        for (uint32_t i = 0; i < S1_SCOPE_CAPACITY; ++i) {
            ring[i].store(0.f, std::memory_order_relaxed);
        }
    }

    /// Render thread. No allocation, no locks, no unbounded work.
    void push(const float *samples, uint32_t count) {
        if (!enabled.load(std::memory_order_relaxed) || samples == nullptr || count == 0) return;
        // A render longer than the ring: keep the newest samples, which are the only
        // ones the display would have shown anyway.
        if (count > S1_SCOPE_CAPACITY) {
            samples += (count - S1_SCOPE_CAPACITY);
            count = S1_SCOPE_CAPACITY;
        }
        seq.fetch_add(1, std::memory_order_release);            // odd: write in progress
        uint32_t w = write.load(std::memory_order_relaxed);
        for (uint32_t i = 0; i < count; ++i) {
            ring[w].store(samples[i], std::memory_order_relaxed);
            w = (w + 1) % S1_SCOPE_CAPACITY;
        }
        write.store(w, std::memory_order_relaxed);
        seq.fetch_add(1, std::memory_order_release);            // even: consistent again
    }

    /// Main thread. Oldest sample first, so the waveform reads left to right.
    bool copy(float *destination, uint32_t count) {
        if (destination == nullptr || count == 0 || count > S1_SCOPE_CAPACITY) return false;
        if (!enabled.load(std::memory_order_relaxed)) return false;
        for (int attempt = 0; attempt < 4; ++attempt) {
            const uint32_t before = seq.load(std::memory_order_acquire);
            if (before & 1u) continue;                          // a write is in flight
            const uint32_t w = write.load(std::memory_order_relaxed);
            const uint32_t start = (w + S1_SCOPE_CAPACITY - count) % S1_SCOPE_CAPACITY;
            for (uint32_t i = 0; i < count; ++i) {
                destination[i] = ring[(start + i) % S1_SCOPE_CAPACITY].load(std::memory_order_relaxed);
            }
            if (seq.load(std::memory_order_acquire) == before) return true;
        }
        return false;
    }
};

}  // namespace

@implementation S1MessageRelay

// Every selector the DSP posts. Each is a no-op once the unit has gone, which is the
// entire point: the message is late, not wrong.
- (void)dependentParameterDidChange:(DependentParameter)param {
    [self.unit dependentParameterDidChange:param];
}
- (void)arpBeatCounterDidChange:(S1ArpBeatCounter)counter {
    [self.unit arpBeatCounterDidChange:counter];
}
- (void)heldNotesDidChange:(HeldNotes)notes {
    [self.unit heldNotesDidChange:notes];
}
- (void)playingNotesDidChange:(PlayingNotes)notes {
    [self.unit playingNotesDidChange:notes];
}
- (void)hostTempoDidChange:(float)tempo {
    [self.unit hostTempoDidChange:tempo];
}
- (void)hostMIDIControlDidArrive:(S1HostMIDIMessage)message {
    [self.unit hostMIDIControlDidArrive:message];
}
- (void)hostHeldKeysDidChange:(S1HostKeys)keys {
    [self.unit hostHeldKeysDidChange:keys];
}

@end


// PORT (X1-2, ADR-066): the kernel's messages to the main thread, posted the way the kernel
// itself used to post them.
//
// PORT FIX (P4-5), carried over: these post to `messageRelay`, not to the unit. The queue stores
// its target as a raw pointer and delivers asynchronously, so addressing the unit itself is a
// use-after-free the moment a unit is destroyed with a message in flight. See `S1MessageRelay`.
// Every method runs on the render thread; `AEMessageQueuePerformSelectorOnMainThread` is
// lock-free and allocation-free, which is why it is the one thing called here.
// PORT (X1-3, ADR-067): the kernel no longer inherits Apple's DSPKernel (the AURenderEvent
// splitter) or AKOutputBuffered (an AudioBufferList); those stay here, in the Apple adapter.
// Every render cycle goes: host event list → this splitter (unchanged Apple sample code with the
// P4-2 fix) → the kernel's `startRamp` / `handleMIDIEvent` / `process(frames, offset)`, exactly
// as before, with the kernel's output pointers set from the buffer list first. The kernel's own
// `processWithEvents(frames, S1Event[])` is the same split for hosts that speak S1Event (JUCE).
class S1KernelAUAdapter final : public DSPKernel, public AKOutputBuffered {
public:
    explicit S1KernelAUAdapter(S1DSPKernel &kernel_) : kernel(kernel_) {}

    void process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) override {
        kernel.process(frameCount, bufferOffset);
    }
    void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) override {
        kernel.startRamp(address, value, duration);
    }
    void handleMIDIEvent(AUMIDIEvent const &event) override {
        const S1MIDIEvent midi = {event.length, {event.data[0], event.data[1], event.data[2]}};
        kernel.handleMIDIEvent(midi);
    }
    /// Once per render cycle, before `processWithEvents`.
    void setBuffer(AudioBufferList *outBufferList) {
        AKOutputBuffered::setBuffer(outBufferList);
        kernel.setOutput((float *)outBufferList->mBuffers[0].mData,
                         (float *)outBufferList->mBuffers[outBufferList->mNumberBuffers > 1 ? 1 : 0].mData);
    }

private:
    S1DSPKernel &kernel;
};

struct S1AudioUnitKernelListener final : S1KernelListener {
    AEMessageQueue *queue;          // owned by the unit, which outlives its kernel
    S1MessageRelay *relay;          // immortal (see the relay's comment)

    S1AudioUnitKernelListener(AEMessageQueue *q, S1MessageRelay *r) : queue(q), relay(r) {}

    void hostTempoDidChange(float tempo) override {
        // A local, not `AEArgumentScalar`: that macro builds a C compound literal and
        // takes its address, which Obj-C++ rejects as the address of an rvalue.
        float tempoValue = tempo;
        AEMessageQueuePerformSelectorOnMainThread(queue, relay, @selector(hostTempoDidChange:),
                                                  AEArgumentStruct(tempoValue), AEArgumentNone);
    }
    void dependentParameterDidChange(const DependentParameter &parameter) override {
        DependentParameter value = parameter;
        AEMessageQueuePerformSelectorOnMainThread(queue, relay, @selector(dependentParameterDidChange:),
                                                  AEArgumentStruct(value), AEArgumentNone);
    }
    void arpBeatCounterDidChange(const S1ArpBeatCounter &counter) override {
        S1ArpBeatCounter value = counter;
        AEMessageQueuePerformSelectorOnMainThread(queue, relay, @selector(arpBeatCounterDidChange:),
                                                  AEArgumentStruct(value), AEArgumentNone);
    }
    void playingNotesDidChange(const PlayingNotes &notes) override {
        PlayingNotes value = notes;
        AEMessageQueuePerformSelectorOnMainThread(queue, relay, @selector(playingNotesDidChange:),
                                                  AEArgumentStruct(value), AEArgumentNone);
    }
    void heldNotesDidChange(const HeldNotes &notes) override {
        HeldNotes value = notes;
        AEMessageQueuePerformSelectorOnMainThread(queue, relay, @selector(heldNotesDidChange:),
                                                  AEArgumentStruct(value), AEArgumentNone);
    }
    void hostMIDIControlDidArrive(const S1HostMIDIMessage &message) override {
        S1HostMIDIMessage value = message;
        AEMessageQueuePerformSelectorOnMainThread(queue, relay, @selector(hostMIDIControlDidArrive:),
                                                  AEArgumentStruct(value), AEArgumentNone);
    }
    bool hostHeldKeysDidChange(const S1HostKeys &keys) override {
        S1HostKeys value = keys;
        return AEMessageQueuePerformSelectorOnMainThread(queue, relay, @selector(hostHeldKeysDidChange:),
                                                         AEArgumentStruct(value), AEArgumentNone);
    }
};

@implementation S1AudioUnit {
    // C++ members need to be ivars; they would be copied on access if they were properties.
    std::unique_ptr<S1DSPKernel> _kernel;
    std::unique_ptr<S1KernelAUAdapter> _kernelAdapter;   // X1-3: Apple's event list → the kernel
    std::unique_ptr<S1AudioUnitKernelListener> _kernelListener;   // the render thread is stopped before either is destroyed
    BufferedOutputBus _outputBusBuffer;
    AUHostMusicalContextBlock _musicalContext;
    AUHostTransportStateBlock _transportState;
    AUAudioUnitPreset *_currentPreset;
    S1Scope _scope;
}

@synthesize parameterTree = _parameterTree;
@synthesize s1Delegate = _s1Delegate;
@synthesize factoryPresetSource = _factoryPresetSource;
@synthesize messageRelay = _messageRelay;

- (float)getSynthParameter:(S1Parameter)param {
    return _kernel->getSynthParameter(param);
}

- (void)setSynthParameter:(S1Parameter)param value:(float)value {
    _kernel->setSynthParameter(param, value);
}

- (float)getDependentParameter:(S1Parameter)param {
    return _kernel->getDependentParameter(param);
}

- (void)setDependentParameter:(S1Parameter)param value:(float)value payload:(int)payload {
    _kernel->setDependentParameter(param, value, payload);
}

///auv3
- (void)setParameter:(AUParameterAddress)address value:(AUValue)value {
    _kernel->setSynthParameter((S1Parameter)address, value);
}

///auv3
- (AUValue)getParameter:(AUParameterAddress)address {
    return _kernel->getSynthParameter((S1Parameter)address);
}

- (float)getMinimum:(S1Parameter)param {
    return _kernel->minimum(param);
}

- (float)getMaximum:(S1Parameter)param {
    return _kernel->maximum(param);
}

- (float)getDefault:(S1Parameter)param {
    return _kernel->defaultValue(param);
}

///Deprecated:calling this method to access even a single element of this array results in creating the entire array
- (NSArray<NSNumber*> *)parameters {
    NSMutableArray *temp = [NSMutableArray arrayWithCapacity:S1Parameter::S1ParameterCount];
    for (int i = 0; i < S1Parameter::S1ParameterCount; i++) {
        [temp setObject:[NSNumber numberWithFloat:_kernel->parameters[i]] atIndexedSubscript:i];
    }
    return [NSArray arrayWithArray:temp];
}

///deprecated
- (void)setParameters:(NSArray<NSNumber*> *)parameters {
    float params[S1Parameter::S1ParameterCount];
    for (int i = 0; i < parameters.count; i++) {
        params[i] = [parameters[i] floatValue];
    }
    _kernel->setParameters(params);
}

- (void)resetSequencer {
    _kernel->resetSequencer();
}

- (BOOL)isSetUp {
    return _kernel->resetted;
}

- (void)stopNote:(uint8_t)note {
    _kernel->stopNote(note);
}

- (void)startNote:(uint8_t)note velocity:(uint8_t)velocity {
    _kernel->startNote(note, velocity);
}

- (void)startNote:(uint8_t)note velocity:(uint8_t)velocity frequency:(float)frequency {
    _kernel->startNote(note, velocity, frequency);
}

- (void)setupWaveform:(UInt32)tableIndex size:(int)size {
    _kernel->setupWaveform(tableIndex, (uint32_t)size);
}

- (void)setWaveform:(UInt32)tableIndex withValue:(float)value atIndex:(UInt32)sampleIndex {
    _kernel->setWaveformValue(tableIndex, sampleIndex, value);
}

- (void)setBandlimitFrequency:(UInt32)blIndex withFrequency:(float)frequency {
    _kernel->setBandlimitFrequency(blIndex, frequency);
}

- (void)reset {
    _kernel->reset();
}

///Puts all notes in Release...a kinder, gentler "reset".
- (void)stopAllNotes {
    _kernel->stopAllNotes();
}

///Resets DSP
- (void)resetDSP {
    _kernel->resetDSP();
}



// S1TuningTable protocol
- (void)setTuningTable:(float)frequency index:(int)index {
    _kernel->setTuningTable(frequency, index);
}

- (float)getTuningTableFrequency:(int)index {
    return _kernel->getTuningTableFrequency(index);
}

- (void)setTuningTableNPO:(int)npo {
    _kernel->setTuningTableNPO(npo);
}

- (int)getTuningTableNPO {
    return _kernel->getTuningTableNPO();
}

#pragma mark - Host state (P4-4)

// The host's session file. `AUAudioUnit`'s own `fullState` serialises the
// `AUParameterTree` and nothing else, which for this instrument is *almost*
// everything: all 150 parameters, and that includes the 48 sequencer values
// (`sequencerPattern00…15`, `sequencerOctBoost00…15`, `sequencerNoteOn00…15`),
// which look like separate state but are addressable parameters.
//
// What it does not include is the **tuning table** — 128 arbitrary frequencies
// that the Tunings panel can load from a Scala file, with no parameter address
// and no compact representation to derive them from. `frequencyA4` is a parameter
// and rides along with the rest; the table is not. A preset restored without it
// plays in the wrong temperament, which is a wrong preset.
static NSString *const kS1StateVersionKey = @"com.badpackets303.SynthOne.stateVersion";
static NSString *const kS1TuningTableKey  = @"com.badpackets303.SynthOne.tuningTable";
static NSString *const kS1TuningNPOKey    = @"com.badpackets303.SynthOne.tuningNPO";

- (NSDictionary<NSString *, id> *)fullState {
    NSDictionary *base = [super fullState];
    NSMutableDictionary<NSString *, id> *state =
        base ? [base mutableCopy] : [NSMutableDictionary dictionary];

    float frequencies[S1_NUM_MIDI_NOTES];
    for (int i = 0; i < S1_NUM_MIDI_NOTES; i++) {
        frequencies[i] = _kernel->getTuningTableFrequency(i);
    }
    // `NSData`, not an array of 128 `NSNumber`s: a quarter of the size in every
    // session file that ever saves this plugin, and it round-trips bit-exactly.
    state[kS1TuningTableKey] = [NSData dataWithBytes:frequencies length:sizeof(frequencies)];
    state[kS1TuningNPOKey] = @(_kernel->getTuningTableNPO());
    state[kS1StateVersionKey] = @1;
    return state;
}

- (void)setFullState:(NSDictionary<NSString *, id> *)fullState {
    // Parameters first — `super` restores the tree, and the tuning table is
    // independent of it.
    [super setFullState:fullState];
    if (fullState == nil) { return; }

    // Every read is defensive. This dictionary came out of a file that a *previous
    // build* wrote, and a session saved before P4-4 has none of these keys at all.
    // A missing or malformed value is a default, never a crash: refusing to open
    // is worse than opening in 12-ET.
    NSData *tuning = fullState[kS1TuningTableKey];
    if ([tuning isKindOfClass:[NSData class]] && tuning.length == sizeof(float) * S1_NUM_MIDI_NOTES) {
        const float *frequencies = (const float *)tuning.bytes;
        for (int i = 0; i < S1_NUM_MIDI_NOTES; i++) {
            _kernel->setTuningTable(frequencies[i], i);
        }
    }
    NSNumber *npo = fullState[kS1TuningNPOKey];
    if ([npo isKindOfClass:[NSNumber class]]) {
        _kernel->setTuningTableNPO(npo.intValue);
    }
}

#pragma mark - Factory and user presets (P4-4)

// The 695 shipped presets, offered as one flat host menu. The names and the
// mapping live in Swift (`S1FactoryPresets`); what is here is the `AUAudioUnit`
// surface and the index bookkeeping.
//
// **Numbering.** Apple's convention is factory presets at `number >= 0` and user
// presets below zero, and a host writes that *number* into its session file. The
// order therefore cannot change once anything has been saved — see the note on
// `S1FactoryPresets.bankOrder`.

- (NSArray<AUAudioUnitPreset *> *)factoryPresets {
    id<S1FactoryPresetSource> source = _factoryPresetSource;
    if (source == nil) { return nil; }

    NSArray<NSString *> *names = [source factoryPresetNames];
    NSMutableArray<AUAudioUnitPreset *> *presets =
        [NSMutableArray arrayWithCapacity:names.count];
    [names enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
        AUAudioUnitPreset *preset = [[AUAudioUnitPreset alloc] init];
        preset.number = (NSInteger)index;
        preset.name = name;
        [presets addObject:preset];
    }];
    return presets;
}

- (AUAudioUnitPreset *)currentPreset {
    return _currentPreset;
}

- (void)setCurrentPreset:(AUAudioUnitPreset *)currentPreset {
    if (currentPreset == nil) {
        _currentPreset = nil;
        return;
    }

    // Negative is a *user* preset, which the framework stores as a `fullState`
    // dictionary on our behalf — `supportsUserPresets` below is what buys that, and
    // it is built on the `fullState` above rather than on anything separate.
    if (currentPreset.number < 0) {
        NSError *error = nil;
        NSDictionary *state = [self presetStateFor:currentPreset error:&error];
        if (state != nil) {
            self.fullState = state;
            _currentPreset = currentPreset;
        }
        return;
    }

    // A host can hand back a number from a session saved by a build with a
    // different bank list. Refusing beats applying whatever now sits at that index.
    if ([_factoryPresetSource applyFactoryPresetAt:currentPreset.number to:self]) {
        _currentPreset = currentPreset;
    }
}

// User presets are free once `fullState` is right: the framework serialises and
// stores them itself. Saying NO here would mean a host offering no way to keep a
// sound outside the session that made it.
- (BOOL)supportsUserPresets {
    return YES;
}

// `fullStateForDocument` is deliberately not overridden. Its default forwards to
// `fullState`, and there is nothing this instrument would save differently in a
// document than in a session — no file references, no absolute paths, no
// machine-specific state. Overriding it to do the same thing twice is a second
// place to forget to add a key.


- (void)createParameters {

    _messageQueue = [[AEMessageQueue alloc] init];

    // Held in a static array as well as by us, so it outlives this audio unit and any
    // message still in flight towards it. See `S1MessageRelay` for why.
    static NSMutableArray<S1MessageRelay *> *immortalRelays;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ immortalRelays = [NSMutableArray array]; });
    _messageRelay = [[S1MessageRelay alloc] init];
    _messageRelay.unit = self;
    @synchronized (immortalRelays) { [immortalRelays addObject:_messageRelay]; }

    self.rampDuration = ak_settings_ramp_duration();
    self.defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:ak_settings_sample_rate()
                                                                        channels:ak_settings_channel_count()];
    _kernel = std::make_unique<S1DSPKernel>(self.defaultFormat.channelCount, self.defaultFormat.sampleRate);
    _kernelAdapter = std::make_unique<S1KernelAUAdapter>(*_kernel);
    _outputBusBuffer.init(self.defaultFormat, 2);
    self.outputBus = _outputBusBuffer.bus;
    self.outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                                 busType:AUAudioUnitBusTypeOutput
                                                                  busses:@[self.outputBus]];
    // PORT (X1-2, ADR-066): was `_kernel->audioUnit = self`. The kernel posts through a
    // listener now; this one posts through the message queue to the relay, as the kernel did.
    _kernelListener = std::make_unique<S1AudioUnitKernelListener>(_messageQueue, _messageRelay);
    _kernel->listener = _kernelListener.get();
    __block S1DSPKernel *blockKernel = _kernel.get();
    
    // Create parameter tree
    AudioUnitParameterOptions flags = kAudioUnitParameterFlag_IsWritable | kAudioUnitParameterFlag_IsReadable;

    // PORT FIX (P4-3): `arpRate` and `tempoSyncToArpRate` are not independent
    // parameters. `_setSynthParameterHelper` re-drives lfo1Rate, lfo2Rate,
    // autoPanFrequency and delayTime through `_rateHelper` whenever either of them
    // changes, so one host automation move alters five values in the DSP. Upstream
    // passed `dependentParameters:nil` for every parameter — which was harmless
    // while the tree was never automated, and is not now: a host that automates
    // `arpRate` would keep showing, and on its next pass write back, four stale
    // values it does not know are out of date.
    //
    // Declaring the dependency is the AU-idiomatic fix. It costs nothing on the
    // render thread and cannot feed back: the host re-*reads* the dependents
    // through `implementorValueProvider`, which returns `getSynthParameter` — the
    // quantized truth — rather than being told a new value to write.
    NSArray<NSNumber *> *const tempoDependents = @[ @(S1Parameter::lfo1Rate),
                                                    @(S1Parameter::lfo2Rate),
                                                    @(S1Parameter::autoPanFrequency),
                                                    @(S1Parameter::delayTime) ];

    NSMutableArray<AUParameter*>* tree = [NSMutableArray array];
    for(NSInteger i = S1Parameter::index1; i < S1Parameter::S1ParameterCount; i++) {
        const S1Parameter p = (S1Parameter)i;
        const AUValue minValue = _kernel->minimum(p);
        const AUValue maxValue = _kernel->maximum(p);
        const AUValue defaultValue = _kernel->defaultValue(p);
        const AudioUnitParameterUnit unit = (AudioUnitParameterUnit)_kernel->parameterUnit(p);   // same values (S1EngineTypes.h)
        NSString* friendlyName = [NSString stringWithCString:_kernel->cString(p) encoding:[NSString defaultCStringEncoding]];
        NSString* keyName = [NSString stringWithCString:_kernel->presetKey(p).c_str() encoding:[NSString defaultCStringEncoding]];
        NSArray<NSNumber *> *dependents =
            (p == S1Parameter::arpRate || p == S1Parameter::tempoSyncToArpRate) ? tempoDependents : nil;
        AUParameter *param = [AUParameterTree createParameterWithIdentifier:keyName name:friendlyName address:p min:minValue max:maxValue unit:unit unitName:nil flags:flags valueStrings:nil dependentParameters:dependents];
        param.value = defaultValue;
        //_kernel->setSynthParameter(p, defaultValue);
        [tree addObject:param];
    }
    
    _parameterTree = [AUParameterTree createTreeWithChildren:tree];
    
    _parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        const S1Parameter p = (S1Parameter)param.address;
        blockKernel->setSynthParameter(p, value);
    };
    _parameterTree.implementorValueProvider = ^(AUParameter *param) {
        const S1Parameter p = (S1Parameter)param.address;
        return blockKernel->getSynthParameter(p);
    };
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    _outputBusBuffer.allocateRenderResources(self.maximumFramesToRender);
    if (self.musicalContextBlock) { _musicalContext = self.musicalContextBlock; }
    // P4-5. Captured here, like the musical context, because the host only
    // guarantees these blocks are valid between allocate and deallocate.
    if (self.transportStateBlock) { _transportState = self.transportStateBlock; }
    // PORT (X1-7, ADR-071): the save / init / reset / restore sequence that stood here, tuning
    // table included (PORT FIX P4-4), is `S1DSPKernel::prepareToRender` now — statement for
    // statement — so the engine's other hosts prepare the kernel exactly as this one does.
    _kernel->prepareToRender((int)self.outputBus.format.channelCount, self.outputBus.format.sampleRate);
    
    return YES;
}

- (void)deallocateRenderResources {
    _outputBusBuffer.deallocateRenderResources();
    [super deallocateRenderResources];
    _musicalContext = nil;
    _transportState = nil;
    _kernel->destroy();
}

#pragma mark - Waveform display (P4-6)

- (BOOL)scopeEnabled {
    return _scope.enabled.load(std::memory_order_relaxed);
}

- (void)setScopeEnabled:(BOOL)scopeEnabled {
    _scope.enabled.store(scopeEnabled, std::memory_order_relaxed);
}

- (BOOL)copyScopeSamples:(float *)destination count:(NSInteger)count {
    if (count <= 0) return NO;
    return _scope.copy(destination, (uint32_t)count);
}

#pragma mark - Host MIDI (ADR-031)

- (BOOL)routesHostMIDI {
    return _kernel->hostMIDI.enabled.load(std::memory_order_relaxed);
}

- (void)setRoutesHostMIDI:(BOOL)routesHostMIDI {
    _kernel->hostMIDI.enabled.store(routesHostMIDI, std::memory_order_relaxed);
}

- (S1HostMIDISettings)hostMIDISettings {
    const S1HostMIDI &router = _kernel->hostMIDI;
    S1HostMIDISettings settings;
    settings.octaveShift       = router.octaveShift.load(std::memory_order_relaxed);
    settings.midiChannel       = router.midiChannel.load(std::memory_order_relaxed);
    settings.omniMode          = router.omniMode.load(std::memory_order_relaxed);
    settings.whiteKeysOnly     = router.whiteKeysOnly.load(std::memory_order_relaxed);
    settings.holdMode          = router.holdMode.load(std::memory_order_relaxed);
    return settings;
}

- (void)setHostMIDISettings:(S1HostMIDISettings)settings {
    // Field by field, with no attempt to make the six one atomic update: each is read
    // independently as a note arrives, exactly as the standalone reads each Swift property.
    S1HostMIDI &router = _kernel->hostMIDI;
    router.octaveShift.store(settings.octaveShift, std::memory_order_relaxed);
    router.midiChannel.store(settings.midiChannel & 0x0F, std::memory_order_relaxed);
    router.omniMode.store(settings.omniMode, std::memory_order_relaxed);
    router.whiteKeysOnly.store(settings.whiteKeysOnly, std::memory_order_relaxed);
    router.holdMode.store(settings.holdMode, std::memory_order_relaxed);
}

// Each block captures the kernel as a plain pointer and nothing Objective-C, which is what
// `performBlockOnAudioThread:` asks of a block that runs on the render thread. The kernel lives
// as long as this unit, and so does the queue that holds the block.

- (void)playKeyOnRenderThread:(uint8_t)note velocity:(uint8_t)velocity {
    S1DSPKernel *kernel = _kernel.get();
    [_messageQueue performBlockOnAudioThread:^{
        kernel->hostMIDI.keyNoteOnFromInterface(*kernel, note, velocity);
    }];
}

- (void)releaseKeyOnRenderThread:(uint8_t)note {
    S1DSPKernel *kernel = _kernel.get();
    [_messageQueue performBlockOnAudioThread:^{
        kernel->hostMIDI.keyNoteOffFromInterface(*kernel, note);
    }];
}

- (void)stopAllNotesOnRenderThread {
    S1DSPKernel *kernel = _kernel.get();
    [_messageQueue performBlockOnAudioThread:^{
        kernel->hostMIDI.allNotesOff(*kernel);
        kernel->hostMIDI.trace.record(S1HostMIDITrace::allNotesOff, 0, 0);
        kernel->stopAllNotes();
    }];
}

- (void)resetOnRenderThread {
    S1DSPKernel *kernel = _kernel.get();
    [_messageQueue performBlockOnAudioThread:^{
        kernel->reset();
    }];
}

- (void)resetDSPOnRenderThread {
    S1DSPKernel *kernel = _kernel.get();
    [_messageQueue performBlockOnAudioThread:^{
        // `resetDSP` empties the held notes and clears every voice, so the router has nothing
        // left to release — only to forget.
        kernel->hostMIDI.clear();
        kernel->resetDSP();
    }];
}

- (BOOL)hostMIDITraceEnabled {
    return _kernel->hostMIDI.trace.enabled.load(std::memory_order_relaxed);
}

- (void)setHostMIDITraceEnabled:(BOOL)hostMIDITraceEnabled {
    _kernel->hostMIDI.trace.enabled.store(hostMIDITraceEnabled, std::memory_order_relaxed);
}

- (NSInteger)takeHostMIDITrace:(uint32_t *)destination capacity:(NSInteger)capacity {
    if (destination == NULL || capacity <= 0) return 0;
    return _kernel->hostMIDI.trace.take(destination, (int)capacity);
}

// X2-7 (ADR-078): subnormals flushed to zero for one render cycle, the caller's floating-point
// environment put back afterwards. Measured 2026-09-18: CoreAudio's render thread computes
// subnormals (a 1e-20 × 1e-20 product is 1e-40 there), and the engine's effects decay into them
// and stay — the smallest one, 1.4e-45, never rounds to zero — which costs a silent instrument
// 1.15–1.5× per block on x86 and some 5% on Apple Silicon. Apple's <fenv.h> has the mode on both
// architectures. The goldens are bit-exact under it (the CTest GoldensFlushToZero). The JUCE
// plugin does the same with juce::ScopedNoDenormals.
namespace {
struct S1ScopedFlushToZero {
    fenv_t saved;
    S1ScopedFlushToZero() { fegetenv(&saved); fesetenv(FE_DFL_DISABLE_DENORMS_ENV); }
    ~S1ScopedFlushToZero() { fesetenv(&saved); }
};
}

- (AUInternalRenderBlock)internalRenderBlock {
    __block S1DSPKernel *state = _kernel.get();
    __block S1KernelAUAdapter *adapter = _kernelAdapter.get();
    // ADR-031. The queue outlives every render cycle: it belongs to this unit, as does the block.
    __unsafe_unretained AEMessageQueue *messageQueue = _messageQueue;
    return ^AUAudioUnitStatus(
                              AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        const S1ScopedFlushToZero flushToZero;
        self->_outputBusBuffer.prepareOutputBufferList(outputData, frameCount, true);
        adapter->setBuffer(outputData);

        // ADR-031: the keys the interface queued, then the router's once-a-cycle checks — both
        // before this cycle's host events, and on the thread that plays them. Polling an empty
        // queue is a lock-free read of a ring, which is all the standalone ever pays.
        AEMessageQueuePoll(messageQueue);
        if (state->hostMIDI.enabled.load(std::memory_order_relaxed)) {
            state->hostMIDI.beginRenderCycle(*state);
        }

        adapter->processWithEvents(timestamp, frameCount, realtimeEventListHead);

        // P4-6: the waveform display. `outputData` is the buffer the host is about to
        // play, so this is the same signal the standalone's node tap sees. A no-op
        // unless the plugin's interface asked for it.
        if (outputData->mNumberBuffers > 0) {
            self->_scope.push((const float *)outputData->mBuffers[0].mData, frameCount);
        }

        double currentTempo;
        if (self->_musicalContext) {
            if (self->_musicalContext( &currentTempo, NULL, NULL, NULL, NULL, NULL ) ) {
                self->_kernel->handleTempoSetting(currentTempo);
            }
        }
        // P4-5. Only the stop edge does anything — see `handleTransportState`.
        if (self->_transportState) {
            AUHostTransportStateFlags flags = 0;
            if (self->_transportState(&flags, NULL, NULL, NULL)) {
                state->handleTransportState((flags & AUHostTransportStateMoving) != 0);
            }
        }
        return noErr;
    };
}


// passthroughs for S1Protocol called by DSP on main thread
- (void)dependentParameterDidChange:(DependentParameter)param {
    [_s1Delegate dependentParameterDidChange:param];
}

- (void)arpBeatCounterDidChange:(S1ArpBeatCounter)arpBeatCounter {
    [_s1Delegate arpBeatCounterDidChange:arpBeatCounter];
}

- (void)heldNotesDidChange:(HeldNotes)heldNotes {
    [_s1Delegate heldNotesDidChange:heldNotes];
}

- (void)playingNotesDidChange:(PlayingNotes)playingNotes {
    [_s1Delegate playingNotesDidChange:playingNotes];
}

// ADR-031. Optional in the protocol: only the plugin's `Conductor` has anywhere to send them.
- (void)hostMIDIControlDidArrive:(S1HostMIDIMessage)message {
    id<S1Protocol> delegate = _s1Delegate;
    if ([delegate respondsToSelector:@selector(hostMIDIControlDidArrive:)]) {
        [delegate hostMIDIControlDidArrive:message];
    }
}

- (void)hostHeldKeysDidChange:(S1HostKeys)keys {
    id<S1Protocol> delegate = _s1Delegate;
    if ([delegate respondsToSelector:@selector(hostHeldKeysDidChange:)]) {
        [delegate hostHeldKeysDidChange:keys];
    }
}

// P4-6. The tempo reaches the DSP on the render thread; this is how it reaches the
// interface. Deliberately **not** written into the `AUParameterTree`: that would
// look like a plugin-originated parameter change, and a host in write mode would
// record `arpRate` automation the user never touched. `implementorValueProvider`
// reads the DSP, so a host that *asks* still gets the truth.
- (void)hostTempoDidChange:(float)tempo {
    if ([_s1Delegate respondsToSelector:@selector(hostTempoDidChange:)]) {
        [_s1Delegate hostTempoDidChange:tempo];
    }
}

@end
