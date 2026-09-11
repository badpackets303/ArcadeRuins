//  S1NodeRecorder — P2-3. Replaces AudioKit's `AKNodeRecorder`.
//
//  AudioKit recorded into a CAF through `AKAudioFile` and then had to
//  `exportAsynchronously` to WAV afterwards, because `AKAudioFile` wrote its own
//  format. `AVAudioFile` writes the WAV directly, so the export step — and the
//  asynchronous callback and error path that came with it — is gone.

import AVFoundation

public final class S1NodeRecorder {

    /// The node being recorded. Setting it moves the tap.
    public var node: AVAudioNode? {
        didSet {
            guard node !== oldValue else { return }
            if isRecording { stop() }
            if isTapped, oldValue?.engine != nil { oldValue?.removeTap(onBus: bus) }
            isTapped = false
        }
    }

    public private(set) var isRecording = false

    /// URL of the file being written, or the last one written.
    public private(set) var url: URL?

    /// Seconds captured so far.
    public private(set) var recordedDuration: Double = 0

    /// Frames per tap callback, as observed from the first one.
    ///
    /// `installTap`'s `bufferSize` is a *hint*: AVAudioEngine picks its own size —
    /// 4,410 frames (0.1 s) at 44.1 kHz here, whatever we ask for. It only ever
    /// hands over complete buffers, so **up to one buffer of audio is lost when
    /// recording stops**. That is inherent to tapping a node and it was true of
    /// AudioKit's `AKNodeRecorder` too. For a synth take it is inaudible; it is
    /// recorded here so nobody has to rediscover it while chasing a "recording is
    /// short" bug.
    public private(set) var tapBufferFrames: AVAudioFrameCount = 0

    private var framesWritten: AVAudioFramePosition = 0

    private let bus: AVAudioNodeBus = 0
    private let bufferSize: AVAudioFrameCount = 4_096
    private var file: AVAudioFile?

    public init(node: AVAudioNode? = nil) {
        self.node = node
    }

    deinit {
        // PORT FIX (P4-6): was an unconditional `removeTap`. Two ways that takes the
        // process down, and a test suite found both.
        //
        // `removeTap` asserts `required condition is false: NULL != engine`, so a
        // recorder that outlives its engine — which happens whenever the two are
        // released in the wrong order — aborts. And removing a tap that was never
        // installed is pointless anyway. `AKNodeOutputPlot` already guards its own
        // deinit the same way; this one did not.
        //
        // It surfaced as a crash in an *unrelated* test, because the abort happens
        // whenever ARC gets round to the recorder.
        guard isTapped, node?.engine != nil else { return }
        node?.removeTap(onBus: bus)
    }

    /// Whether a tap is currently installed, which is not the same as `isRecording`:
    /// the tap goes on before recording starts and comes off in `stop()`.
    private var isTapped = false

    /// Start writing to `url`. 24-bit WAV: what a person expects to be handed, and
    /// `AVAudioFile` converts from the tap's float32 on the way in.
    public func record(to url: URL) throws {
        guard let node = node else { throw S1RecorderError.noNode }
        guard !isRecording else { return }

        let tapFormat = node.outputFormat(forBus: bus)
        guard tapFormat.sampleRate > 0 else { throw S1RecorderError.nodeNotRendering }

        let file = try AVAudioFile(forWriting: url,
                                   settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                                              AVSampleRateKey: tapFormat.sampleRate,
                                              AVNumberOfChannelsKey: tapFormat.channelCount,
                                              AVLinearPCMBitDepthKey: 24,
                                              AVLinearPCMIsFloatKey: false,
                                              AVLinearPCMIsBigEndianKey: false],
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        self.file = file
        self.url = url
        recordedDuration = 0
        framesWritten = 0
        tapBufferFrames = 0

        isTapped = true
        node.installTap(onBus: bus, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.file else { return }
            do {
                try file.write(from: buffer)
                if self.tapBufferFrames == 0 { self.tapBufferFrames = buffer.frameLength }
                // Counted rather than read back from `file.length`, which lags the
                // writes by a buffer.
                self.framesWritten += AVAudioFramePosition(buffer.frameLength)
                self.recordedDuration = Double(self.framesWritten) / tapFormat.sampleRate
            } catch {
                AKLog("recorder write failed: \(error)")
            }
        }
        isRecording = true
    }

    /// Stop and close the file. Returns where it landed.
    @discardableResult
    public func stop() -> URL? {
        guard isRecording else { return url }
        if node?.engine != nil { node?.removeTap(onBus: bus) }
        isTapped = false
        isRecording = false
        // Closing the AVAudioFile is what flushes the header's length fields; a
        // WAV whose file object is still alive is not finished.
        file = nil
        return url
    }

    /// Throw away the last recording and get ready for another.
    public func reset() throws {
        if isRecording { stop() }
        if let url = url, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        url = nil
        recordedDuration = 0
        framesWritten = 0
        tapBufferFrames = 0
    }
}

public enum S1RecorderError: Error {
    case noNode
    case nodeNotRendering
}
