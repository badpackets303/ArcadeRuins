//
//  S1AudioUnit.h
//  AudioKit
//
//  Created by AudioKit Contributors, revision history on Github.
//  Join us at AudioKitPro.com, github.com/audiokit
//

// PORT FIX (P1-6): framework-style imports + a named include guard, for the
// reasons spelled out at the top of S1Parameter.h. This header is public so that
// Swift can see S1AudioUnit; public headers are flattened into Headers/, which
// is why neither "AudioKit/..." nor a sibling-relative quote works here.
#ifndef S1_AUDIO_UNIT_H
#define S1_AUDIO_UNIT_H

#import <SynthOneCore/AKAudioUnit.h>
#import <SynthOneCore/S1Parameter.h>

#import <SynthOneCore/S1EngineTypes.h>

@class AEMessageQueue;

@protocol S1Protocol <NSObject>

-(void)dependentParameterDidChange:(DependentParameter)dependentParam;

-(void)arpBeatCounterDidChange:(S1ArpBeatCounter)arpBeatCounter;

-(void)heldNotesDidChange:(HeldNotes)heldNotes;

-(void)playingNotesDidChange:(PlayingNotes)playingNotes;

@optional

/// The host's tempo changed (P4-6). Optional because only the plugin's `Conductor`
/// has a tempo control to update — the standalone has no host.
-(void)hostTempoDidChange:(float)tempo;

/// A control change or program change from the host (ADR-031). Plugin only.
-(void)hostMIDIControlDidArrive:(S1HostMIDIMessage)message;

/// Host MIDI is holding a different set of keys (ADR-031). Plugin only.
-(void)hostHeldKeysDidChange:(S1HostKeys)keys;

@end

@class S1AudioUnit;

/// The object the render thread addresses its main-thread messages to (P4-5 fix).
///
/// **Why this exists.** `AEMessageQueuePerformSelectorOnMainThread` stores its target
/// as a **raw pointer** in a lock-free ring buffer — retaining on the render thread
/// is not real-time safe — and `AEMainThreadEndpoint` then `dispatch_async`es the
/// delivery. If the addressed object dies in between, the handler does `objc_retain`
/// on freed memory and the process segfaults. Upstream never met this: one synth,
/// alive for the life of the app. A host creates and destroys instances, and so does
/// every test that renders.
///
/// So the render thread addresses a relay that is **deliberately never deallocated**,
/// and the relay holds a *weak* reference to the audio unit. A message that arrives
/// after its unit has gone finds `unit == nil` and does nothing. One of these leaks
/// per audio-unit instance — a few dozen bytes against a use-after-free.
@interface S1MessageRelay : NSObject <S1Protocol>
@property (nonatomic, weak) S1AudioUnit *unit;
@end

/// Supplies the shipped banks as AU factory presets (P4-4).
///
/// Implemented in Swift by `S1FactoryPresets`. This audio unit is Obj-C++ and the
/// preset codec is Swift, so the two meet at a protocol rather than by one
/// importing the other — importing `SynthOneCore-Swift.h` from here is exactly what
/// ADR-014 rules out.
@protocol S1FactoryPresetSource <NSObject>
- (NSArray<NSString *> *)factoryPresetNames;
- (BOOL)applyFactoryPresetAt:(NSInteger)index to:(S1AudioUnit *)unit;
@end

@interface S1AudioUnit : AKAudioUnit
{
    @public
    AEMessageQueue  *_messageQueue;
}

@property (nonatomic) NSArray *parameters;
@property (nonatomic, weak) id<S1Protocol> s1Delegate;

/// Install with `S1FactoryPresets.install(into:)`. Without it the unit reports no
/// factory presets, which is a legitimate thing for an AU to do — so the absence is
/// quiet, and `AudioUnitPresetTests` asserts the plugin's factory installs one.
@property (nonatomic, strong, nullable) id<S1FactoryPresetSource> factoryPresetSource;

/// The relay the DSP posts through. Never nil, never deallocated — see `S1MessageRelay`.
@property (nonatomic, readonly) S1MessageRelay *messageRelay;

#pragma mark - Waveform display (P4-6)

/// How many samples the scope keeps — one screenful for the Generators panel's plot,
/// and about 23 ms at 44.1 kHz.
#define S1_SCOPE_CAPACITY (1024)

/// Whether the render thread should keep a copy of its output for the waveform display.
///
/// **Off by default, and it must stay that way.** The standalone draws its waveform by
/// tapping the engine's mixer and never touches this; only the plugin, which has no node
/// to tap, turns it on. While it is off the render thread does one relaxed atomic load
/// per cycle and nothing else.
@property (nonatomic) BOOL scopeEnabled;

