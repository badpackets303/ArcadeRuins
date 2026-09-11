//  What the host actually gets when it loads the plugin (P4-2).
//
//  Until now this returned `SynthOneAudioUnit`, a P1-1 shell whose render block
//  `memset`s the buffer to silence. It is gone: the plugin vends **`S1AudioUnit`**,
//  the same Obj-C++ audio unit the standalone app plays through and the one P1-6
//  proved renders in tune and P2-4's golden files pin.
//
//  ## Why there is no engine here
//
//  The standalone app owns an `AVAudioEngine`; a plugin does not. The host owns the
//  graph, pulls `internalRenderBlock` on its own thread, and gives us the format.
//  So this path must **never** touch `AVAudioEngine.outputNode` — an audio unit has
//  no business opening an output device (ADR-015, and P3-4 for what that costs).
//  `S1AudioUnit` is an `AUAudioUnit` already, so there is nothing to wrap.
//
//  ## Ordering
//
//  Wavetables must be loaded after `init` and before the host calls
//  `allocateRenderResources`. Returning from this method is exactly that window.
//
//  ## The interface (P4-6)
//
//  The same 12 storyboards the standalone uses, from the same framework bundle. It
//  is driven through `Conductor` exactly as the app drives it — the difference is
//  `SynthOneApp.startHosted`, which wires the interface to the host's audio unit
//  instead of building an engine. See `S1SynthControlling`.

import CoreAudioKit
import AVFoundation
import SynthOneCore

public final class SynthOneAudioUnitViewController: AUViewController, AUAudioUnitFactory {

    /// Held so the view can reach it at P4-6.
    public private(set) var audioUnit: S1AudioUnit?

    /// The real interface, once there is an audio unit to drive.
    private var interface: UIViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = S1ScalingContainer.designSize
        view.backgroundColor = .black
        installInterfaceIfPossible()
    }

    /// **The ordering problem.** Hosts differ: some create the view controller first
    /// and call `createAudioUnit` afterwards, others the reverse. So both paths call
    /// this and it does nothing until it has both a loaded view and a unit.
    private func installInterfaceIfPossible() {
        guard interface == nil, isViewLoaded, let audioUnit else { return }

        // Before the interface: `Manager.viewDidLoad` force-unwraps `conductor.synth`
        // and reads every parameter's range as it wires up its controls.
        SynthOneApp.startHosted(audioUnit: audioUnit)

        let interface = SynthOneApp.makeRootViewController()
        addChild(interface)
        interface.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(interface.view)
        NSLayoutConstraint.activate([
            interface.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            interface.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            interface.view.topAnchor.constraint(equalTo: view.topAnchor),
            interface.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        interface.didMove(toParent: self)
        self.interface = interface
    }

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        // Built in SynthOneCore, so the tests build exactly the unit a host gets: the kernel,
        // the wavetables, the factory presets and host-MIDI routing (ADR-031).
        let unit = try SynthOneApp.makePluginAudioUnit(componentDescription: componentDescription)

        audioUnit = unit

        // The host may have built the view already — see `installInterfaceIfPossible`.
        DispatchQueue.main.async { [weak self] in self?.installInterfaceIfPossible() }

        return unit
    }
}
