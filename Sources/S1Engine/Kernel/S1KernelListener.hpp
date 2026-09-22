//
//  S1KernelListener.hpp
//  Arcade Ruins
//
//  PORT (X1-2, ADR-066): what the kernel tells the outside world, as plain C++.
//
//  Upstream the kernel posted these itself, straight from the render thread, with
//  `AEMessageQueuePerformSelectorOnMainThread(audioUnit->_messageQueue, audioUnit.messageRelay, …)`.
//  The kernel now calls a listener and knows nothing about queues, selectors or the audio unit;
//  `S1AudioUnit` implements the listener and does exactly what the kernel used to do
//  (`S1AudioUnitKernelListener` in S1AudioUnit.mm). The JUCE build will implement it its own way.
//
//  Every method may be called from the render thread. An implementation must not allocate,
//  lock or block.
//

#ifndef S1_KERNEL_LISTENER_HPP
#define S1_KERNEL_LISTENER_HPP

#include "S1EngineTypes.h"   // the message structs

struct S1KernelListener {
    virtual ~S1KernelListener() = default;

    /// P4-6. The host's tempo, on its way to the tempo control.
    virtual void hostTempoDidChange(float tempo) = 0;
    /// lfo1Rate, lfo2Rate, autoPanRate, delayTime or arpSeqTempoMultiplier was re-derived.
    virtual void dependentParameterDidChange(const DependentParameter &parameter) = 0;
    virtual void arpBeatCounterDidChange(const S1ArpBeatCounter &counter) = 0;
    virtual void playingNotesDidChange(const PlayingNotes &notes) = 0;
    virtual void heldNotesDidChange(const HeldNotes &notes) = 0;
    /// ADR-031, plugin only: a control or program change from the host.
    virtual void hostMIDIControlDidArrive(const S1HostMIDIMessage &message) = 0;
    /// ADR-031, plugin only. Returns false if the message could not be queued, so the caller
    /// tries again next render cycle.
    virtual bool hostHeldKeysDidChange(const S1HostKeys &keys) = 0;
};

#endif
