//
//  Conductor.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 7/23/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

// PORT: `import AudioKit` / `import AudioKitUI`.
import UIKit
import AVFoundation
import S1Support

class Conductor: NSObject, S1Protocol {

    static var sharedInstance = Conductor()

    /// Internal rather than private (P4-6): a singleton by convention, but hosted
    /// mode has to be testable without commandeering the shared instance that every
    /// other suite's view controllers already captured. Nothing in the product builds
    /// a second one.
    override init() { super.init() }
    
    /// PORT: upstream sets `UIApplication.shared.isIdleTimerDisabled`. Under
    /// Catalyst that property exists but does nothing — display sleep on macOS is
    /// the system's business, not an app's. Kept as stored state so the DEV panel's
    /// toggle still reads back, and so P3-6 can decide whether to reach for
    /// `ProcessInfo.beginActivity` instead.
    var neverSleep = false

    var backgroundAudio = false

    var banks: [Bank] = []

    /// The synth as the *interface* sees it (P4-6).
    ///
    /// Typed as the protocol, not as `AKSynthOne`, so the same 153 UI files drive
    /// either an `AKSynthOne` in an engine we own or the bare `S1AudioUnit` a host
    /// hands the plugin. See `S1SynthControlling`.
    var synth: S1SynthControlling!

    /// The same object as `synth` in the standalone, and **nil in the plugin**.
    ///
    /// Everything that needs the *node* rather than the synth lives here: the mixer,
    /// the sustainer and the output plot all take an `AKNode`, and a plugin has no
    /// graph to put one in.
    private(set) var synthNode: AKSynthOne?

    /// True when the interface is driving a host's audio unit (P4-6).
    ///
    /// The honest question for anything that differs between the app and the plugin.
    /// **Do not infer it from `audioRecorder == nil`**: in the standalone the engine
    /// starts on a background queue, so the recorder does not exist until
    /// `engineDidStart` runs — which is *after* the panels have loaded. Hiding the
    /// Record button on that test hid it in the app too.
    private(set) var isHosted = false

    var audioPlotter: AKNodeOutputPlot!

    var sustainer: SDSustainer!

    var audioRecorder: AudioRecorder?

    var mixer: AKMixer?

    /// PORT: replaces AudioKit's process-wide `AudioKit.engine` / `.output` /
    /// `.start()`. ADR-014.
    let engine = S1AudioEngine()

    // PORT: `midiInput: ABMIDIReceiverPort?` and `audioBusMidiDelegate` were the
    // Audiobus MIDI hooks. Audiobus is iOS-only and is stubbed out (P3-2).

    var midiInChannel: MIDIChannel = MIDIChannel(0)

    var isOmniMode: Bool = true

    var bindings: [(S1Parameter, S1Control)] = []

    var defaultValues: [Double] = []

    var heldNoteCount: Int = 0

    // PORT: `audioUnitPropertyListener: AudioUnitPropertyListener!` watched
    // `kAudioUnitProperty_IsInterAppConnected` to show the Inter-App Audio host's
    // icon. IAA is iOS-only and has no macOS equivalent (P3-2).

    let lfo1RateEffectsPanelID: Int32 = 1

    let lfo2RateEffectsPanelID: Int32 = 2

    let autoPanEffectsPanelID: Int32 = 3

    let delayTimeEffectsPanelID: Int32 = 4

    let lfo1RateTouchPadID: Int32 = 5

    let lfo1RateModWheelID: Int32 = 6

    let lfo2RateModWheelID: Int32 = 7

    let pitchBendID: Int32 = 8

    let arpSeqTempoMultiplierID: Int32 = 9

    var iaaTimer: Timer = Timer()

    public var viewControllers: Set<UpdatableViewController> = []

    fileprivate var started = false
    
