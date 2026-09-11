//  P1-6 acceptance: the first sound Synth One has made on macOS.
//
//  Everything before this proved the port *compiles and links*. ADR-011 is the
//  standing reminder that neither is evidence of anything audible: a Soundpipe
//  fork with the right symbol names and the wrong semantics would have got this
//  far and then aliased. So these tests drive S1AudioUnit exactly as the app
//  will — createParameters, wavetables, allocateRenderResources, note on —
//  render offline through internalRenderBlock, and *measure* the result.
//
//  No AVAudioEngine, no UI, no host. Just the audio unit.

import XCTest
import Accelerate
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class S1AudioUnitRenderTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512

    // MARK: - Building the synth

    /// The shipping AudioComponentDescription (project.yml: aumu / ruin / BP03).
    private var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x72_75_69_6E,      // 'ruin'
            componentManufacturer: 0x42_50_30_33, // 'BP03'
            componentFlags: 0, componentFlagsMask: 0)
    }

    /// Decoding 52 4,096-point wavetables is the slow part of building a synth,
    /// so it happens once for the whole test run.
    private struct Wavetables {
        let tables: [AKTable]
        let bandlimitFrequencies: [Float]
    }

    private static let wavetables: Result<Wavetables, Error> = Result {
        // Framework resources, not app resources: upstream read these from
        // Bundle.main in AKSynthOne.swift, which is not where they live for us.
        let bundle = Bundle(for: S1AudioUnit.self)
        let decoder = JSONDecoder()

        func url(_ name: String) throws -> URL {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile,
                                 userInfo: [NSFilePathErrorKey: "\(name).json in SynthOneCore"])
            }
            return url
        }

        let names = try decoder.decode([String].self,
                                       from: Data(contentsOf: url("bandlimitedWaveforms")))
        let frequencies = try decoder.decode(AKTable.self,
                                             from: Data(contentsOf: url("bandlimitedWaveformFrequencies")))
        let tables = try names.map {
            try decoder.decode(AKTable.self, from: Data(contentsOf: url($0)))
        }
        return Wavetables(tables: tables, bandlimitFrequencies: Array(frequencies))
    }

    /// A synth with its oscillator wavetables loaded, ready for
    /// `allocateRenderResources`.
    ///
    /// The order is not negotiable. `S1NoteState::init` hands `ft_array` straight
    /// to `sp_oscmorph2d_init`, and `allocateRenderResources` walks every table to
    /// rescale `sicvt` for the sample rate — both dereference tables that
    /// `setupWaveform` has to have created first.
    private func makeSynth() throws -> S1AudioUnit {
        let unit = try S1AudioUnit(componentDescription: componentDescription, options: [])
        unit.maximumFramesToRender = framesPerBlock

        let waves = try Self.wavetables.get()
        XCTAssertEqual(waves.tables.count, 52, "4 waveforms x 13 band-limited tables")
        XCTAssertEqual(waves.bandlimitFrequencies.count, 13)

        for (index, frequency) in waves.bandlimitFrequencies.enumerated() {
            unit.setBandlimitFrequency(UInt32(index), withFrequency: frequency)
        }
        for (tableIndex, table) in waves.tables.enumerated() {
            unit.setupWaveform(UInt32(tableIndex), size: Int32(table.count))
            for (sampleIndex, sample) in table.enumerated() {
                unit.setWaveform(UInt32(tableIndex), withValue: sample, at: UInt32(sampleIndex))
            }
        }
        return unit
    }

    // MARK: - Offline rendering

    private struct Render {
        var left: [Float]
        var right: [Float]
        var frameCount: AVAudioFrameCount { AVAudioFrameCount(left.count) }
    }

    /// Renders `seconds` of audio, calling `schedule` before each block with the
    /// time at the start of that block. Note on/off go through the same
    /// main-thread API the app uses.
    private func render(_ unit: S1AudioUnit,
                        seconds: Double,
                        schedule: (Double, S1AudioUnit) -> Void = { _, _ in }) throws -> Render {
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let format = unit.outputBus.format
        XCTAssertEqual(format.channelCount, 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBlock) else {
            XCTFail("could not allocate render buffer")
            return Render(left: [], right: [])
        }
        buffer.frameLength = framesPerBlock

        let renderBlock = unit.internalRenderBlock
        let blocks = Int((seconds * sampleRate / Double(framesPerBlock)).rounded())
        var out = Render(left: [], right: [])
        out.left.reserveCapacity(blocks * Int(framesPerBlock))
        out.right.reserveCapacity(blocks * Int(framesPerBlock))
        var sampleTime: Double = 0

        for _ in 0..<blocks {
            schedule(sampleTime / sampleRate, unit)

            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid

            let status = renderBlock(&flags, &timestamp, framesPerBlock, 0,
                                     buffer.mutableAudioBufferList, nil, nil)
            XCTAssertEqual(status, noErr)

            if let channels = buffer.floatChannelData {
                out.left.append(contentsOf: UnsafeBufferPointer(start: channels[0],
                                                                count: Int(framesPerBlock)))
                out.right.append(contentsOf: UnsafeBufferPointer(start: channels[1],
                                                                 count: Int(framesPerBlock)))
            }
            sampleTime += Double(framesPerBlock)
        }
        return out
    }

    /// Renders one sustained note: on at `noteOn`, off at `noteOff`, tail to
    /// `seconds`.
    private func renderNote(_ note: UInt8,
                            velocity: UInt8 = 127,
                            seconds: Double = 3.0,
                            noteOn: Double = 0,
                            noteOff: Double = 2.0,
                            configure: (S1AudioUnit) -> Void = { _ in }) throws -> Render {
        let unit = try makeSynth()
        configure(unit)
        var started = false
        var stopped = false
        return try render(unit, seconds: seconds) { time, unit in
            if !started && time >= noteOn { unit.startNote(note, velocity: velocity); started = true }
            if !stopped && time >= noteOff { unit.stopNote(note); stopped = true }
        }
    }

    /// How long after `allocateRenderResources` the synth takes to reach its
    /// nominal state. Every portamento-enabled parameter is re-ported from zero
    /// at that point (`S1_PORTAMENTO_HALF_TIME` = 0.1 s), so pitch, cutoff and
    /// volume all sweep in — see `testPitchSweepsInWhileParametersSettle`. Pitch
    /// measurements have to be taken after this, or they measure the sweep.
    private let settleTime: Double = 1.0

    // MARK: - Measurement

    private func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    private func rms(_ x: ArraySlice<Float>) -> Float {
        guard !x.isEmpty else { return 0 }
        let values = Array(x)
        var result: Float = 0
        vDSP_rmsqv(values, 1, &result, vDSP_Length(values.count))
        return result
    }

    private func seconds(_ t: Double) -> Int { Int(t * sampleRate) }

    /// Fundamental frequency by normalised autocorrelation.
    ///
    /// Not zero-crossing counting: Synth One's default patch is a sawtooth, and
    /// a harmonic-rich wave crosses zero many times per cycle. Autocorrelation
    /// measures the *period*, which is what "the expected fundamental" means.
    /// Taking the first strong peak rather than the tallest avoids reporting an
    /// octave down, since r(2T) is as high as r(T) for any periodic signal.
    private func fundamental(_ signal: [Float],
                             minHz: Double = 50,
                             maxHz: Double = 2_000) -> Double {
        var x = signal
        var mean: Float = 0
        vDSP_meanv(x, 1, &mean, vDSP_Length(x.count))
        var negativeMean = -mean
        vDSP_vsadd(x, 1, &negativeMean, &x, 1, vDSP_Length(x.count))

        let minLag = max(1, Int(sampleRate / maxHz))
        let maxLag = min(Int(sampleRate / minHz), x.count / 2)
        guard maxLag > minLag + 1 else { return 0 }
        let window = vDSP_Length(x.count - maxLag)

        var r = [Float](repeating: 0, count: maxLag + 1)
        x.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var zeroLagEnergy: Float = 0
            vDSP_dotpr(base, 1, base, 1, &zeroLagEnergy, window)
            guard zeroLagEnergy > 0 else { return }
            for lag in minLag...maxLag {
                var numerator: Float = 0
                var lagEnergy: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &numerator, window)
                vDSP_dotpr(base + lag, 1, base + lag, 1, &lagEnergy, window)
                r[lag] = numerator / (sqrt(zeroLagEnergy * lagEnergy) + .leastNormalMagnitude)
            }
        }

        let best = r[minLag...maxLag].max() ?? 0
        guard best > 0.3 else { return 0 }   // not periodic enough to call

        var lag = -1
        for candidate in (minLag + 1)..<maxLag
        where r[candidate] >= 0.85 * best
            && r[candidate] >= r[candidate - 1]
            && r[candidate] >= r[candidate + 1] {
            lag = candidate
            break
        }
        guard lag > minLag, lag < maxLag else { return 0 }

        // Parabolic interpolation through the peak, so the answer is not
        // quantised to whole samples (one sample is 4 Hz at 440).
        let y0 = Double(r[lag - 1]), y1 = Double(r[lag]), y2 = Double(r[lag + 1])
        let curvature = y0 - 2 * y1 + y2
        let delta = curvature != 0 ? 0.5 * (y0 - y2) / curvature : 0
        return sampleRate / (Double(lag) + delta)
    }

    /// Magnitude of a Hann-windowed DFT at one frequency. Used to ask "is this
    /// pitch present", which is the right question for a chord — a chord has no
    /// single period to autocorrelate for.
    private func magnitude(of signal: [Float], at frequency: Double) -> Double {
        var real = 0.0, imaginary = 0.0
        let n = Double(signal.count)
        for (i, sample) in signal.enumerated() {
            let window = 0.5 - 0.5 * cos(2 * .pi * Double(i) / (n - 1))
            let phase = 2 * .pi * frequency * Double(i) / sampleRate
            real += Double(sample) * window * cos(phase)
            imaginary -= Double(sample) * window * sin(phase)
        }
        return (real * real + imaginary * imaginary).squareRoot() / n
    }

    // MARK: - Tests

    /// createParameters is where the kernel is built. If it did not run to
    /// completion there is no synth, so check its visible product first.
    func testAudioUnitBuildsTheFullParameterTree() throws {
        let unit = try S1AudioUnit(componentDescription: componentDescription, options: [])
        let parameters = try XCTUnwrap(unit.parameterTree?.allParameters)
        XCTAssertEqual(parameters.count, Int(S1Parameter.S1ParameterCount.rawValue))
        XCTAssertEqual(parameters.count, 150)
        XCTAssertEqual(unit.getSynthParameter(.masterVolume), 0.5, accuracy: 0.000_1)
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 20_000, accuracy: 0.1)
    }

    /// With no note played the synth must be silent — reverb and delay tails
    /// included. A synth that idles with noise would hide every later measurement.
    func testSilentUntilANoteIsPlayed() throws {
        let unit = try makeSynth()
        let render = try render(unit, seconds: 0.5)
        XCTAssertEqual(peak(render.left), 0, accuracy: 0.000_01)
        XCTAssertEqual(peak(render.right), 0, accuracy: 0.000_01)
    }

    /// **The P1-6 acceptance criterion.** A note in, audio out.
    func testNoteOnProducesAudio() throws {
        let render = try renderNote(69)
        XCTAssertGreaterThan(peak(render.left), 0.05, "note on must produce audible output")
        XCTAssertGreaterThan(rms(render.left[seconds(1.2)..<seconds(1.9)]), 0.01)
        XCTAssertLessThanOrEqual(peak(render.left), 1.2, "and must not be clipping hard")
        XCTAssertGreaterThan(peak(render.right), 0.05, "the right channel must carry it too")
    }

    /// **The other half of P1-6.** Audible is not enough — it has to be the right
    /// note. MIDI 69 is A4; the DSP tuning table is initialised to 12-ET at A440.
    func testFundamentalMatchesTheNotePlayed() throws {
        for (note, expected) in [(69, 440.0), (57, 220.0), (81, 880.0), (60, 261.6256)] {
            let render = try renderNote(UInt8(note), seconds: settleTime + 2.0,
                                        noteOn: settleTime, noteOff: settleTime + 2.0)
            let measured = fundamental(Array(render.left[seconds(settleTime + 0.5)..<seconds(settleTime + 1.9)]))
            XCTAssertEqual(measured, expected, accuracy: expected * 0.005,
                           "MIDI \(note) should sound \(expected) Hz, measured \(measured) Hz")
        }
    }

    /// A note struck immediately after `allocateRenderResources` sweeps *up* into
    /// tune over roughly half a second, and this is upstream behaviour, not a
    /// porting defect. `setupParameterTree` re-runs `sp_port_init` for every
    /// portamento-enabled parameter, and `sp_port_init` zeroes the filter state —
    /// so `parameters[detuningMultiplier]` climbs 0 -> 1 with a 0.1 s half-time
    /// while `S1NoteState::run` is multiplying `oscmorph->freq` by it once per
    /// sample. A multiplicative accumulator fed a value below 1 walks the pitch
    /// down, then back up as the parameter settles.
    ///
    /// Pinning it here means a future change to the portamento or the oscillator
    /// frequency path shows up as a failure rather than as a mystery, and it
    /// explains why every other pitch test waits `settleTime` first.
    func testPitchSweepsInWhileParametersSettle() throws {
        let render = try renderNote(69, seconds: 3.0, noteOff: 3.0)

        let early = fundamental(Array(render.left[seconds(0.05)..<seconds(0.20)]))
        let middle = fundamental(Array(render.left[seconds(0.50)..<seconds(0.65)]))
        let settled = fundamental(Array(render.left[seconds(1.50)..<seconds(2.90)]))

        XCTAssertLessThan(early, 400, "a note struck at t=0 starts flat")
        XCTAssertGreaterThan(middle, early, "and sweeps upward as the parameters settle")
        XCTAssertLessThan(middle, settled)
        XCTAssertEqual(settled, 440, accuracy: 2.2, "arriving in tune and staying there")
    }

    /// Transposing down an octave must halve the frequency. This is a different
    /// code path from the note number — `startNote` adds `transpose` before the
    /// tuning-table lookup — and it is cheap insurance that the lookup is real
    /// rather than a coincidence of one note.
    func testTransposeShiftsPitch() throws {
        let render = try renderNote(69, seconds: settleTime + 2.0,
                                    noteOn: settleTime, noteOff: settleTime + 2.0) {
            $0.setSynthParameter(.transpose, value: -12)
        }
        let measured = fundamental(Array(render.left[seconds(settleTime + 0.5)..<seconds(settleTime + 1.9)]))
        XCTAssertEqual(measured, 220, accuracy: 1.1)
    }

    /// Note off must release the envelope, not cut it. Default release is 0.05 s,
    /// so half a second after note off the tail has to be far below sustain.
    func testNoteOffReleasesTheEnvelope() throws {
        let render = try renderNote(69, seconds: 3.0, noteOff: 2.0)
        let sustaining = rms(render.left[seconds(1.5)..<seconds(1.9)])
        let released = rms(render.left[seconds(2.5)..<seconds(2.9)])
        XCTAssertGreaterThan(sustaining, 0.01)
        XCTAssertLessThan(released, sustaining * 0.05, "note off must release the voice")
    }

    /// Four voices at once, under the S1_MAX_POLYPHONY ceiling of six. A chord has
    /// no single period, so this asks the spectrum whether each note is actually
    /// there — a monophonic synth would answer "only the last one".
    func testChordIsPolyphonic() throws {
        let unit = try makeSynth()
        let chordNotes: [UInt8] = [57, 60, 64, 67]              // A3 C4 E4 G4
        let chordFrequencies = [220.0, 261.6256, 329.6276, 391.9954]
        var started = false
        let chord = try render(unit, seconds: settleTime + 2.0) { time, unit in
            guard !started, time >= settleTime else { return }
            started = true
            for note in chordNotes { unit.startNote(note, velocity: 110) }
        }
        let single = try renderNote(57, velocity: 110, seconds: settleTime + 2.0,
                                    noteOn: settleTime, noteOff: settleTime + 2.0)

        let window = seconds(settleTime + 0.5)..<seconds(settleTime + 1.9)
        XCTAssertGreaterThan(rms(chord.left[window]), rms(single.left[window]),
                             "four voices should be louder than one")

        let voiced = Array(chord.left[window])
        // A quarter tone away from each note: present in no harmonic series here,
        // so it is the noise floor this comparison is against.
        let floor = magnitude(of: voiced, at: 240.5)
        for (note, frequency) in zip(chordNotes, chordFrequencies) {
            XCTAssertGreaterThan(magnitude(of: voiced, at: frequency), floor * 10,
                                 "MIDI \(note) (\(frequency) Hz) is missing from the chord")
        }
    }

    /// The kernel is torn down and rebuilt on every allocate/deallocate cycle
    /// (`S1DSPKernel::init` calls `destroy` first). The wavetables are set up once,
    /// outside that cycle, so this is the test that would fail if `destroy` ever
    /// started freeing `ft_array`.
    func testSurvivesRepeatedAllocation() throws {
        let unit = try makeSynth()
        for cycle in 1...3 {
            var started = false
            let render = try render(unit, seconds: settleTime + 1.5) { time, unit in
                guard !started, time >= settleTime else { return }
                unit.startNote(69, velocity: 127)
                started = true
            }
            let window = seconds(settleTime + 0.5)..<seconds(settleTime + 1.4)
            XCTAssertGreaterThan(peak(render.left), 0.05, "silent on cycle \(cycle)")
            XCTAssertEqual(fundamental(Array(render.left[window])), 440, accuracy: 2.2,
                           "detuned on cycle \(cycle)")
        }
    }

    /// Not an assertion — a deliverable. Renders a short phrase and writes it to a
    /// WAV so a person can *listen*, which until P2-4's golden files exist is the
    /// only check that catches the class of bug ADR-011 warns about: audio that
    /// measures plausibly and sounds wrong.
    func testWritesAuditionWAV() throws {
        let unit = try makeSynth()
        let melody: [(time: Double, note: UInt8)] = [
            (1.0, 57), (1.6, 60), (2.2, 64), (2.8, 69)
        ]
        let chord: [UInt8] = [45, 57, 64, 72]
        var fired = Set<Int>()
        var chordFired = false

        // One second of silence first, so the parameter portamento has settled and
        // the phrase is in tune from its first note (testPitchSweepsInWhile-
        // ParametersSettle covers what happens when it has not).
        let render = try render(unit, seconds: 8.0) { time, unit in
            for (index, event) in melody.enumerated()
            where !fired.contains(index) && time >= event.time {
                fired.insert(index)
                unit.startNote(event.note, velocity: 100)
                if index > 0 { unit.stopNote(melody[index - 1].note) }
            }
            if !chordFired && time >= 4.2 {
                chordFired = true
                unit.stopNote(melody[melody.count - 1].note)
                for note in chord { unit.startNote(note, velocity: 76) }
            }
            if chordFired && time >= 6.6 {
                for note in chord { unit.stopNote(note) }
            }
        }
        XCTAssertGreaterThan(peak(render.left), 0.05)
        // Velocities are chosen so the four-voice chord stays inside full scale:
        // masterVolume defaults to 0.5 and pow2() squares velocity, so a chord at
        // 110 does exceed 1.0 and the 24-bit file would clamp. That is the patch
        // behaving as designed, but a clipped audition file is a bad listening test.
        XCTAssertLessThan(peak(render.left), 0.99, "the audition render must not clip")
        XCTAssertLessThan(peak(render.right), 0.99, "the audition render must not clip")

        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/SynthOneTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("p1-6-first-sound.wav")

        let file = try AVAudioFile(forWriting: url,
                                   settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                                              AVSampleRateKey: sampleRate,
                                              AVNumberOfChannelsKey: 2,
                                              AVLinearPCMBitDepthKey: 24,
                                              AVLinearPCMIsFloatKey: false,
                                              AVLinearPCMIsBigEndianKey: false],
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: render.frameCount))
        buffer.frameLength = render.frameCount
        let channels = try XCTUnwrap(buffer.floatChannelData)
        render.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: $0.count) }
        render.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: $0.count) }
        try file.write(from: buffer)

        print("P1-6 audition WAV: \(url.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
