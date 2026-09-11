//  Replacement for AudioKit's AKAudioUnit.h. Ported from AudioKit 4.9.2 (MIT).
//  S1AudioUnit subclasses this; names kept per ADR-009. See PORTING.md.
//
//  Pure Obj-C on purpose: this is a public framework header, so it must be
//  parseable by Swift. Nothing C++ may leak in here.

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AKKernelUnit
- (AUImplementorValueProvider _Null_unspecified)getter;
- (AUImplementorValueObserver _Null_unspecified)setter;
@end

@interface AKAudioUnit : AUAudioUnit<AKKernelUnit>

@property (nonatomic, strong) AUAudioUnitBus *outputBus;
@property (nonatomic, strong, nullable) AUAudioUnitBusArray *inputBusArray;
@property (nonatomic, strong, nullable) AUAudioUnitBusArray *outputBusArray;
@property (nonatomic, strong) AVAudioFormat *defaultFormat;

- (void)start;
- (void)stop;
@property (readonly) BOOL isPlaying;
@property (readonly) BOOL isSetUp;

@property double rampDuration;

/// Subclasses build their parameter tree and busses here. Called during init.
- (void)createParameters;

- (AUImplementorValueProvider _Null_unspecified)getter;
- (AUImplementorValueObserver _Null_unspecified)setter;

@end

@interface AUParameter(Ext)
+ (instancetype)parameterWithIdentifier:(NSString *)identifier
                                   name:(NSString *)name
                                address:(AUParameterAddress)address
                                    min:(AUValue)min
                                    max:(AUValue)max
                                   unit:(AudioUnitParameterUnit)unit
                                  flags:(AudioUnitParameterOptions)flags;

+ (instancetype)parameterWithIdentifier:(NSString *)identifier
                                   name:(NSString *)name
                                address:(AUParameterAddress)address
                                    min:(AUValue)min
                                    max:(AUValue)max
                                   unit:(AudioUnitParameterUnit)unit;
@end

@interface AUParameterTree(Ext)
+ (instancetype)treeWithChildren:(NSArray<AUParameter *> *)children;
@end

NS_ASSUME_NONNULL_END