    /// Which *layout* is running, not which machine.
    ///
    /// PORT FIX (P4-6): was `UIDevice.current.userInterfaceIdiom`. That was correct
    /// until ADR-023, when the Catalyst idiom became **Optimize Interface for Mac**
    /// and the property started returning `.mac`.
    ///
    /// Upstream uses this in 37 places, all of them asking one question: *iPad layout
    /// or iPhone layout?* Nothing branches on `.mac`, so under `.mac` every one of
    /// those checks took **neither** path. The visible symptom was the bottom panel
    /// never being installed — `switchToChildPanel(_:isOnTop: false)` opens with
    /// `guard conductor.device == .pad`, so hiding the keyboard revealed empty space
    /// where the second panel belongs. The Tunings panel's row metrics and several
    /// keyboard-toggle branches were silently taking the wrong path too.
    ///
    /// We only ever load the iPad storyboards — `SynthOneApp.makeRootViewController`
    /// says so — so this is `.pad` by construction. The Mac idiom changes control
    /// metrics; it does not change which layout we shipped.
    let device: UIUserInterfaceIdiom = .pad  

    /// PORT (P2-4): `Preset(dictionary:defaults:)` takes its per-parameter defaults
    /// rather than reaching into this singleton itself. This is where the preset UI
    /// gets them.
    var presetDefaults: PresetDefaults {
        synth?.presetDefaults ?? { _ in 0 }
    }

    func updateDefaultValues() {
        let parameterCount = S1Parameter.S1ParameterCount.rawValue
        defaultValues = [Double](repeating: 0, count: Int(parameterCount))
        for address in 0..<parameterCount {
            guard let parameter: S1Parameter = S1Parameter(rawValue: address)
            else {
                AKLog("ERROR: S1Parameter enum out of range: \(address)")
                return
        }
        defaultValues[Int(address)] = self.synth.getSynthParameter(parameter)
      }
    }

    func bind(_ control: S1Control,
              to parameter: S1Parameter,
              callback closure: S1ControlCallback? = nil) {
        let binding = (parameter, control)
        bindings.append(binding)
        let control = binding.1
        if let cb = closure {

            // custom closure
            control.setValueCallback = cb(parameter, control)
            control.resetToDefaultCallback = defaultParameter(parameter, control)
        } else {

            // default closure
            control.setValueCallback = changeParameter(parameter, control)
            control.resetToDefaultCallback = defaultParameter(parameter, control)
        }
    }

    var defaultParameter: S1ControlDefaultCallback  = { parameter, control in
        return {
            if sharedInstance.defaultValues.count != S1Parameter.S1ParameterCount.rawValue { return }
            sharedInstance.synth.setSynthParameter(parameter, sharedInstance.defaultValues[Int(parameter.rawValue)])
            sharedInstance.updateSingleUI(parameter, control: nil, value: sharedInstance.defaultValues[Int(parameter.rawValue)])
        }
        } {
        didSet {
            AKLog("WARNING: defaultParameter callback changed")
        }
    }

    var changeParameter: S1ControlCallback  = { parameter, control in
        return { value in
            sharedInstance.synth.setSynthParameter(parameter, value)
            sharedInstance.updateSingleUI(parameter, control: control, value: value)
          }
        } {
        didSet {
            AKLog("WARNING: changeParameter callback changed")
        }
    }

    func updateSingleUI(_ parameter: S1Parameter,
                        control inputControl: S1Control?,
                        value inputValue: Double) {

        // cannot access synth until it is initialized and started
        if !started { return }

        // for every binding of type param
        for binding in bindings where parameter == binding.0 {
            let control = binding.1

            // don't update the control if it is the one performing the callback because it has already been updated
            if let inputControl = inputControl {
                if control !== inputControl {
                    control.value = inputValue
                }
            } else {
                // nil control = global update (i.e., preset change)
                control.value = inputValue
            }
        }

        // View controllers can own objects which are not updated by the bindings scheme.
        // For example, EnvelopesPanel has AKADSRView's which do not conform to S1Control
        for vc in viewControllers {
            vc.updateUI(parameter, control: inputControl, value: inputValue)
        }
    }

