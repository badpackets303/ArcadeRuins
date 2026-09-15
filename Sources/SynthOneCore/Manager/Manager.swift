//
//  Manager.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 7/8/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import S1Support
import UIKit


protocol EmbeddedViewsDelegate: AnyObject {

    func switchToChildPanel(_ newView: ChildPanel, isOnTop: Bool)

}

public class Manager: UpdatableViewController, AudioRecorderFileDelegate {

    // P3-5, computer-keyboard note entry. Stored here because a Swift extension
    // cannot add stored properties; the behaviour is in
    // `Manager+ComputerKeyboard.swift`.

    /// Keys currently held down, by character. Also what suppresses key auto-repeat.
    var typedNotes: Set<String> = []
    /// Velocity for typed notes, changed with C and V.
    var typedVelocity = 100

    @IBOutlet weak var topContainerView: UIView!

    @IBOutlet weak var bottomContainerView: UIView!

    @IBOutlet weak var keyboardView: KeyboardView!

    @IBOutlet var keyboardTopConstraint: NSLayoutConstraint!

    @IBOutlet var keyboardLeftConstraint: NSLayoutConstraint!

    @IBOutlet var keyboardRightConstraint: NSLayoutConstraint!

    @IBOutlet var topPanelheight: NSLayoutConstraint!

    @IBOutlet weak var midiButton: SynthButton!

    @IBOutlet weak var holdButton: MIDISynthButton!

    @IBOutlet weak var monoButton: MIDISynthButton!

	@IBOutlet weak var keyboardToggle: SynthButton!

    @IBOutlet weak var octaveStepper: Stepper!

    @IBOutlet weak var transposeStepper: MIDIStepper!

    @IBOutlet weak var configKeyboardButton: SynthButton!

    @IBOutlet weak var bluetoothButton: AKBluetoothMIDIButton!

    @IBOutlet weak var modWheelSettings: SynthButton!

    @IBOutlet weak var midiLearnToggle: SynthButton!

    @IBOutlet weak var pitchBend: AKVerticalPad!

    @IBOutlet weak var modWheelPad: AKVerticalPad!
    
    @IBOutlet weak var linkButton: AKLinkButton!

    weak var embeddedViewsDelegate: EmbeddedViewsDelegate?

    /// PORT (P6, ADR-045): set when the desktop layout has been built over this view.
    /// Nil in the classic layout and in the test bundle's storyboard walks.
    var desktopLayout: S1DesktopLayout?

    /// PORT (P6-6, P8-0): View ▸ Preset Browser (⌥⌘P), Escape and Search Presets (⌘F) reach these through the
    /// responder chain; the desktop layout adds them as key commands too.
    @objc func desktopTogglePresets(_ sender: Any?) { desktopLayout?.togglePresetPanel() }
    @objc func desktopClosePresets(_ sender: Any?) { desktopLayout?.setPresetPanelVisible(false) }
    @objc func desktopSearchPresets(_ sender: Any?) { desktopLayout?.searchPresets() }

    var topChildPanel: ChildPanel?

    var bottomChildPanel: ChildPanel?

    var prevBottomChildPanel: ChildPanel?

    var isPresetsDisplayed: Bool = false

    var activePreset = Preset()

    var midiInputs = [MIDIInput]()

    var notesFromMIDI = Set<MIDINoteNumber>()

    /// Incoming MIDI note number -> the note actually sounded, for notes currently
    /// held. The `Octave:` control transposes MIDI input, so a note-off has to undo
    /// the *same* shift its note-on applied — otherwise moving the octave while a key
    /// is down leaves the note stuck on. See `Manager+MIDIListener`.
    var soundingMIDINotes: [MIDINoteNumber: MIDINoteNumber] = [:]

    var appSettings = AppSettings()

    var isDevView = false

    var sustainMode = false

    var pcJustTriggered = false

    var midiControls = [MIDILearnable]()

    var signedMailingList = false

