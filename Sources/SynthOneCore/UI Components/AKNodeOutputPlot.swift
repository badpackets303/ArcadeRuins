//  Stands in for AudioKitUI's `AKNodeOutputPlot` (P3-1).
//
//  AudioKit's version subclasses `EZAudioPlot` — EZAudio being a vendored Obj-C
//  library of its own, several thousand lines, for one waveform display in the
//  Generators panel. Not worth carrying, so this is ours: a `UIView` that taps a
//  node and draws what comes back.
//
//  The surface is exactly what Synth One touches — `init(_:)`, `color`, `gain`,
//  `shouldFill`, `pause()`, `resume()` — so `GeneratorsPanelController` and
//  `Conductor` port unchanged. The name is kept for the same reason (ADR-009).

import UIKit
import AVFoundation
import S1Support

open class AKNodeOutputPlot: UIView {

    /// Waveform colour.
    @objc open var color: UIColor = .orange { didSet { setNeedsDisplay() } }

    /// Vertical scale applied to the samples before drawing.
    @objc open var gain: Double = 1.0

    /// Fill under the waveform rather than stroking it.
    @objc open var shouldFill: Bool = false { didSet { setNeedsDisplay() } }

    /// Samples per redraw. 1,024 at 44.1 kHz is ~23 ms of audio, which reads as a
    /// live waveform rather than a flicker.
    @objc open var bufferSize: AVAudioFrameCount = 1_024

    private weak var node: AVAudioNode?
    private var isTapped = false

    // MARK: Pull mode (P4-6)

    /// Where the samples come from when there is no node — see `resume(pulling:)`.
    private var pull: ((UnsafeMutablePointer<Float>, Int) -> Bool)?
    /// Preallocated. The pull runs at display rate and must not allocate per frame.
    private var pullBuffer: [Float] = []
    private var displayLink: CADisplayLink?
    /// Written on the audio thread, read on the main thread. A torn read here
    /// costs one frame of a decorative waveform, so it is not worth a lock on the
    /// render path.
    private var samples: [Float] = []

    public convenience init(_ node: AKNode?, frame: CGRect = .zero) {
        self.init(frame: frame)
        setupNode(node?.avAudioUnitOrNode)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
    }

    deinit {
        // Not `pause()`: that touches `isTapped` on whatever thread deinit runs on,
        // and removing a tap twice is a hard crash.
        if isTapped { node?.removeTap(onBus: 0) }
        displayLink?.invalidate()
    }

    open func setupNode(_ node: AVAudioNode?) {
        guard let node = node, !isTapped else { return }
        self.node = node
        install(on: node)
    }

    /// `installTap` raises an Obj-C exception — an outright abort, not an error —
    /// on a node that is not attached to an engine. `S1AudioEngine` builds its
    /// graph lazily, when the engine starts (ADR-015), so a plot created between
    /// `engine.output = mixer` and `engine.start()` sees an unattached node. That
    /// crashed the app on launch until P3-1 found it.
    ///
    /// `Conductor` now creates the plot after starting, and this refuses to tap an
    /// unattached node in any case: a decorative waveform must never be able to
    /// take the app down.
    private func install(on node: AVAudioNode) {
        guard node.engine != nil else {
            AKLog("AKNodeOutputPlot: node is not attached to an engine yet; not tapping")
            return
        }
        node.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self, let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let captured = Array(UnsafeBufferPointer(start: channel, count: count))
            DispatchQueue.main.async {
                self.samples = captured
                self.setNeedsDisplay()
            }
        }
        isTapped = true
    }

    @objc open func pause() {
        displayLink?.invalidate()
        displayLink = nil
        guard isTapped, let node = node else { return }
        node.removeTap(onBus: 0)
        isTapped = false
    }

    /// Drive the plot from a pull source rather than a node tap (P4-6).
    ///
    /// The plugin's case. There is no `AVAudioNode` to tap — the host owns the graph —
    /// so the audio unit keeps its last `bufferSize` output samples in a lock-free ring
    /// (`S1Scope`) and this collects a snapshot on each display frame. `source` returns
    /// `false` when it has nothing consistent to give, and the plot simply keeps the
    /// frame it already has.
    ///
    /// - Parameter source: called on the **main** thread with a destination and a
    ///   sample count; fills the destination and returns whether it did.
    open func resume(pulling source: @escaping (UnsafeMutablePointer<Float>, Int) -> Bool) {
        pull = source
        let count = Int(bufferSize)
        if pullBuffer.count != count { pullBuffer = [Float](repeating: 0, count: count) }

        guard displayLink == nil else { return }
        // The proxy, not `self`: `CADisplayLink` retains its target, and a plot that
        // owned one directly would keep itself alive for the life of the run loop.
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        // 30 Hz. The waveform is decoration; matching the display's full rate would
        // double the work for no visible difference.
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func pullSamples() {
        guard let pull = pull, !pullBuffer.isEmpty else { return }
        let filled = pullBuffer.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return pull(base, buffer.count)
        }
        guard filled else { return }
        samples = pullBuffer
        setNeedsDisplay()
    }

    @objc open func resume() {
        guard !isTapped, let node = node else { return }
        install(on: node)
    }

    /// Useful after reconnecting the graph.
    @objc open func reconnect() {
        pause()
        resume()
    }

    open override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), samples.count > 1 else { return }

        let middle = rect.midY
        let scale = CGFloat(gain) * rect.height / 2
        let step = rect.width / CGFloat(samples.count - 1)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: middle - CGFloat(samples[0]) * scale))
        for (index, sample) in samples.enumerated().dropFirst() {
            let y = middle - CGFloat(max(-1, min(1, sample))) * scale
            path.addLine(to: CGPoint(x: CGFloat(index) * step, y: y))
        }

        context.setLineWidth(1)
        if shouldFill {
            path.addLine(to: CGPoint(x: rect.maxX, y: middle))
            path.addLine(to: CGPoint(x: 0, y: middle))
            path.close()
            color.setFill()
            path.fill()
        } else {
            color.setStroke()
            path.stroke()
        }
    }
}

/// Holds the plot weakly on behalf of `CADisplayLink`, which retains its target.
private final class DisplayLinkProxy: NSObject {
    private weak var plot: AKNodeOutputPlot?
    init(_ plot: AKNodeOutputPlot) { self.plot = plot }
    @objc func tick() { plot?.pullSamples() }
}