    // Call when a global update needs to happen.  i.e., on launch, foreground, and/or when a Preset is loaded.
    func updateAllUI() {
        let parameterCount = S1Parameter.S1ParameterCount.rawValue
        for address in 0..<parameterCount {
            guard let parameter: S1Parameter = S1Parameter(rawValue: address)
                else {
                    AKLog("ERROR: S1Parameter enum out of range: \(address)")
                    return
            }
            let value = self.synth.getSynthParameter(parameter)
            updateSingleUI(parameter, control: nil, value: value)
        }

        // Display Preset Name again
        guard let manager = self.viewControllers.first(
            where: { $0 is Manager }) as? Manager else { return }
        updateDisplayLabel("\(manager.activePreset.position): \(manager.activePreset.name)")
    }

    /// Wire the interface to an audio unit the **host** owns (P4-6).
    ///
    /// The plugin's counterpart to `start(mode:)`. Everything here is about what is
    /// *absent*: no `AVAudioEngine`, no mixer, no output device, no audio session.
    /// The host owns the graph and pulls `internalRenderBlock` on its own thread, and
    /// an AUv3 that touches `AVAudioEngine.outputNode` blocks on device setup for no
    /// reason (ADR-015).
    ///
    /// What the interface still gets: a synth to drive (`S1HostedSynth`), a sustainer
    /// so the on-screen keyboard plays, and the parameter defaults every control reads
    /// as it wires itself up.
    func startHosted(audioUnit: S1AudioUnit) {
        guard !started else {
            AKLog("Conductor.startHosted() called again — already started")
            return
        }

        #if DEBUG
        AKSettings.enableLogging = true
        #endif

        // P2-2: the no-op session. The plugin must never reconfigure the host's.
        S1AudioSessionProvider.current = S1HostedAudioSession()

        _ = AKPolyphonicNode.tuningTable.defaultTuning()

        isHosted = true

        let hosted = S1HostedSynth(audioUnit: audioUnit)
        synth = hosted
        synthNode = nil                     // there is no node, and callers must cope
        audioUnit.s1Delegate = self         // `AKSynthOne` does this for the standalone

        sustainer = SDSustainer(hosted)

        // Created with **no node** — there is nothing to tap, because the host owns the
        // graph — and driven the other way instead: the render thread parks its output
        // in the audio unit's lock-free ring (`S1Scope`) and the plot pulls a snapshot
        // on each display frame. Neither allocating nor dispatching is legal on a render
        // thread, which is why the standalone's `installTap` shape cannot be reused here.
        audioPlotter = AKNodeOutputPlot(nil)
        audioUnit.scopeEnabled = true
        audioPlotter.resume(pulling: { [weak audioUnit] destination, count in
            audioUnit?.copyScopeSamples(destination, count: count) ?? false
        })

        // No `audioRecorder`: it taps the mixer, and recording a plugin's output is
        // the host's job, not ours.

        started = true
        updateDefaultValues()

        // **Host automation moves the controls** (P4-6). `updateSingleUI` with a nil
        // control is the "something other than a control changed this" path the preset
        // loader already uses, so every control bound to the parameter follows.
        //
        // Our own writes are excluded by the originator token inside `observeHostChanges`,
        // which is what stops a host move updating a knob, the knob writing back, and
        // the host recording an automation point the user never made.
        hosted.observeHostChanges { [weak self] parameter, value in
            self?.updateSingleUI(parameter, control: nil, value: value)
        }
    }

    /// How the engine should run once the graph is built.
    enum AudioMode {
        /// Hardware output. What the app uses.
        case realtime
        /// Offline manual rendering — no hardware, no output device.
        ///
        /// **Not just a test convenience.** `AVAudioEngine.outputNode` lazily opens
        /// the hardware output unit, and in a process that cannot get an output
        /// device that blocks for 90 seconds before succeeding anyway (ADR-015).
        /// A headless process that only wants the UI, or an audio unit that renders
        /// through its host, must never touch it.
        case offline
    }

