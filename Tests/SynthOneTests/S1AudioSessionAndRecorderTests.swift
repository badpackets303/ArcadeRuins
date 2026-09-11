//  P2-2 and P2-3 acceptance.
//
//  P2-2: the audio session is behind a protocol, and the default implementation
//  is the one that does nothing — because the failure mode of getting it wrong in
//  the plugin is invisible and the failure mode of getting it wrong in the app is
//  not.
//
//  P2-3: recording is an AVAudioFile tap, and it produces a real WAV containing
//  the audio that was playing.

import XCTest
import AVFoundation
@testable import SynthOneCore

final class S1AudioSessionTests: XCTestCase {

    override func tearDown() {
        S1AudioSessionProvider.current = S1HostedAudioSession()
        super.tearDown()
    }

    /// The default has to be the no-op. An AUv3 that never opts in must not touch
    /// the host's session, and "you forgot to configure it" has to be the safe
    /// state rather than the dangerous one.
    func testDefaultSessionIsTheHostedNoOp() {
        XCTAssertTrue(S1AudioSessionProvider.current is S1HostedAudioSession)
    }

    /// Every call is a no-op and none of them throw — the shared UI code calls
    /// these unconditionally.
    func testHostedSessionDoesNothingAndSucceeds() throws {
        let session = S1HostedAudioSession()
        XCTAssertNoThrow(try session.configure())
        XCTAssertNoThrow(try session.setActive(true))
        XCTAssertNoThrow(try session.setActive(false))
        XCTAssertNoThrow(try session.setPreferredIOBufferDuration(0.005))
    }

    /// Hosted sessions report the rate the audio unit is actually rendering at,
    /// which is what the host handed us — not the hardware's.
    func testHostedSessionReportsTheAudioUnitSampleRate() {
        let original = AKSettings.sampleRate
        defer { AKSettings.sampleRate = original }
        AKSettings.sampleRate = 96_000
        XCTAssertEqual(S1HostedAudioSession().sampleRate, 96_000)
    }

    /// The standalone app's session really does reach `AVAudioSession`.
    ///
    /// **`.playback`, not upstream's `.playAndRecord`** — and this assertion is the
    /// point of the test, not a detail. `.playAndRecord` makes macOS prompt for
    /// microphone access, and the app blocks on that dialog: 72 seconds before the
    /// window appeared, measured at P3-4. Synth One never records audio input here —
    /// `S1NodeRecorder` taps the mixer's *output*, and Audiobus and IAA are gone.
    ///
    /// If this ever goes back to `.playAndRecord`, the app starts asking for a
    /// permission it does not use and hanging on the answer.
    func testSystemSessionUsesPlaybackAndNeverAsksForTheMicrophone() throws {
        let session = S1SystemAudioSession()
        try session.configure()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        XCTAssertFalse(AVAudioSession.sharedInstance().category == .playAndRecord,
                       "requesting record access prompts for the microphone at launch")
        XCTAssertGreaterThan(session.sampleRate, 0)
        try session.setActive(false)
    }

    /// The other half of the same fix: nothing should declare a microphone need.
    func testAppDeclaresNoMicrophoneUsage() throws {
        // The app bundle, not the test bundle.
        let appPlist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOne/Info.plist")
        let data = try Data(contentsOf: appPlist)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any])
        XCTAssertNil(plist["NSMicrophoneUsageDescription"],
                     "a microphone usage string means something is asking for the microphone")
    }

    /// Swapping the implementation is the whole point.
    func testProviderIsSwappable() {
        S1AudioSessionProvider.current = S1SystemAudioSession()
        XCTAssertTrue(S1AudioSessionProvider.current is S1SystemAudioSession)
    }
}