    let mainStoryboard = UIStoryboard(name: "Main", bundle: .synthOneCore)

    var isPhoneX = false

    var isLoaded = false

    // Python code to generate whiteKeysOnlyMap:
    // middleC = [60,60,61,61,62,63,63,64,64,65,65,66]
    // delta = [x - 60 for x in middleC]
    // w = [((60+7*math.floor((x-60)/12)) + delta[(x-60)%12]) for x in range(0,128) ]
    // retVal = ""
    // for x in range(0,128):
    //    retVal += str((60+7*math.floor((x-60)/12)) + delta[(x-60)%12])
    //    retVal += ", "
    // print(retVal) # use this in Swift array declaration
    let whiteKeysOnlyMap: [MIDINoteNumber] = [
        25, 25, 26, 26, 27, 28, 28, 29, 29, 30, 30, 31,
        32, 32, 33, 33, 34, 35, 35, 36, 36, 37, 37, 38,
        39, 39, 40, 40, 41, 42, 42, 43, 43, 44, 44, 45,
        46, 46, 47, 47, 48, 49, 49, 50, 50, 51, 51, 52,
        53, 53, 54, 54, 55, 56, 56, 57, 57, 58, 58, 59,
        60, 60, 61, 61, 62, 63, 63, 64, 64, 65, 65, 66,
        67, 67, 68, 68, 69, 70, 70, 71, 71, 72, 72, 73,
        74, 74, 75, 75, 76, 77, 77, 78, 78, 79, 79, 80,
        81, 81, 82, 82, 83, 84, 84, 85, 85, 86, 86, 87,
        88, 88, 89, 89, 90, 91, 91, 92, 92, 93, 93, 94,
        95, 95, 96, 96, 97, 98, 98, 99
    ]

    // AudioBus
    // PORT: the Inter-App Audio host-icon listener — iOS-only (P3-2).

    // MARK: - Define child view controllers
    lazy var envelopesPanel: EnvelopesPanelController = {
        let envelopesStoryboard = UIStoryboard(name: "Envelopes", bundle: .synthOneCore)
        var vcName = ChildPanel.envelopes.identifier()
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        return envelopesStoryboard.instantiateViewController(withIdentifier: vcName) as! EnvelopesPanelController
    }()

    lazy var generatorsPanel: GeneratorsPanelController = {
        let generatorsStoryboard = UIStoryboard(name: "Generators", bundle: .synthOneCore)
        var vcName = ChildPanel.generators.identifier()
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        return generatorsStoryboard.instantiateViewController(withIdentifier: vcName) as! GeneratorsPanelController
    }()

    lazy var devViewController: DevViewController = {
        let devStoryboard = UIStoryboard(name: "Dev", bundle: .synthOneCore)
        var vcName = "Dev"
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        let viewController = devStoryboard.instantiateViewController(withIdentifier: vcName) as! DevViewController
        viewController.delegate = self
        return viewController
    }()

    lazy var touchPadPanel: TouchPadPanelController = {
        let touchPadStoryboard = UIStoryboard(name: "TouchPad", bundle: .synthOneCore)
        var vcName = ChildPanel.touchPad.identifier()
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        return touchPadStoryboard.instantiateViewController(withIdentifier: vcName) as! TouchPadPanelController
    }()

    lazy var fxPanel: EffectsPanelController = {
        let effectsStoryboard = UIStoryboard(name: "Effects", bundle: .synthOneCore)
        var vcName = ChildPanel.effects.identifier()
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        return effectsStoryboard.instantiateViewController(withIdentifier: vcName) as! EffectsPanelController
    }()

    lazy var sequencerPanel: SequencerPanelController = {
        let sequencerStoryboard = UIStoryboard(name: "Sequencer", bundle: .synthOneCore)
        var vcName = ChildPanel.sequencer.identifier()
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        return sequencerStoryboard.instantiateViewController(withIdentifier: vcName) as! SequencerPanelController
    }()

