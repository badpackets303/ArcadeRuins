#import "AudioKit/S1TestToneAudioUnit.h"
#import "AudioKit/AKSoundpipeKernel.hpp"
#import "AudioKit/BufferedAudioBus.hpp"
#import "AKSettingsBridge.h"

// A minimal kernel shaped like S1DSPKernel: Soundpipe state owned by the base,
// output written through AKOutputBuffered, events delivered by DSPKernel.
class S1TestToneKernel : public AKSoundpipeKernel, public AKOutputBuffered {
public:
    S1TestToneKernel(int channelCount, double sampleRate)
        : AKSoundpipeKernel(channelCount, sampleRate) {
        createDSP();
    }

    ~S1TestToneKernel() {
        destroyDSP();
    }

    void init(int channelCount, double sampleRate) override {
        destroyDSP();
        AKSoundpipeKernel::init(channelCount, sampleRate);
        createDSP();
    }

    void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) override {
        // No ramping in the test tone.
    }

    void handleMIDIEvent(AUMIDIEvent const& midiEvent) override {
        if (midiEvent.length < 3) { return; }
        uint8_t status = midiEvent.data[0] & 0xF0;
        uint8_t note = midiEvent.data[1];
        uint8_t velocity = midiEvent.data[2];

        if (status == 0x90 && velocity > 0) {
            frequency = (float)noteToHz(note);
            if (osc) { osc->freq = frequency; }
            gate = 1.f;
        } else if (status == 0x80 || (status == 0x90 && velocity == 0)) {
            gate = 0.f;
        }
    }

    void process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) override {
        if (outBufferListPtr == nullptr || osc == nullptr) { return; }

        for (AUAudioFrameCount i = 0; i < frameCount; ++i) {
            float sample = 0.f;
            sp_osc_compute(sp, osc, nullptr, &sample);
            sample *= gate;

            for (UInt32 channel = 0; channel < outBufferListPtr->mNumberBuffers; ++channel) {
                float *out = (float *)outBufferListPtr->mBuffers[channel].mData;
                if (out) { out[bufferOffset + i] = sample; }
            }
        }
    }

    void setFrequency(float hz) {
        frequency = hz;
        if (osc) { osc->freq = hz; }
    }

    float getFrequency() const { return frequency; }
    void setGate(float g) { gate = g; }

private:
    void createDSP() {
        sp_ftbl_create(sp, &ftbl, 4096);
        sp_gen_sine(sp, ftbl);
        sp_osc_create(&osc);
        sp_osc_init(sp, osc, ftbl, 0);
        osc->freq = frequency;
        osc->amp = 1.f;
    }

    void destroyDSP() {
        if (osc)  { sp_osc_destroy(&osc);   osc = nullptr; }
        if (ftbl) { sp_ftbl_destroy(&ftbl); ftbl = nullptr; }
    }

    sp_osc *osc = nullptr;
    sp_ftbl *ftbl = nullptr;
    float frequency = 440.f;
    float gate = 0.f;
};

@implementation S1TestToneAudioUnit {
    std::unique_ptr<S1TestToneKernel> _kernel;
    BufferedOutputBus _outputBusBuffer;
}

@synthesize parameterTree = _parameterTree;

- (void)createParameters {
    self.rampDuration = ak_settings_ramp_duration();
    self.defaultFormat = [[AVAudioFormat alloc]
                          initStandardFormatWithSampleRate:ak_settings_sample_rate()
                                                  channels:ak_settings_channel_count()];

    _kernel = std::make_unique<S1TestToneKernel>(self.defaultFormat.channelCount,
                                                 self.defaultFormat.sampleRate);

    _outputBusBuffer.init(self.defaultFormat, 2);
    self.outputBus = _outputBusBuffer.bus;
    self.outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                                 busType:AUAudioUnitBusTypeOutput
                                                                  busses:@[self.outputBus]];
}

- (float)frequency {
    return _kernel ? _kernel->getFrequency() : 0.f;
}

- (void)setFrequency:(float)frequency {
    if (_kernel) { _kernel->setFrequency(frequency); }
}

- (void)setGateOpen:(BOOL)open {
    if (_kernel) { _kernel->setGate(open ? 1.f : 0.f); }
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    _outputBusBuffer.allocateRenderResources(self.maximumFramesToRender);
    _kernel->init(self.outputBus.format.channelCount, self.outputBus.format.sampleRate);
    return YES;
}

- (void)deallocateRenderResources {
    _outputBusBuffer.deallocateRenderResources();
    [super deallocateRenderResources];
}

- (AUInternalRenderBlock)internalRenderBlock {
    __block S1TestToneKernel *state = _kernel.get();
    __block BufferedOutputBus *outputBuffer = &_outputBusBuffer;
    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        outputBuffer->prepareOutputBufferList(outputData, frameCount, true);
        state->setBuffer(outputData);
        state->processWithEvents(timestamp, frameCount, realtimeEventListHead);
        return noErr;
    };
}

@end
