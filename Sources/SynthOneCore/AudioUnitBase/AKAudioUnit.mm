//  Replacement for AudioKit's AKAudioUnit.mm. Ported from AudioKit 4.9.2 (MIT).
//  See PORTING.md.

#import "AudioKit/AKAudioUnit.h"
#import <AVFoundation/AVFoundation.h>

// PORT CHANGE: upstream reads AKSettings.sampleRate / .channelCount through
// <AudioKit/AudioKit-Swift.h>. Our AKSettings is Swift in a *static library*, so
// it has no Obj-C interface header to import here. The three scalars the DSP
// layer needs are backed by C storage instead, which both languages front
// (ADR-010).
#import "AKSettingsBridge.h"

@implementation AKAudioUnit {
    AUAudioUnitBusArray *_outputBusArray;
}

@synthesize parameterTree = _parameterTree;
@synthesize rampDuration = _rampDuration;

- (void)start {}
- (void)stop {}
- (BOOL)isPlaying { return NO; }
- (BOOL)isSetUp { return NO; }

- (double)rampDuration {
    return _rampDuration;
}

- (void)setRampDuration:(double)rampDuration {
    if (_rampDuration == rampDuration) { return; }
    _rampDuration = rampDuration;
    [self setUpParameterRamp];
}

- (void)createParameters {}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) {
        return nil;
    }

    self.defaultFormat = [[AVAudioFormat alloc]
                          initStandardFormatWithSampleRate:ak_settings_sample_rate()
                                                  channels:ak_settings_channel_count()];

    // Subclasses build their parameter tree and busses here.
    [self createParameters];

    // Only create a default output bus if the subclass did not make its own.
    if (self.outputBus == nil) {
        self.outputBus = [[AUAudioUnitBus alloc] initWithFormat:self.defaultFormat error:nil];
    }
    if (self.outputBusArray == nil) {
        _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                                 busType:AUAudioUnitBusTypeOutput
                                                                  busses:@[self.outputBus]];
    } else {
        _outputBusArray = self.outputBusArray;
    }

    return self;
}

#pragma mark - AUAudioUnit Overrides

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

- (AUImplementorValueProvider)getter {
    return _parameterTree.implementorValueProvider;
}

- (AUImplementorValueObserver)setter {
    return _parameterTree.implementorValueObserver;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    [self setUpParameterRamp];
    return YES;
}

/*
    While rendering we want parameter changes scheduled, not applied directly —
    setting them off the render thread is not thread safe.

    NOTE: this REPLACES whatever implementorValueObserver a subclass installed in
    createParameters, and it runs on every allocateRenderResources. That is
    upstream's behaviour and is preserved deliberately; it matters at P4-3 when
    the real 150-parameter tree is wired up.
 */
- (void)setUpParameterRamp {
    if (self.parameterTree == nil) { return; }

    __block AUScheduleParameterBlock scheduleParameter = self.scheduleParameterBlock;
    if (scheduleParameter == nil) { return; }

    __block AUAudioFrameCount rampDuration = AUAudioFrameCount(_rampDuration * self.outputBus.format.sampleRate);

    self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        scheduleParameter(AUEventSampleTimeImmediate, rampDuration, param.address, value);
    };
}

@end

@implementation AUParameter(Ext)

+ (instancetype)parameterWithIdentifier:(NSString *)identifier
                                   name:(NSString *)name
                                address:(AUParameterAddress)address
                                    min:(AUValue)min
                                    max:(AUValue)max
                                   unit:(AudioUnitParameterUnit)unit
                                  flags:(AudioUnitParameterOptions)flags {
    return [AUParameterTree createParameterWithIdentifier:identifier
                                                     name:name
                                                  address:address
                                                      min:min
                                                      max:max
                                                     unit:unit
                                                 unitName:nil
                                                    flags:flags
                                             valueStrings:nil
                                      dependentParameters:nil];
}

+ (instancetype)parameterWithIdentifier:(NSString *)identifier
                                   name:(NSString *)name
                                address:(AUParameterAddress)address
                                    min:(AUValue)min
                                    max:(AUValue)max
                                   unit:(AudioUnitParameterUnit)unit {
    return [AUParameter parameterWithIdentifier:identifier
                                           name:name
                                        address:address
                                            min:min
                                            max:max
                                           unit:unit
                                          flags:0];
}

@end

@implementation AUParameterTree(Ext)

+ (instancetype)treeWithChildren:(NSArray<AUParameter *> *)children {
    AUParameterTree *tree = [AUParameterTree createTreeWithChildren:children];
    if (tree == nil) {
        return nil;
    }
    tree.implementorStringFromValueCallback = ^(AUParameter *param, const AUValue *__nullable valuePtr) {
        AUValue value = valuePtr == nil ? param.value : *valuePtr;
        return [NSString stringWithFormat:@"%.3f", value];
    };
    return tree;
}

@end
