//  P0-4 spike: minimal AUv3 instrument.
//  Monophonic sine, one parameter, MIDI note on/off. Enough for auval to exercise
//  render, parameters, MIDI and state — nothing more.

import AVFoundation
import AudioToolbox
import CoreAudio
import CoreAudioKit

/// Render-thread state. Held in raw memory so the render block captures a pointer
/// rather than a Swift object — no ARC traffic on the audio thread.
private struct SineState {
    var phase: Double = 0
    var phaseIncrement: Double = 0
    var sampleRate: Double = 44_100
    var amplitude: Double = 0        // smoothed
    var targetAmplitude: Double = 0  // gate
    var gain: Double = 0.5
    var noteActive: Bool = false
}

public final class SpikeAudioUnit: AUAudioUnit {

    public enum ParameterAddress: AUParameterAddress {
        case gain = 0
        /// P0-4 evidence channel: the view controller sets this to 1.0 once the
        /// storyboard has actually loaded inside the extension process.
        case storyboardLoaded = 1
        /// P0-4 evidence channel: 1.0 if the extension could write to the App Group container.
        case appGroupWritable = 2
    }

    private var state: UnsafeMutablePointer<SineState>
    private let outputBus: AUAudioUnitBus
    private var _outputBusArray: AUAudioUnitBusArray!
    private var _inputBusArray: AUAudioUnitBusArray!
    private var _parameterTree: AUParameterTree!

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {

        state = UnsafeMutablePointer<SineState>.allocate(capacity: 1)
        state.initialize(to: SineState())

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
            state.deinitialize(count: 1)
            state.deallocate()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
        }
        outputBus = try AUAudioUnitBus(format: format)
        outputBus.maximumChannelCount = 2

        try super.init(componentDescription: componentDescription, options: options)

        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        // An instrument has no inputs, but the array must exist and be empty.
        _inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])

        let gainParam = AUParameterTree.createParameter(
            withIdentifier: "gain",
            name: "Gain",
            address: ParameterAddress.gain.rawValue,
            min: 0.0, max: 1.0, unit: .linearGain, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil, dependentParameters: nil)
        gainParam.value = 0.5

        let sbParam = AUParameterTree.createParameter(
            withIdentifier: "storyboardLoaded",
            name: "Storyboard Loaded",
            address: ParameterAddress.storyboardLoaded.rawValue,
            min: 0.0, max: 1.0, unit: .boolean, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil)
        sbParam.value = 0

        let agParam = AUParameterTree.createParameter(
            withIdentifier: "appGroupWritable",
            name: "App Group Writable",
            address: ParameterAddress.appGroupWritable.rawValue,
            min: 0.0, max: 1.0, unit: .boolean, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil)
        agParam.value = 0

        _parameterTree = AUParameterTree.createTree(withChildren: [gainParam, sbParam, agParam])
        var storyboardFlag: Float = 0
        var appGroupFlag: Float = 0

        let statePtr = state
        _parameterTree.implementorValueObserver = { param, value in
            if param.address == ParameterAddress.gain.rawValue {
                statePtr.pointee.gain = Double(value)
            } else if param.address == ParameterAddress.storyboardLoaded.rawValue {
                storyboardFlag = value
            } else if param.address == ParameterAddress.appGroupWritable.rawValue {
                appGroupFlag = value
            }
        }
        _parameterTree.implementorValueProvider = { param in
            if param.address == ParameterAddress.gain.rawValue {
                return AUValue(statePtr.pointee.gain)
            } else if param.address == ParameterAddress.storyboardLoaded.rawValue {
                return storyboardFlag
            } else if param.address == ParameterAddress.appGroupWritable.rawValue {
                return appGroupFlag
            }
            return 0
        }
        _parameterTree.implementorStringFromValueCallback = { param, valuePtr in
            let value = valuePtr?.pointee ?? param.value
            return String(format: "%.2f", value)
        }

        maximumFramesToRender = 512
    }

    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }
    public override var inputBusses: AUAudioUnitBusArray { _inputBusArray }
    public override var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set { /* read-only tree */ }
    }

    public override var channelCapabilities: [NSNumber]? { [0, 2] }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        state.pointee.sampleRate = outputBus.format.sampleRate
        state.pointee.phase = 0
        state.pointee.amplitude = 0
        state.pointee.targetAmplitude = 0
        state.pointee.noteActive = false
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let statePtr = state

        return { _, _, frameCount, _, outputBusList, realtimeEventListHead, _ in

            // --- MIDI ---
            var event = realtimeEventListHead
            while let e = event {
                if e.pointee.head.eventType == .MIDI {
                    let midi = e.pointee.MIDI
                    let status = midi.data.0 & 0xF0
                    let note = midi.data.1
                    let velocity = midi.data.2

                    if status == 0x90 && velocity > 0 {
                        let freq = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
                        statePtr.pointee.phaseIncrement = 2.0 * Double.pi * freq / statePtr.pointee.sampleRate
                        statePtr.pointee.targetAmplitude = Double(velocity) / 127.0
                        statePtr.pointee.noteActive = true
                    } else if status == 0x80 || (status == 0x90 && velocity == 0) {
                        statePtr.pointee.targetAmplitude = 0
                        statePtr.pointee.noteActive = false
                    } else if status == 0xB0 && (note == 123 || note == 120) {
                        statePtr.pointee.targetAmplitude = 0
                        statePtr.pointee.noteActive = false
                    }
                }
                event = UnsafePointer(e.pointee.head.next)
            }

            // --- Render ---
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputBusList)
            for buffer in ablPointer {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }

            let gain = statePtr.pointee.gain
            var phase = statePtr.pointee.phase
            var amp = statePtr.pointee.amplitude
            let target = statePtr.pointee.targetAmplitude
            let inc = statePtr.pointee.phaseIncrement
            let smoothing = 0.001

            for frame in 0..<Int(frameCount) {
                amp += (target - amp) * smoothing
                let sample = Float(sin(phase) * amp * gain)
                phase += inc
                if phase > 2.0 * Double.pi { phase -= 2.0 * Double.pi }

                for buffer in ablPointer {
                    let out = buffer.mData!.assumingMemoryBound(to: Float.self)
                    out[frame] = sample
                }
            }

            statePtr.pointee.phase = phase
            statePtr.pointee.amplitude = amp

            return noErr
        }
    }
}