/// Copies the most recent `count` output samples, oldest first, into `destination`.
///
/// Main thread. Returns `NO` — leaving `destination` untouched — when the scope is off,
/// when `count` exceeds `S1_SCOPE_CAPACITY`, or when the render thread was mid-write on
/// every attempt. A dropped frame of a decorative waveform is the right outcome; making
/// either side wait for the other is not.
- (BOOL)copyScopeSamples:(float *)destination count:(NSInteger)count;

#pragma mark - Host MIDI (ADR-031)

/// Whether MIDI arriving in the render block goes through `S1HostMIDI` — the plugin's port of
/// the standalone's MIDI chain — rather than upstream's bare note on and off.
///
/// **Off by default.** The standalone has no host and never turns it on. The plugin's factory,
/// `SynthOneApp.makePluginAudioUnit`, turns it on before the host sees the unit.
@property (nonatomic) BOOL routesHostMIDI;

/// The interface's MIDI settings. Written by `Manager.syncHostMIDISettings()` on the main
/// thread; the render thread reads them without a lock.
@property (nonatomic) S1HostMIDISettings hostMIDISettings;

/// An on-screen or typed key, played on the render thread.
///
/// Host notes are handled on the render thread, and the kernel's `startNote` and `stopNote`
/// mutate an `NSMutableArray` that upstream documents as not for the render thread. A key
/// played from the main thread would race them. So the interface's keys are queued, and applied
/// at the start of the next render cycle on the same thread as host notes. A key sounds within
/// one buffer — and not at all while the host is not rendering, like everything else a plugin
/// does.
- (void)playKeyOnRenderThread:(uint8_t)note velocity:(uint8_t)velocity
    NS_SWIFT_NAME(playKeyOnRenderThread(_:velocity:));
- (void)releaseKeyOnRenderThread:(uint8_t)note
    NS_SWIFT_NAME(releaseKeyOnRenderThread(_:));

/// `stopAllNotes`, `reset` and `resetDSP`, queued the same way for the same reason.
/// `stopAllNotes` also releases the keys host MIDI is holding, as `Manager.stopAllNotes` does
/// in the standalone through `KeyboardView.allNotesOff`.
- (void)stopAllNotesOnRenderThread;
- (void)resetOnRenderThread;
- (void)resetDSPOnRenderThread;

/// Tests only: record what the router and the queued keys did (`S1HostMIDITrace`).
@property (nonatomic) BOOL hostMIDITraceEnabled;

/// Copies and consumes the trace, oldest first, as `[op:8][note:8][value:16]`. Returns the count.
- (NSInteger)takeHostMIDITrace:(uint32_t *)destination capacity:(NSInteger)capacity
    NS_SWIFT_NAME(takeHostMIDITrace(_:capacity:));


- (float)getSynthParameter:(S1Parameter)param;
- (void)setSynthParameter:(S1Parameter)param value:(float)value;
- (float)getDependentParameter:(S1Parameter)param;
- (void)setDependentParameter:(S1Parameter)param value:(float)value payload:(int)payload;

- (float)getMinimum:(S1Parameter)param;
- (float)getMaximum:(S1Parameter)param;
- (float)getDefault:(S1Parameter)param;

- (void)setupWaveform:(UInt32)tableIndex size:(int)size;
- (void)setWaveform:(UInt32)tableIndex withValue:(float)value atIndex:(UInt32)sampleIndex;
- (void)setBandlimitFrequency:(UInt32)blIndex withFrequency:(float)frequency;

- (void)stopNote:(uint8_t)note;
- (void)startNote:(uint8_t)note velocity:(uint8_t)velocity;
- (void)startNote:(uint8_t)note velocity:(uint8_t)velocity frequency:(float)frequency;

- (void)reset;
- (void)stopAllNotes;
- (void)resetDSP;
- (void)resetSequencer;

// S1TuningTable protocol
- (void)setTuningTable:(float)frequency index:(int)index;
- (float)getTuningTableFrequency:(int)index;
- (void)setTuningTableNPO:(int)npo;
- (int)getTuningTableNPO;

///auv3, not yet used
- (void)setParameter:(AUParameterAddress)address value:(AUValue)value;
- (AUValue)getParameter:(AUParameterAddress)address;
- (void)createParameters;

// protected passthroughs for S1Protocol called by DSP on main thread
- (void)dependentParameterDidChange:(DependentParameter)param;
- (void)arpBeatCounterDidChange:(S1ArpBeatCounter)arpBeatcounter;
- (void)heldNotesDidChange:(HeldNotes)heldNotes;
- (void)playingNotesDidChange:(PlayingNotes)playingNotes;
- (void)hostTempoDidChange:(float)tempo;
- (void)hostMIDIControlDidArrive:(S1HostMIDIMessage)message;
- (void)hostHeldKeysDidChange:(S1HostKeys)keys;

@end

#endif /* S1_AUDIO_UNIT_H */