    lazy var tuningsPanel: TuningsPanelController = {
        let tuningsStoryboard = UIStoryboard(name: "Tunings", bundle: .synthOneCore)
        var vcName = ChildPanel.tunings.identifier()
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        return tuningsStoryboard.instantiateViewController(withIdentifier: vcName) as! TuningsPanelController
    }()

    lazy var presetsViewController: PresetsViewController = {
        let presetsStoryboard = UIStoryboard(name: "Presets", bundle: .synthOneCore)
        var vcName = "Presets"
        if conductor.device == .phone { vcName = "iPhone" + vcName }
        return presetsStoryboard.instantiateViewController(withIdentifier: vcName) as! PresetsViewController
    }()

    // swiftlint:enable force_cast

    // MARK: - viewDidLoad

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let modelName = UIDevice.current.modelName
        
        // Conductor start
        let s = conductor.synth!
        keyboardView?.delegate = self
        keyboardView?.polyphonicMode = s.getSynthParameter(.isMono) < 1 ? true : false

        // Set Header as Delegate
        if let headerVC = self.children.first as? HeaderViewController {
            headerVC.delegate = self
            headerVC.headerDelegate = self
        }

        // Set AKKeyboard octave range
        octaveStepper.minValue = -2
        octaveStepper.maxValue = 4

        /// transpose
        transposeStepper.minValue = s.getMinimum(.transpose)
        transposeStepper.maxValue = s.getMaximum(.transpose)

        // Make bluetooth button look pretty
        bluetoothButton.centerPopupIn(view: view)
        bluetoothButton.layer.cornerRadius = 2
        bluetoothButton.layer.borderWidth = 1

        #if ABLETON_ENABLED_1
        print("GOT HERE ABLETON")
        linkButton.centerPopupIn(view: view)
        #endif

        // Setup Callbacks
        setupCallbacks()

        // Load Presets
        displayPresetsController()

        // PORT FIX (ADR-031): only the standalone opens MIDI inputs. A plugin takes its MIDI
        // from the host, through the render block. Measured in Logic on 2026-09-10, doing both
        // played every key twice — as two different notes — and let a plugin on an unselected
        // track answer a hardware keyboard. `isHosted` is set by `startHosted`, which runs
        // before this view loads.
        if conductor.isHosted {
            syncHostMIDISettings()
        } else {
            DispatchQueue.global(qos: .userInteractive).async {
                S1MIDI.shared.createVirtualInputPort(95_433, name: "AudioKit Synth One")
                S1MIDI.shared.openOutput(name: "AudioKit Synth One")
            }
            S1MIDI.shared.addListener(self)
        }

        // Pre-load views and Set initial subviews
        switchToChildPanel(.sequencer, isOnTop: true)
        switchToChildPanel(.sequencer, isOnTop: false)
        switchToChildPanel(.effects, isOnTop: true)
        switchToChildPanel(.touchPad, isOnTop: true)
        switchToChildPanel(.effects, isOnTop: true)
        switchToChildPanel(.envelopes, isOnTop: true)
        switchToChildPanel(.effects, isOnTop: true)
        switchToChildPanel(.generators, isOnTop: true)
        
        // Pre-load dev panel view
        add(asChildViewController: devViewController, isTopContainer: true)
        devViewController.view.removeFromSuperview()

        // IAA MIDI
        #if !targetEnvironment(macCatalyst)
        var callbackStruct = AudioOutputUnitMIDICallbacks(
            userData: nil,
            MIDIEventProc: { (_, status, data1, data2, _) in
                S1MIDI.shared.sendMessage([MIDIByte(status), MIDIByte(data1), MIDIByte(data2)])
            },
            MIDISysExProc: { (_, _, _) in
                print("Not handling sysex")
            }
        )

        guard let outputAudioUnit = AudioKit.engine.outputNode.audioUnit else {
            AKLog("ERROR: can't create outputAudioUnit")
            return
        }

