//  The plugin's waveform display, from the render thread to the main thread (P4-6).
//
//  The standalone draws its waveform by tapping the engine's mixer. A plugin has no
//  node to tap — the host owns the graph — and neither allocating a buffer nor
//  dispatching a block is legal on a render thread, so the audio unit parks its output
//  in a lock-free ring (`S1Scope`) that the plot pulls from on the main thread.
//
//  These are behaviour tests, not linkage tests: each one renders real audio through
//  the host's path and asserts on the samples that come back out of the scope. The
//  interesting failure mode is a scope that reports success while handing back silence,
//  which is exactly what a flat line in Logic looks like.

import XCTest
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class PluginScopeTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512
    private let capacity = 1_024

    /// Portamento re-ramps from zero at allocation, so the synth sweeps into tune over
    /// roughly the first second (ADR-013). Render past it before believing the output.
    private let settleTime: Double = 1.0

    private func makePluginUnit() throws -> S1AudioUnit {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        unit.maximumFramesToRender = framesPerBlock
        return unit
    }

    /// Renders `seconds` of audio and returns channel 0, leaving the unit's scope
    /// holding whatever the last blocks put there.
    @discardableResult
    private func render(_ unit: S1AudioUnit, seconds: Double,
                        schedule: (Double, S1AudioUnit) -> Void = { _, _ in }) throws -> [Float] {
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let format = unit.outputBus.format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBlock) else {
            XCTFail("no render buffer"); return []
        }
        buffer.frameLength = framesPerBlock

        let renderBlock = unit.internalRenderBlock
        var out: [Float] = []
        var sampleTime: Double = 0

        while sampleTime < seconds * sampleRate {
            schedule(sampleTime / sampleRate, unit)
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid
            XCTAssertEqual(renderBlock(&flags, &timestamp, framesPerBlock, 0,
                                       buffer.mutableAudioBufferList, nil, nil), noErr)
            if let channel = buffer.floatChannelData?[0] {
                out.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(framesPerBlock)))
            }
            sampleTime += Double(framesPerBlock)
        }
        return out
    }

    /// What the plot's pull does, in the shape the plot does it.
    private func copyScope(from unit: S1AudioUnit, count: Int) -> [Float]? {
        var destination = [Float](repeating: .nan, count: max(count, 1))
        let filled = destination.withUnsafeMutableBufferPointer { buffer -> Bool in
            unit.copyScopeSamples(buffer.baseAddress!, count: count)
        }
        return filled ? Array(destination.prefix(count)) : nil
    }

    // MARK: - Tests

    /// **The one that matters.** The samples the plot draws are the samples the host
    /// played. Not "a copy succeeded" — the actual tail of the rendered signal.
    func testScopeCarriesTheRenderedOutputToTheMainThread() throws {
        let unit = try makePluginUnit()
        unit.scopeEnabled = true

        var started = false
        let signal = try render(unit, seconds: settleTime + 0.5) { time, unit in
            guard !started, time >= settleTime else { return }
            started = true
            unit.startNote(69, velocity: 127)
        }
        XCTAssertGreaterThan(signal.count, capacity, "not enough audio rendered to fill the scope")

        let scope = try XCTUnwrap(copyScope(from: unit, count: capacity),
                                  "the scope refused to hand back a snapshot")
        XCTAssertEqual(scope, Array(signal.suffix(capacity)),
                       "the scope is not showing what was rendered")

        // And it is a waveform, not a flat line — the failure the user would actually
        // see. An all-zero snapshot would satisfy the equality above if the render had
        // gone silent, so this pins the signal down separately.
        XCTAssertGreaterThan(scope.map(abs).max() ?? 0, 0.01,
                             "the scope filled with silence while a note was sounding")
    }

    /// Off by default, and it stays off until someone asks. The standalone taps a node
    /// and must never pay for this.
    func testScopeIsOffByDefault() throws {
        let unit = try makePluginUnit()
        XCTAssertFalse(unit.scopeEnabled)
        XCTAssertNil(copyScope(from: unit, count: capacity),
                     "a scope that was never enabled handed back a snapshot")
    }

    /// The flag is honoured on the **render** thread, not just at the copy. If `push`
    /// ignored it, this would come back full of audio.
    func testARenderWithTheScopeOffLeavesNothingBehind() throws {
        let unit = try makePluginUnit()
        var started = false
        let signal = try render(unit, seconds: settleTime + 0.5) { time, unit in
            guard !started, time >= settleTime else { return }
            started = true
            unit.startNote(69, velocity: 127)
        }
        XCTAssertGreaterThan(Signal.peak(signal), 0.05, "the test rendered no audio to speak of")

        unit.scopeEnabled = true
        let scope = try XCTUnwrap(copyScope(from: unit, count: capacity))
        XCTAssertEqual(scope.map(abs).max() ?? 0, 0,
                       "the render thread wrote to the scope while it was disabled")
    }

    /// A refusal, not a buffer overrun. `count` comes from the plot's `bufferSize`,
    /// which is a public property anyone can set.
    func testScopeRefusesACountItCannotSatisfy() throws {
        let unit = try makePluginUnit()
        unit.scopeEnabled = true
        try render(unit, seconds: 0.1)

        XCTAssertNil(copyScope(from: unit, count: capacity + 1))
        XCTAssertNil(copyScope(from: unit, count: 0))
        XCTAssertNil(copyScope(from: unit, count: -1))
        XCTAssertNotNil(copyScope(from: unit, count: capacity), "the boundary itself must work")
    }

    /// A shorter window is the newest samples, not the oldest — the plot asks for
    /// whatever fits its width, and a scope that handed back stale audio would look
    /// like a waveform frozen a second in the past.
    func testAShorterWindowIsTheMostRecentSamples() throws {
        let unit = try makePluginUnit()
        unit.scopeEnabled = true

        var started = false
        let signal = try render(unit, seconds: settleTime + 0.5) { time, unit in
            guard !started, time >= settleTime else { return }
            started = true
            unit.startNote(69, velocity: 127)
        }

        let window = 256
        let scope = try XCTUnwrap(copyScope(from: unit, count: window))
        XCTAssertEqual(scope, Array(signal.suffix(window)))
    }
}
