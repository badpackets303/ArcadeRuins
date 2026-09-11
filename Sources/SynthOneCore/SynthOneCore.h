//  Umbrella header for the SynthOneCore framework.
//  Only pure Obj-C headers may appear here — Swift must be able to parse it, so
//  nothing C++ can be exposed.

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double SynthOneCoreVersionNumber;
FOUNDATION_EXPORT const unsigned char SynthOneCoreVersionString[];

#import <SynthOneCore/AKAudioUnit.h>
#import <SynthOneCore/S1TestToneAudioUnit.h>

// P1-6: S1AudioUnit is the synth. It has to be in the umbrella for Swift to see
// it at all — the headless render harness, and later AKSynthOne.swift (P2-1) and
// the AUv3 view controller (P4-6). It drags in S1Parameter.h, hence AKInterop.h.
#import <SynthOneCore/S1AudioUnit.h>