        let connectIAAMDI = AudioUnitSetProperty(outputAudioUnit,
                                                 kAudioOutputUnitProperty_MIDICallbacks,
                                                 kAudioUnitScope_Global,
                                                 0,
                                                 &callbackStruct,
                                                 UInt32(MemoryLayout<AudioOutputUnitMIDICallbacks>.size))
        if connectIAAMDI != 0 {
            AKLog("Cannot create outpoutAudioUnit of type: kAudioOutputUnitProperty_MIDICallbacks")
        }
        #endif
		holdButton.accessibilityValue = self.keyboardView.holdMode ?
			NSLocalizedString("On", comment: "On") :
			NSLocalizedString("Off", comment: "Off")

		monoButton.accessibilityValue = self.keyboardView.polyphonicMode ?
			NSLocalizedString("Off", comment: "Off") :
			NSLocalizedString("On", comment: "On")
        
        isPhoneX = modelName == "iPhone X" || modelName == "iPhone XS" || modelName == "iPhone XS Max" || modelName == "iPhone XR" || modelName == "iPhone 11" || modelName == "iPhone 11 Pro" || modelName == "iPhone 11 Pro Max"
        if isPhoneX {
            self.keyboardLeftConstraint?.constant = 72.5
            self.keyboardRightConstraint?.constant = 72.5
        }

        // PORT (ADR-039): the Mac has no Show/Hide. The keyboard is always the compact strip
        // under the panels (ADR-035), so the button comes off the toolbar. Its callback stays,
        // and still runs at launch with 0, as upstream's does.
        if conductor.device == .pad {
            keyboardToggle.isHidden = true
        }

