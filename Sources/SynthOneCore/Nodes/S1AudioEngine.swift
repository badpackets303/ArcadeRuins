//  S1AudioEngine — the replacement for AudioKit's global `AudioKit` engine (P2-1).
//  Ours outright, hence the `S1` prefix (ADR-009).
//
//  AudioKit exposed one process-wide `AVAudioEngine` behind static members
//  (`AudioKit.engine`, `AudioKit.output`, `AudioKit.start()`), and `AKNode`
//  reached back into it to attach itself. This is an object you hold instead.
//  See ADR-014 for why, and P4-2 for where it goes next.
//
//  The graph Synth One builds is fixed and small — `synth -> mixer -> output` —
//  so this models exactly that rather than reproducing AudioKit's connection DSL.

import AVFoundation
import S1Support

public final class S1AudioEngine {

    /// The engine itself. Exposed because the host-icon and recorder code needs
    /// `outputNode`, and because tests need `manualRenderingBlock`.
    public let engine = AVAudioEngine()

    /// The last node in the chain, mirroring upstream's `AudioKit.output = mixer`.
    ///
    /// Setting it only *records* the intent — the graph is built when the engine
    /// starts. That ordering is load-bearing; see `startOfflineRendering`.
    public var output: AKNode? {
        didSet { graphIsBuilt = false }
    }

    public var isRunning: Bool { engine.isRunning }

    private var graphIsBuilt = false

    // MARK: - Device changes (ADR-043)
    //
    // When the output or input hardware changes — AirPods taken out of an ear, a USB interface
    // unplugged, another default device chosen — AVAudioEngine stops itself and posts
    // `AVAudioEngineConfigurationChange`. Upstream never listened, and on iOS the session's
    // interruption handling covered for it. The standalone went silent until it was relaunched.
    // Nodes stay attached and connected through the change, and the output unit converts to the
    // new device's format, so starting again is enough.

    /// Whether the app wants sound. Set by `start()`, cleared by `pause()`, `stop()` and offline
    /// rendering. A configuration change stops the engine without clearing it, which is how the
    /// restart tells an engine the app paused from one the hardware stopped. Internal so tests can
    /// stand in for a realtime start, which would open a hardware device (ADR-015).
    var shouldBeRunning = false

    /// What a configuration change does when the engine should be running. Replaced in tests.
    var restartAfterConfigurationChange: (S1AudioEngine) -> Void = { audioEngine in
        audioEngine.restartQueue.async { audioEngine.restart() }
    }

    /// Off the main thread, like the first start in `Conductor.start(mode:)`: opening a device
    /// can take a while, and the window should not wait behind it.
    private let restartQueue = DispatchQueue(label: "S1AudioEngine.restart", qos: .userInitiated)
    private var configurationObserver: NSObjectProtocol?

    public init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.configurationDidChange()
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    func configurationDidChange() {
        guard shouldBeRunning else { return }
        AKLog("S1AudioEngine: the audio hardware changed and the engine stopped; restarting")
        restartAfterConfigurationChange(self)
    }

    /// A few tries, because the new device may not be ready the moment the notification arrives.
    private func restart() {
        for attempt in 1...5 {
            guard shouldBeRunning else { return }       // paused meanwhile
            guard !engine.isRunning else { return }
            do {
                try engine.start()
                AKLog("S1AudioEngine: restarted after the audio hardware changed (attempt \(attempt))")
                return
            } catch {
                AKLog("S1AudioEngine: restart attempt \(attempt) failed: \(error)")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    // MARK: - Graph

    private func attach(_ node: AKNode) {
        let avNode = node.avAudioUnitOrNode
        if avNode.engine == nil { engine.attach(avNode) }
    }

    /// Wires `mixer inputs -> mixer -> engine.outputNode`.
    ///
    /// Connections are made with a `nil` format on purpose: the source bus format
    /// is used, and `AVAudioMixerNode` will sample-rate convert into whatever the
    /// output node is running at. That is what lets the same graph serve both the
    /// hardware and offline rendering at another rate without being rebuilt by hand.
    private func buildGraphIfNeeded() {
        guard !graphIsBuilt, let output = output else { return }
        graphIsBuilt = true
        attach(output)

        if let mixer = output as? AKMixer {
            for input in mixer.inputs {
                attach(input)
                engine.connect(input.avAudioUnitOrNode, to: mixer.mixerNode, format: nil)
            }
        }
        engine.connect(output.avAudioUnitOrNode, to: engine.outputNode, format: nil)
    }

    // MARK: - Transport

    public func start() throws {
        shouldBeRunning = true
        if engine.manualRenderingMode != .realtime {
            engine.stop()
            engine.disableManualRenderingMode()
            graphIsBuilt = false
        }
        buildGraphIfNeeded()
        guard !engine.isRunning else { return }
        try engine.start()
    }

    /// Upstream's `stopEngine()` — pause, so the graph survives.
    public func pause() {
        shouldBeRunning = false
        engine.pause()
    }

    public func stop() {
        shouldBeRunning = false
        engine.stop()
    }

    // MARK: - Offline rendering
    //
    // The same path the P2-4 golden-WAV tests will use.
    //
    // ⚠️ **`enableManualRenderingMode` must be the first thing to touch the
    // engine.** `AVAudioEngine.outputNode` lazily creates the hardware output
    // unit, and in a process that cannot get an output device — an `xctest`
    // bundle, for one — that call blocks for **90 seconds** before giving up and
    // succeeding anyway. Enabling manual rendering first means the hardware unit
    // is never created at all: measured 0.009 s against 90.6 s. This is why
    // `output` only records its node and the graph is built here, after the
    // switch. ADR-015.

    public func startOfflineRendering(sampleRate: Double = 44_100,
                                      channels: AVAudioChannelCount = 2,
                                      maximumFrameCount: AVAudioFrameCount = 4_096) throws {
        // Offline rendering has no hardware to change under it (ADR-043).
        shouldBeRunning = false
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: channels) else {
            throw S1AudioEngineError.unsupportedFormat(sampleRate: sampleRate, channels: channels)
        }
        if engine.isRunning { engine.stop() }
        try engine.enableManualRenderingMode(.offline, format: format,
                                             maximumFrameCount: maximumFrameCount)
        graphIsBuilt = false
        buildGraphIfNeeded()
        try engine.start()
    }

    /// Pulls one block. The caller owns the loop, so note events can be scheduled
    /// between blocks exactly as they are in a real render callback.
    @discardableResult
    public func render(into buffer: AVAudioPCMBuffer) throws -> AVAudioEngineManualRenderingStatus {
        try engine.renderOffline(buffer.frameLength, to: buffer)
    }

    /// A buffer sized for one block of offline rendering.
    public func makeRenderBuffer(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                      frameCapacity: frameCount)
        buffer?.frameLength = frameCount
        return buffer
    }
}

public enum S1AudioEngineError: Error {
    case unsupportedFormat(sampleRate: Double, channels: AVAudioChannelCount)
}