    func start(mode: AudioMode = .realtime) {
        // PORT: upstream is called exactly once, from `AppDelegate`, so it never
        // guarded. Calling it twice builds a second graph on a running engine and
        // AVAudioEngine aborts the process. Cheap insurance for a singleton.
        guard !started else {
            AKLog("Conductor.start() called again — already started")
            return
        }

        #if DEBUG
        AKSettings.enableLogging = true
        AKLog("Logging is ON")
        #else
        AKLog("Logging is OFF")
        #endif

        // Allow audio to play while the iOS device is muted.
        AKSettings.playbackWhileMuted = true

        // PORT: upstream is `try AKSettings.setSession(category: .playAndRecord,
        // with: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])`. The
        // standalone app owns its audio session; the AUv3 must never touch the
        // host's, which is why this goes through the protocol (P2-2).
        S1AudioSessionProvider.current = S1SystemAudioSession()
        do {
            try S1AudioSessionProvider.current.configure()
        } catch {
            AKLog("Could not set session category: \(error)")
        }

        // DEFAULT TUNING
        _ = AKPolyphonicNode.tuningTable.defaultTuning()

        let node = AKSynthOne()
        synthNode = node
        synth = node
        node.delegate = self
        node.rampDuration = 0.0 // Handle ramping internally instead of the ramper hack
        mixer = AKMixer(node)

        // PORT: `AudioKit.output = mixer` then `try AudioKit.start()`. Same two
        // steps against an engine we own rather than a global (ADR-014).
        engine.output = mixer

        sustainer = SDSustainer(node)

        // The plot is created now but not yet tapping: `AKNodeOutputPlot` refuses to
        // tap a node that is not attached to an engine, and `GeneratorsPanelController`
        // force-unwraps this in `viewDidLoad`. It starts drawing in `engineDidStart()`.
        audioPlotter = AKNodeOutputPlot(node)

        started = true

        switch mode {
        case .offline:
            // Deterministic and instant; tests and headless callers rely on the
            // engine being live when `start` returns.
            do {
                try engine.startOfflineRendering()
                engineDidStart()
            } catch {
                AKLog("engine did not start! \(error)")
            }

        case .realtime:
            // ⚠️ **Off the main thread, deliberately.**
            //
            // Starting the engine opens an output device, and device setup is not
            // something a window should wait behind. P3-4 measured a **72 second**
            // launch on the owner's machine — the cause turned out to be the
            // microphone consent dialog that `.playAndRecord` triggered (now fixed
            // in `S1SystemAudioSession`), but the shape of the bug is general: any
            // prompt, any slow or absent device, and the app is a grey rectangle.
            //
            // Nothing in the UI needs the engine *running* — `Manager.viewDidLoad`
            // needs `conductor.synth`, which exists by now. So the window comes up
            // immediately and audio arrives when the device does.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                do {
                    try self.engine.start()
                    #if DEBUG
                    AKLog("engine started (realtime)")
                    #endif
                } catch {
                    AKLog("engine did not start! \(error)")
                }
                DispatchQueue.main.async { self.engineDidStart() }
            }
        }

        // PORT: the Inter-App Audio host-icon listener and `Audiobus.start()` /
        // `setupAudioBusInput()` lived here behind `#if !targetEnvironment(macCatalyst)`.
        // Neither exists on macOS (P3-2).
    }

    /// Everything that can only happen once the graph is live and its nodes are
    /// attached to the engine.
    private func engineDidStart() {
        // Both of these tap a node, and a tap on an unattached node aborts the
        // process rather than failing (P3-1 learned that the hard way).
        audioRecorder = AudioRecorder(node: mixer?.mixerNode)
        audioPlotter?.resume()
    }

    func updateDisplayLabel(_ message: String) {
        let manager = self.viewControllers.first(where: { $0 is Manager }) as? Manager
        manager?.updateDisplay(message)
    }

    func updateDisplayLabel(_ parameter: S1Parameter, value: Double) {
        let headerVC = self.viewControllers.first(where: { $0 is HeaderViewController }) as? HeaderViewController
        headerVC?.updateDisplayLabel(parameter, value: value)
    }

    // MARK: - S1Protocol

    // called by DSP on main thread
    /// The host's tempo changed, and `arpRate` has already followed it in the DSP
    /// (ADR-025). This is the interface catching up (P4-6) — without it the plugin's
    /// tempo control keeps reading 120 while the arpeggiator runs at Logic's tempo,
    /// which is what the owner reported.
    ///
    /// `updateSingleUI` with a nil control is the "something other than a control did
    /// this" path, so every control bound to `arpRate` follows.
    func hostTempoDidChange(_ tempo: Float) {
        updateSingleUI(.arpRate, control: nil, value: Double(tempo))
    }

    /// A control change or program change the host sent (ADR-031). The plugin opens no MIDI
    /// inputs of its own, so this is how the mod wheel, MIDI learn, program change and bank
    /// select still hear a controller.
    func hostMIDIControlDidArrive(_ message: S1HostMIDIMessage) {
        let manager = viewControllers.first(where: { $0 is Manager }) as? Manager
        manager?.receivedHostMIDIControl(message)
    }

    /// The keys host MIDI is holding, for the on-screen keyboard to light (ADR-031).
    func hostHeldKeysDidChange(_ keys: S1HostKeys) {
        let manager = viewControllers.first(where: { $0 is Manager }) as? Manager
        manager?.showHostHeldKeys(keys)
    }

    func dependentParameterDidChange(_ parameter: DependentParameter) {

        // add panels with dependent parameters here

        let effectsPanel = self.viewControllers.first(where: { $0 is EffectsPanelController })
            as? EffectsPanelController
        effectsPanel?.dependentParameterDidChange(parameter)

        let touchPadPanel = self.viewControllers.first(where: { $0 is TouchPadPanelController })
            as? TouchPadPanelController
        touchPadPanel?.dependentParameterDidChange(parameter)

        let sequencerPanel = self.viewControllers.first(where: { $0 is SequencerPanelController }) as? SequencerPanelController
        sequencerPanel?.dependentParameterDidChange(parameter)

        let manager = self.viewControllers.first(where: { $0 is Manager }) as? Manager
        manager?.dependentParameterDidChange(parameter)
    }

    // called by DSP on main thread
    func arpBeatCounterDidChange(_ beat: S1ArpBeatCounter) {
        let sequencerPanel = self.viewControllers.first(where: { $0 is SequencerPanelController })
            as? SequencerPanelController
        sequencerPanel?.updateLED(beatCounter: Int(beat.beatCounter), heldNotes: self.heldNoteCount)
    }

    // called by DSP on main thread
    func heldNotesDidChange(_ heldNotes: HeldNotes) {
        heldNoteCount = Int(heldNotes.heldNotesCount)
    }

    // called by DSP on main thread
    func playingNotesDidChange(_ playingNotes: PlayingNotes) {
        let tuningsPanel = self.viewControllers.first(where: { $0 is TuningsPanelController })
            as? TuningsPanelController
        tuningsPanel?.playingNotesDidChange(playingNotes)
    }

    // Start/Pause the engine (conserve energy by turning background audio off)
    func startEngine(completionHandler: (() -> Void)? = nil) {
        AKLog("engine.isRunning: \(engine.isRunning)")
        if !engine.isRunning {
            do {
                try engine.start()
                AKLog("engine is started.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    completionHandler?()
                }
            } catch {
                AKLog("Unable to start the audio engine. Probably fatal error")
            }

            return
        }
        completionHandler?()
    }

    func stopEngine() {
        engine.pause()
    }

    func deactivateSession() {

        stopEngine()

        do {
            // PORT: `AKSettings.session.setActive(false)` (P2-2).
            try S1AudioSessionProvider.current.setActive(false)
        } catch let error as NSError {
            AKLog("error setting session: " + error.description)
        }

        iaaTimer.invalidate()

        AKLog("deactivated session")
    }
}


extension Conductor: S1TuningTable {

    func setTuningTableNPO(_ npo: Int) {
        
        synth.setTuningTableNPO(npo)
    }

    func setTuningTable(_ frequency: Double, index: Int) {

        synth.setTuningTable(frequency, index: index)
    }

    func getTuningTableFrequency(_ index: Int) -> Double {

        return Double( synth.getTuningTableFrequency(index) )
    }
}