final class S1NodeRecorderTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SynthOneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// **The Record button's whole path** (P4-6): `toggleRecord` on, render, off —
    /// and a `.wav` named by date appears in the recorder's directory.
    ///
    /// `S1NodeRecorder` is well covered below, but nothing exercised `AudioRecorder`,
    /// which is what the button actually calls and which owns the filename and the
    /// destination folder.
    func testTheRecordButtonPathProducesAFile() throws {
        let synth = AKSynthOne()
        let engine = S1AudioEngine()
        let mixer = AKMixer(synth)
        engine.output = mixer
        try engine.startOfflineRendering(sampleRate: sampleRate, maximumFrameCount: framesPerBlock)

        let recorder = AudioRecorder(node: mixer.mixerNode)
        recorder.directory = scratch          // not the real ~/Music/SynthOne
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)

        guard let buffer = engine.makeRenderBuffer(frameCount: framesPerBlock) else {
            return XCTFail("no render buffer")
        }
        synth.play(noteNumber: 69, velocity: 127)
        recorder.toggleRecord(value: 1)       // what the button does
        var frames: Double = 0
        while frames < 1.0 * sampleRate {
            _ = try engine.render(into: buffer)
            frames += Double(framesPerBlock)
        }
        recorder.toggleRecord(value: 0)

        let written = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
        XCTAssertEqual(written.count, 1, "the button produced no file: \(written)")
        let name = try XCTUnwrap(written.first)
        XCTAssertTrue(name.hasSuffix(".wav"), "\(name) is not a WAV")

        // And it has audio in it — an empty file would pass a "file exists" check.
        let url = scratch.appendingPathComponent(name)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 44 * 1_000, "\(name) is \(size) bytes — header only")
    }

    /// Records the synth's own output through the tap, offline, and reads the WAV
    /// back. Recording silence would pass a "file exists" check, so this checks
    /// the samples.
    func testRecordsTheGraphToAPlayableWAV() throws {
        let synth = AKSynthOne()
        let engine = S1AudioEngine()
        let mixer = AKMixer(synth)
        engine.output = mixer
        try engine.startOfflineRendering(sampleRate: sampleRate, maximumFrameCount: framesPerBlock)

        let recorder = S1NodeRecorder(node: mixer.mixerNode)
        let url = scratch.appendingPathComponent("take.wav")

        guard let buffer = engine.makeRenderBuffer(frameCount: framesPerBlock) else {
            return XCTFail("no render buffer")
        }
        // One second of settling first (ADR-013), then record two seconds of A440.
        var recording = false
        var frames: Double = 0
        while frames < 3.0 * sampleRate {
            let time = frames / sampleRate
            if time >= 1.0 && !recording {
                recording = true
                synth.play(noteNumber: 69, velocity: 127)
                try recorder.record(to: url)
            }
            _ = try engine.render(into: buffer)
            frames += Double(buffer.frameLength)
        }
        let written = recorder.stop()
        engine.stop()

        XCTAssertEqual(written, url)
        XCTAssertFalse(recorder.isRecording)

        // A tap only ever delivers whole buffers, so the take is short by up to one
        // of them. 4,410 frames at 44.1 kHz, whatever `bufferSize` asked for.
        let tapSeconds = Double(recorder.tapBufferFrames) / sampleRate
        XCTAssertGreaterThan(recorder.tapBufferFrames, 0)
        XCTAssertEqual(recorder.recordedDuration, 2.0, accuracy: tapSeconds + 0.01)
        XCTAssertLessThanOrEqual(recorder.recordedDuration, 2.0)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, sampleRate)
        XCTAssertEqual(file.fileFormat.channelCount, 2)
        XCTAssertEqual(Double(file.length), recorder.recordedDuration * sampleRate, accuracy: 1,
                       "the finished file must hold exactly what the recorder counted")

        let readBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                        frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: readBuffer)
        let samples = UnsafeBufferPointer(start: try XCTUnwrap(readBuffer.floatChannelData)[0],
                                          count: Int(readBuffer.frameLength))
        XCTAssertGreaterThan(samples.reduce(0) { max($0, abs($1)) }, 0.05,
                             "the recording has to contain the note, not silence")
    }

    /// The header's length fields are only written when the file object is
    /// released, so a recording that is never stopped is a broken WAV. `stop()`
    /// has to be what closes it.
    func testStopFinalisesTheFile() throws {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: framesPerBlock)
        let source = AVAudioPlayerNode()
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()

        let recorder = S1NodeRecorder(node: engine.mainMixerNode)
        let url = scratch.appendingPathComponent("short.wav")
        try recorder.record(to: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: framesPerBlock)!
        buffer.frameLength = framesPerBlock
        for _ in 0..<10 { _ = try engine.renderOffline(framesPerBlock, to: buffer) }
        recorder.stop()
        engine.stop()

        // 10 x 512 = 5,120 frames rendered, delivered as whole tap buffers only.
        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0, "stop() must flush and close the file")
        XCTAssertEqual(file.length, Int64(recorder.recordedDuration * sampleRate), accuracy: 1)
        XCTAssertEqual(file.length % Int64(recorder.tapBufferFrames), 0,
                       "a take is a whole number of tap buffers")
        XCTAssertLessThanOrEqual(file.length, 10 * Int64(framesPerBlock))
    }

    func testRecordingWithoutANodeThrows() {
        let recorder = S1NodeRecorder()
        XCTAssertThrowsError(try recorder.record(to: scratch.appendingPathComponent("x.wav")))
    }

    /// `reset()` deletes the previous take — upstream's recorder calls it before
    /// every new recording.
    func testResetRemovesThePreviousTake() throws {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: framesPerBlock)
        try engine.start()

        let recorder = S1NodeRecorder(node: engine.mainMixerNode)
        let url = scratch.appendingPathComponent("take.wav")
        try recorder.record(to: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: framesPerBlock)!
        buffer.frameLength = framesPerBlock
        _ = try engine.renderOffline(framesPerBlock, to: buffer)
        recorder.stop()
        engine.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try recorder.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(recorder.url)
        XCTAssertEqual(recorder.recordedDuration, 0)
    }
}