       // PORT (P3-2): upstream is
       // `Audiobus.client?.controller.stateIODelegate = self` followed by
       // `conductor.audioBusMidiDelegate = self`. Audiobus is iOS-only; the macOS
       // implementation of this protocol ignores the registration.
       S1PlatformServicesProvider.current.registerInterAppHostStateDelegate(self)
    }
    
    // Hide home bar on newer iPhones/iPad
    override public var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // P3-5: claim the typing keyboard for note entry.
        startComputerKeyboard()
        guard !isLoaded else { return }

        // Load App Settings
        if Disk.exists("settings.json", in: .settings) {   // PORT (ADR-041): each product's own
            loadSettingsFromDevice()
        } else {
            setDefaultsFromAppSettings()
            saveAppSettings()
        }

        // Set Mailing List Button
        signedMailingList = appSettings.signedMailingList
        if let headerVC = self.children.first as? HeaderViewController {
            headerVC.updateMailingListButton(appSettings.signedMailingList)
        }

        // Load Banks
        if Disk.exists("banks.json", in: .documents) {
            loadBankSettings()
        } else {
            createInitBanks()
        }

        // Check preset versions
        let currentPresetVersion = AppSettings().presetsVersion
        if appSettings.presetsVersion < currentPresetVersion {
            if conductor.device == .pad {
                if appSettings.presetsVersion < 1.24 && !appSettings.firstRun {
                    performSegue(withIdentifier: "SegueToApps", sender: nil) 
                }
                if appSettings.presetsVersion < 1.3 && !appSettings.firstRun {
                    performSegue(withIdentifier: "SegueToFM", sender: nil)
                }
            }
            
            // Check for Device Type, set buffer to 1024 for iPad 4
            if appSettings.presetsVersion < 1.25 {
                if UIDevice.current.modelName == "iPad 4" {
                    AKSettings.bufferLength = .veryLong
                    try? AVAudioSession.sharedInstance().setPreferredIOBufferDuration(AKSettings.bufferLength.duration)
                }
                if conductor.device == .pad {
                    displayAlertController("iPhone version! 🎉", message: "We've been working hard for you. Synth One is now available as a Universal app on the iPhone. Free & Open-source. Thank you. 🙏")
                }
            }
            
            // upgrade presets
            presetsViewController.upgradePresets()
            
            // Save appSettings
            appSettings.presetsVersion = currentPresetVersion
            saveAppSettings()
        }

        presetsViewController.loadBanks()

        // Set Initial Preset from last used Bank & Preset
        self.presetsViewController.didSelectBank(index: self.appSettings.currentBankIndex)
        self.presetsViewController.didSelectPreset(index: self.appSettings.currentPresetIndex)

        // Show email list if first run
        if appSettings.firstRun && !appSettings.signedMailingList && Private.MailChimpAPIKey != "***REMOVED***" && conductor.device != .phone {
            performSegue(withIdentifier: "SegueToMailingList", sender: self)
        }
        
        // Check for Device Type
        let modelName = UIDevice.current.modelName
        if appSettings.firstRun && (conductor.device == .phone || modelName == "iPad 4") {
            AKSettings.bufferLength = .veryLong
            try? AVAudioSession.sharedInstance().setPreferredIOBufferDuration(AKSettings.bufferLength.duration)
        }
        
        if appSettings.firstRun && (modelName == "iPhone SE" || modelName == "iPhone 5s" || modelName == "iPhone 5c") {
            iPhoneRequirementWarning()
        }
        
        if appSettings.firstRun && (modelName == "iPhone 6" || modelName == "iPhone 6s" || modelName == "iPhone 7" || modelName == "iPhone 8" || modelName == "iPhone 6 Plus" || modelName == "iPhone 6s Plus" || modelName == "iPhone 7 Plus" || modelName == "iPhone 8 Plus") {
            if UIScreen.main.nativeScale != UIScreen.main.scale {
                iPhoneZoomWarning()
            }
        }

        // iPhone show welcome screen
        if appSettings.firstRun && conductor.device == .phone { 
           performSegue(withIdentifier: "SegueToWelcome", sender: self)
        }
    
        // PORT (ADR-042): upstream's launch-count prompts are gone, at the owner's request.
        // They were a "please give a Great rating" alert on the 5th launch, an App Store
        // review request every 50th, the "Synth One + Share One!" card every 7th and a push
        // notification request on the 9th and every 75th. There is no App Store listing
        // (ADR-005), the card's video is AudioKit's, its Share crashes in the plugin, and
        // push was already compiled out on Catalyst. The storyboards and the functions stay:
        // About and the header still reach them. `launches` still counts.

        // Keyboard show or hide on launch
        if appSettings.firstRun && conductor.device == .phone { appSettings.showKeyboard = 1.0 }
        keyboardToggle.value = appSettings.showKeyboard

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            self.keyboardToggle.setValueCallback(self.appSettings.showKeyboard)
        }
        
        // Increase number of launches
        appSettings.launches += 1
        appSettings.firstRun = false
        saveAppSettingValues()

        appendMIDIControls(fromViewController: generatorsPanel)
        appendMIDIControls(fromViewController: envelopesPanel)
        appendMIDIControls(fromViewController: fxPanel)
        appendMIDIControls(fromViewController: sequencerPanel)
        appendMIDIControls(fromViewController: devViewController)
        appendMIDIControls(fromViewController: tuningsPanel)
        appendMIDIControl(transposeStepper)
        appendMIDIControl(holdButton)
        appendMIDIControl(monoButton)

        setupLinkStuff()
        conductor.audioRecorder?.fileDelegate = self
        isLoaded = true
    }

    // Make edge gestures more responsive
    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return UIRectEdge.all
    }

    private func appendMIDIControls(fromViewController controller: UIViewController) {
        // PORT (P6, ADR-045): in the desktop layout the panel's controls have moved out
        // of the panel's view into the desktop sections; the layout knows where.
        let views = desktopLayout?.controlViews(of: controller) ?? controller.view.subviews
        for view in views {
            guard let midiControl = view as? MIDILearnable else { continue }
            midiControl.addHotspot()
            midiControls.append(midiControl)
        }
    }

    private func appendMIDIControl(_ control: MIDILearnable) {
        control.addHotspot()
        midiControls.append(control)
    }


    func stopAllNotes() {
        self.keyboardView.allNotesOff()
        conductor.synth.stopAllNotes()
    }

    override func updateUI(_ parameter: S1Parameter, control inputControl: S1Control?, value: Double) {

        // Even though isMono is a dsp parameter it needs special treatment because this vc's state depends on it
        guard let s = conductor.synth else {
            AKLog("ParentViewController can't update global UI because synth is not instantiated")
            return
        }

        // PORT (P6-2, ADR-045): readouts that depend on other parameters (tempo sync, tempo,
        // the dependent rates) and the filter-type picker follow the parameter, not a knob.
        desktopLayout?.parameterDidChange(parameter, value: value)

        let isMono = s.getSynthParameter(.isMono)
        if isMono != monoButton.value {
            monoButton.value = isMono
            self.keyboardView.polyphonicMode = (isMono == 0) ? true : false
        }
        
        if parameter == .cutoff {
            if inputControl === modWheelPad || activePreset.modWheelRouting != 0 {
                return
            }
            // PORT FIX (ADR-030): upstream placed the wheel at
            // `1 - ln(value / 40) / ln(7600 / 40)`, which is not the inverse of what the
            // wheel itself writes in `Manager+callbacks.swift` —
            // `3 × scaleRangeLog2(1 - wheel, 120…7600)`. So a cutoff the wheel had just
            // set put the wheel somewhere else: dragged to the top (360 Hz), it was redrawn
            // at 0.58. Upstream only reached this from the cutoff knob, but in the plugin
            // every host echo and automation pass does, and the owner saw the wheel "not
            // remain at the position it's dragged to". This is the exact inverse.
            let mmin = 120.0
            let mmax = 7_600.0
            let scaledValue01 = (0...1).clamp(1 - log2(value / 3 / mmin) / log2(mmax / mmin))
            modWheelPad.setVerticalValue01(scaledValue01)
        }
        if parameter == .transpose {
            transposeStepper.value = Double(activePreset.transpose)
        }
    }

    func dependentParameterDidChange(_ dependentParameter: DependentParameter) {
        desktopLayout?.dependentParameterDidChange(dependentParameter.parameter)   // PORT (P6-2)
        switch dependentParameter.parameter {

        case .lfo1Rate:
            if dependentParameter.payload == conductor.lfo1RateModWheelID {
                return
            }
            if activePreset.modWheelRouting == 1 {
                modWheelPad.setVerticalValue01(Double(dependentParameter.normalizedValue))
            }

        case .lfo2Rate:
            if dependentParameter.payload == conductor.lfo2RateModWheelID {
                return
            }
            if activePreset.modWheelRouting == 2 {
                modWheelPad.setVerticalValue01(Double(dependentParameter.normalizedValue))
            }

        case .pitchbend:
            if dependentParameter.payload == conductor.pitchBendID {
                return
            }
            pitchBend.setVerticalValue01(Double(dependentParameter.normalizedValue))

        default:
            _ = 0
        }
    }

    // PORT: upstream takes an `AKAudioFile`, and uses nothing but its `url`.
    // `S1NodeRecorder` hands over the URL directly, so `AKAudioFile` never had to be
    // ported at all (P2-3).
    public func didFinishRecording(url fileURL: URL) {
        // PORT (P4-6): upstream presents a `UIActivityViewController` — the iOS
        // "share this file" idiom. Two reasons it is wrong here.
        //
        // On a Mac the expectation is a file you can find, not a share sheet. And on
        // Catalyst that controller **throws** unless its popover has a source rect;
        // upstream sets one only when the idiom is `.pad`, which stopped being true
        // at ADR-023 — so stopping a recording would have crashed the app.
        //
        // Opening the containing folder reveals it in Finder, which is the native
        // answer and cannot fail the same way.
        conductor.updateDisplayLabel("Recorded \(fileURL.lastPathComponent)")
        UIApplication.shared.open(fileURL.deletingLastPathComponent())
    }
}
