//  P1-4 proof: the smallest possible client of the ported base layer.
//
//  Structurally a rehearsal for S1AudioUnit — an AKAudioUnit subclass whose
//  kernel derives from AKSoundpipeKernel + AKOutputBuffered, driven through
//  DSPKernel::processWithEvents and a BufferedOutputBus. If this renders, the
//  sp_data lifecycle, bus setup and render-block plumbing are all correct.
//
//  Pure Obj-C header: it is public in the framework, so Swift must parse it.

#import <AVFoundation/AVFoundation.h>
// Framework-style import: public headers are flattened into
// SynthOneCore.framework/Headers, so the "AudioKit/..." path does not survive.
#import <SynthOneCore/AKAudioUnit.h>

NS_ASSUME_NONNULL_BEGIN

@interface S1TestToneAudioUnit : AKAudioUnit

/// Frequency of the test tone, Hz.
@property (nonatomic) float frequency;

/// Gate the tone on or off directly (MIDI note on/off does the same).
- (void)setGateOpen:(BOOL)open;

@end

NS_ASSUME_NONNULL_END
