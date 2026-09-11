//  Stands in for AudioKit's `AKMixer`. Synth One uses exactly one, in
//  `Conductor.start()`: `mixer = AKMixer(synth)`.
//
//  AudioKit's version connects its inputs immediately through the global engine.
//  Ours records them and lets `S1AudioEngine` do the attaching and connecting,
//  because there is no global engine to connect through (ADR-014).

import AVFoundation
import S1Support

@objc open class AKMixer: AKNode {

    /// The mixer node itself, typed. `avAudioNode` is the same object.
    public let mixerNode: AVAudioMixerNode

    /// Nodes feeding this mixer, in the order they were added.
    public private(set) var inputs: [AKNode] = []

    /// Output level, 0...1.
    @objc open var volume: Double {
        get { Double(mixerNode.outputVolume) }
        set { mixerNode.outputVolume = Float(newValue) }
    }

    public init(_ inputs: [AKNode] = []) {
        let node = AVAudioMixerNode()
        self.mixerNode = node
        self.inputs = inputs
        super.init(avAudioNode: node)
    }

    /// Upstream's variadic shape: `AKMixer(synth)`.
    public convenience init(_ inputs: AKNode...) {
        self.init(inputs)
    }

    /// Add an input. Takes effect the next time the graph is built.
    @objc open func connect(input: AKNode) {
        inputs.append(input)
    }
}
