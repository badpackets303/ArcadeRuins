//  P1-4 acceptance: the ported AudioKit base layer actually renders.
//
//  S1TestToneAudioUnit is shaped exactly like S1AudioUnit will be — an
//  AKAudioUnit subclass whose kernel derives from AKSoundpipeKernel +
//  AKOutputBuffered and runs through DSPKernel::processWithEvents. Driving it
//  end to end exercises the sp_data lifecycle, BufferedOutputBus, bus setup and
//  the render block, which is everything P1-5 depends on.

import XCTest
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class AudioUnitBaseTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512

    private func makeUnit() throws -> S1TestToneAudioUnit {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x74_73_74_31,   // 'tst1'
            componentManufacturer: 0x42_50_30_33, // 'BP03'
            componentFlags: 0, componentFlagsMask: 0)
        let unit = try S1TestToneAudioUnit(componentDescription: desc, options: [])
        unit.maximumFramesToRender = framesPerBlock
        return unit
    }

    /// Renders `blocks` buffers and returns the left channel.
    private func render(_ unit: S1TestToneAudioUnit, blocks: Int) throws -> [Float] {
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let format = unit.outputBus.format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBlock) else {
            XCTFail("could not allocate render buffer"); return []
        }
        buffer.frameLength = framesPerBlock

        let renderBlock = unit.internalRenderBlock
        var collected: [Float] = []
        var sampleTime: Double = 0

        for _ in 0..<blocks {
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid

            let status = renderBlock(&flags, &timestamp, framesPerBlock, 0,
                                     buffer.mutableAudioBufferList, nil, nil)
            XCTAssertEqual(status, noErr)

            if let channel = buffer.floatChannelData?[0] {
                collected.append(contentsOf: UnsafeBufferPointer(start: channel,
                                                                 count: Int(framesPerBlock)))
            }
            sampleTime += Double(framesPerBlock)
        }
        return collected
    }

    private func estimateFrequency(_ signal: [Float]) -> Double {
        var crossings = 0
        for i in 1..<signal.count where signal[i - 1] <= 0 && signal[i] > 0 { crossings += 1 }
        return Double(crossings) * sampleRate / Double(signal.count)
    }

    private func peak(_ signal: [Float]) -> Float {
        signal.reduce(0) { max($0, abs($1)) }
    }

    // MARK: - Tests

    func testUnitInstantiatesAndBuildsOutputBus() throws {
        let unit = try makeUnit()
        XCTAssertNotNil(unit.outputBus)
        XCTAssertEqual(unit.outputBus.format.channelCount, 2)
        XCTAssertEqual(unit.outputBus.format.sampleRate, sampleRate)
        XCTAssertEqual(unit.outputBusses.count, 1, "AKAudioUnit must vend the subclass's bus array")
    }

    /// Gate closed: the render block must produce digital silence, and
    /// BufferedOutputBus must have zero-filled the buffer.
    func testSilentWhenGateClosed() throws {
        let unit = try makeUnit()
        unit.setGateOpen(false)
        let signal = try render(unit, blocks: 4)
        XCTAssertFalse(signal.isEmpty)
        XCTAssertEqual(peak(signal), 0, accuracy: 0.000_01)
    }

    /// The whole stack: sp_data created by AKSoundpipeKernel, samples written
    /// through AKOutputBuffered, dispatched by DSPKernel::processWithEvents.
    func testRendersToneAtRequestedFrequency() throws {
        let unit = try makeUnit()
        unit.frequency = 440
        unit.setGateOpen(true)

        let signal = try render(unit, blocks: 86)   // ~1 second
        XCTAssertGreaterThan(signal.count, 40_000)
        XCTAssertGreaterThan(peak(signal), 0.5, "tone should be audible")
        XCTAssertEqual(estimateFrequency(signal), 440, accuracy: 3.0)
    }

    func testFrequencyIsSettable() throws {
        let unit = try makeUnit()
        unit.frequency = 220
        unit.setGateOpen(true)
        let signal = try render(unit, blocks: 86)
        XCTAssertEqual(estimateFrequency(signal), 220, accuracy: 3.0)
    }

    /// Reallocating render resources re-runs kernel init(), which tears down and
    /// rebuilds the Soundpipe state. It must not leak or crash, and must still play.
    func testSurvivesReallocationOfRenderResources() throws {
        let unit = try makeUnit()
        unit.frequency = 330
        unit.setGateOpen(true)

        for _ in 0..<3 {
            let signal = try render(unit, blocks: 43)
            XCTAssertGreaterThan(peak(signal), 0.5)
            XCTAssertEqual(estimateFrequency(signal), 330, accuracy: 4.0)
        }
    }

    /// Regression test for the AKDSPKernel PORT FIX: upstream's init() had
    /// `sampleRate = sampleRate`, a self-assignment, so the member never updated.
    func testKernelInitUpdatesSampleRate() throws {
        let unit = try makeUnit()
        unit.setGateOpen(true)
        // 44.1 kHz bus; a 440 Hz tone must measure 440 Hz. If the kernel kept a
        // stale sample rate, sp->sr and the measured pitch would disagree.
        unit.frequency = 440
        let signal = try render(unit, blocks: 86)
        XCTAssertEqual(estimateFrequency(signal), 440, accuracy: 3.0)
    }
}
