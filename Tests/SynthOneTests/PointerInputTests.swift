//  P3-5 acceptance: the controls work with one pointer and a typing keyboard.
//
//  Upstream assumes ten fingers on glass. Catalyst has one pointer, so each of
//  these is a deliberate decision rather than a port — see
//  `docs/03-parity-checklist.md`'s Input section.

import XCTest
import UIKit
@testable import SynthOneCore

final class KnobPointerTests: XCTestCase {

    private func makeKnob() -> Knob {
        let knob = Knob(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        knob.range = 0...1
        knob.value = 0.5
        return knob
    }

    /// A plain drag still behaves exactly as it did — this is the control the
    /// parity checklist is protecting, and ⌥ must not have changed it.
    func testDragMovesTheKnob() {
        let knob = makeKnob()
        let before = knob.value
        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: 0))
        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: -40))   // upward = increase
        XCTAssertGreaterThan(knob.value, before)
    }

    /// ⌥ makes the same gesture move the knob less. Without it a cutoff knob
    /// spanning 20 kHz in 200 points cannot be set precisely with a mouse.
    func testOptionDragIsFiner() {
        func travel(fine: Bool) -> Double {
            let knob = makeKnob()
            knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: 0), fine: fine)
            knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: -40), fine: fine)
            return knob.value - 0.5
        }
        let coarse = travel(fine: false)
        let fine = travel(fine: true)
        XCTAssertGreaterThan(coarse, 0)
        XCTAssertGreaterThan(fine, 0, "⌥ should slow the drag, not stop it")
        XCTAssertEqual(fine / coarse, Double(Knob.fineAdjustmentFactor), accuracy: 0.01)
    }

    /// Dragging past either end must clamp rather than wrap or run away.
    func testDragClampsAtBothEnds() {
        let knob = makeKnob()
        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: 0))
        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: -10_000))
        XCTAssertEqual(knob.value, 1.0, accuracy: 0.000_1)

        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: 0))
        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: 10_000))
        XCTAssertEqual(knob.value, 0.0, accuracy: 0.000_1)
    }

    /// Every knob carries a scroll recogniser, and it must be restricted to
    /// indirect scroll events — `allowedTouchTypes = []`. Without that it competes
    /// with the click-drag and the knob jumps.
    func testScrollRecogniserIsScrollOnly() throws {
        let knob = makeKnob()
        let pans = knob.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer } ?? []
        let scroll = try XCTUnwrap(pans.first { !$0.allowedScrollTypesMask.isEmpty },
                                   "no scroll-wheel recogniser on the knob")
        XCTAssertTrue(scroll.allowedTouchTypes.isEmpty,
                      "the scroll recogniser must not also claim pointer drags")
    }

    /// Double-click resets to default — upstream's double-tap, which Catalyst
    /// delivers unchanged. Cheap to assert, and easy to lose.
    func testDoubleClickResetsToDefault() throws {
        let knob = makeKnob()
        var reset = 0
        knob.resetToDefaultCallback = { reset += 1 }
        let taps = knob.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer } ?? []
        XCTAssertTrue(taps.contains { $0.numberOfTapsRequired == 2 })
        knob.handleTap(knob)
        XCTAssertEqual(reset, 1)
    }

    /// `RateKnob` used to override the whole drag routine to change one line, so it
    /// would not have gained ⌥ or the scroll wheel. It overrides only the value
    /// derivation now.
    func testRateKnobInheritsPointerBehaviour() {
        let knob = RateKnob(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        knob.range = 0...1
        knob.value = 0.5
        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: 0), fine: true)
        knob.setPercentagesWithTouchPoint(CGPoint(x: 0, y: -40), fine: true)
        XCTAssertGreaterThan(knob.value, 0.5)
        XCTAssertLessThan(knob.value, 0.6, "⌥ should still be fine on a RateKnob")
    }
}

/// **Owner-reported, twice: `Hide` and `Wheels` do nothing.**
///
/// Every dead control was a `UIButton` subclass; every working one (knobs, the
/// Octave stepper, the toggles) is a `UIView` subclass with its own touch handling.
/// That is the whole diagnosis: under *Optimize Interface for Mac* (ADR-023) UIKit
/// backs `UIButton` with an AppKit cell and **never calls `touchesBegan` on the
/// subclass**, so three control classes went silently dead the moment the idiom
/// changed.
///
/// These tests cannot reproduce that — a host-less test bundle runs in the `.pad`
/// idiom, where `touchesBegan` works fine. What they pin instead is the property
/// that makes the fix idiom-independent: the buttons respond to `.touchUpInside`,
/// which **both** idioms deliver.
final class ButtonActionTests: XCTestCase {

    /// `sendActions(for:)` is **not** usable here: it dispatches through
    /// `UIApplication.shared`, which a host-less test bundle does not have, so the
    /// action silently never runs. So the wiring is asserted structurally and the
    /// behaviour is asserted by calling the action — UIKit's job is delivering the
    /// event, and the point of the fix is that it now uses an event UIKit delivers in
    /// both idioms.
    private func assertWiredForTouchUpInside(_ control: UIControl,
                                             _ name: String,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
        let actions = control.actions(forTarget: control, forControlEvent: .touchUpInside) ?? []
        XCTAssertFalse(actions.isEmpty,
                       "\(name) has no .touchUpInside action — it is dead under the Mac idiom",
                       file: file, line: line)
    }

    /// A button built in code has to work too. P3-5 fixed exactly this in `Knob`,
    /// which wired its gestures only in `init?(coder:)`.
    func testEveryButtonIsWiredForTouchUpInside() {
        assertWiredForTouchUpInside(SynthButton(frame: .zero), "SynthButton")
        assertWiredForTouchUpInside(CallbackButton(frame: .zero), "CallbackButton")
        assertWiredForTouchUpInside(MIDISynthButton(frame: .zero), "MIDISynthButton")
        assertWiredForTouchUpInside(KeyboardShowButton(frame: .zero), "KeyboardShowButton")
        assertWiredForTouchUpInside(PresetUIButton(frame: .zero), "PresetUIButton")
        assertWiredForTouchUpInside(FilterTypeButton(frame: .zero), "FilterTypeButton")
        assertWiredForTouchUpInside(HeaderNavButton(frame: .zero), "HeaderNavButton")
    }

    /// **Owner-reported: the `Mono` button turns blue and its label becomes
    /// unreadable.** Under the Mac idiom UIKit resolves a `UIButton` to the *Mac*
    /// behavioural style and paints the system accent behind a selected button,
    /// overriding the dark background these controls set for themselves. Measured on
    /// a running build: a plain `UIButton` resolves to `.mac`, and `.pad` after the
    /// opt-out.
    ///
    /// The assertion is on `preferredBehavioralStyle` — what we *set* — because
    /// `behavioralStyle` resolves to `.pad` in the test bundle anyway, which would
    /// make this pass whether the fix were there or not.
    @available(macCatalyst 15.0, *)
    func testButtonsOptOutOfMacDrawing() {
        let buttons: [(UIButton, String)] = [
            (SynthButton(frame: .zero), "SynthButton"),
            (MIDISynthButton(frame: .zero), "MIDISynthButton"),
            (KeyboardShowButton(frame: .zero), "KeyboardShowButton"),
            (PresetUIButton(frame: .zero), "PresetUIButton"),
            (CallbackButton(frame: .zero), "CallbackButton"),
            (FilterTypeButton(frame: .zero), "FilterTypeButton"),
            (HeaderNavButton(frame: .zero), "HeaderNavButton")
        ]
        for (button, name) in buttons {
            XCTAssertEqual(button.preferredBehavioralStyle, .pad,
                           "\(name) will be painted with the macOS accent colour over its own "
                           + "background, and its designed title colour will be unreadable")
        }
    }

    /// **Owner-reported: a bordered rectangle around the header wordmark.** ADR-026's
    /// sweep went class by class, and the header's title hit area and its dice are
    /// plain `UIButton`s straight out of the storyboard with no `customClass`, so both
    /// were missed. Under the Mac behavioural style a bare `.system` button is drawn as
    /// a real macOS push button — which turns an invisible hit area into a frame.
    ///
    /// Asserted on the whole header hierarchy rather than on two named outlets, because
    /// naming them is exactly the mistake that let these two through in the first place.
    ///
    /// This cannot be checked by rendering: Mac-style controls need an `NSApplication`,
    /// which a test bundle has none of — `drawHierarchy` throws
    /// `NSInternalInconsistencyException`. So it asserts what we *set*, for the reason
    /// given on `testButtonsOptOutOfMacDrawing` above.
    @available(macCatalyst 15.0, *)
    func testEveryHeaderButtonOptsOutOfMacDrawing() throws {
        let storyboard = UIStoryboard(name: "Header", bundle: Bundle.synthOneCore)
        let controller = try XCTUnwrap(storyboard.instantiateInitialViewController())
        controller.loadViewIfNeeded()

        var offenders: [String] = []
        func walk(_ view: UIView, path: String) {
            if let button = view as? UIButton, button.preferredBehavioralStyle != .pad {
                let name = button.accessibilityIdentifier
                    ?? button.accessibilityLabel
                    ?? button.currentTitle
                    ?? "\(type(of: button))"
                offenders.append("\(path)/\(name)")
            }
            view.subviews.forEach { walk($0, path: path + "/" + String(describing: type(of: view))) }
        }
        walk(controller.view, path: "")

        XCTAssertEqual(offenders, [],
                       "these header buttons will be drawn as macOS push buttons over the "
                       + "panel's own artwork: \(offenders)")
    }

    /// The filter button cycles low-pass / band-pass / high-pass rather than
    /// toggling, so its press has its own behaviour to keep.
    func testFilterTypeButtonCyclesThroughThreeStates() {
        let button = FilterTypeButton(frame: .zero)
        var seen: [Double] = []
        button.setValueCallback = { seen.append($0) }
        for _ in 0..<4 { button.pressed() }
        XCTAssertEqual(seen, [1, 2, 0, 1], "the filter type no longer cycles 0,1,2")
    }

    func testSynthButtonTogglesOncePerPress() {
        let button = SynthButton(frame: .zero)
        var seen: [Double] = []
        button.setValueCallback = { seen.append($0) }

        button.pressed()
        XCTAssertEqual(button.value, 1)
        button.pressed()
        XCTAssertEqual(button.value, 0)

        // **Once per press.** Upstream called the callback from both `touchesBegan`
        // and `touchesEnded`, so every tap ran it twice — for the keyboard toggle
        // that meant animating and saving settings twice.
        XCTAssertEqual(seen, [1, 0])
    }

    func testCallbackButtonFiresOnPress() {
        let button = CallbackButton(frame: .zero)
        var fired = 0
        button.callback = { _ in fired += 1 }
        button.pressed()
        XCTAssertEqual(fired, 1)
    }

    /// MIDI learn intercepts the press instead of toggling — it has to keep doing so
    /// through the new path, or arming a control for MIDI learn would also change it.
    func testMIDILearnInterceptsThePress() {
        let button = MIDISynthButton(frame: .zero)
        var seen: [Double] = []
        button.setValueCallback = { seen.append($0) }

        button.midiLearnMode = true
        button.pressed()
        XCTAssertTrue(button.isMIDILearnActive, "the press did not arm MIDI learn")
        XCTAssertEqual(button.value, 0, "arming MIDI learn must not also toggle the control")
        XCTAssertTrue(seen.isEmpty)

        button.midiLearnMode = false
        button.pressed()
        XCTAssertEqual(button.value, 1)
        XCTAssertEqual(seen, [1])
    }

    /// The keyboard toggle is the one the owner reported. Its callback moves a
    /// constraint by 299 points; what had stopped working was the press reaching it.
    func testTheKeyboardToggleReceivesItsPress() {
        let button = KeyboardShowButton(frame: .zero)
        var seen: [Double] = []
        button.setValueCallback = { seen.append($0) }
        button.pressed()
        XCTAssertEqual(seen, [1], "the Hide button is still not receiving presses")
    }

    /// No `UIButton` subclass may go back to *overriding* `touchesBegan` — the Mac
    /// idiom never calls it, and the failure looks like a UI that ignores clicks.
    func testNoButtonOverridesTouchesBegan() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneCore")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        var offenders: [String] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            // A *class declaration*, not any mention: three view controllers name
            // `UIButton` in an `@IBAction` signature and handle `touchesBegan` on
            // their own view, which is a `UIView` and still receives it.
            let declaresButton = text.contains("class ") && (
                text.range(of: "class [A-Za-z]+: (UIButton|SynthButton)",
                           options: .regularExpression) != nil)
            guard declaresButton else { continue }
            // The declaration, not the word — these files explain the trap in prose.
            if text.contains("func touchesBegan") {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "these are UIButton subclasses overriding touchesBegan, which the Mac "
                      + "idiom never delivers: \(offenders.joined(separator: ", "))")
    }
}

/// **The second casualty of the Mac idiom** (ADR-023), owner-reported as "the
/// keyboard drops down leaving a lot of dead space in the middle".
///
/// `Conductor.device` was `UIDevice.current.userInterfaceIdiom`, and 37 places ask it
/// *iPad layout or iPhone layout?*. Under `.mac` every one of them took neither path.
final class LayoutIdiomTests: XCTestCase {

    private static let started: Bool = { SynthOneApp.start(mode: .offline); return true }()
    override func setUp() { super.setUp(); _ = Self.started }

    /// The layout is the iPad layout, whatever machine it renders on — and a unit
    /// test cannot catch this by accident, because the test bundle *does* report
    /// `.pad`. Only the app and the plugin see `.mac`, which is why it shipped.
    func testTheLayoutIdiomIsPadRegardlessOfTheRunningIdiom() {
        XCTAssertEqual(Conductor.sharedInstance.device, .pad)
    }

    /// It must not be derived from the running idiom again. That is the actual
    /// regression, and it is one word.
    func testDeviceIsNotTakenFromTheRunningIdiom() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneCore/DSP/Conductor.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(text.contains("let device = UIDevice.current.userInterfaceIdiom"),
                       "device is back on the running idiom — under the Mac idiom that is "
                       + "`.mac`, and every `== .pad` check in the app silently fails")
    }

    /// The visible symptom: hiding the keyboard is supposed to *reveal a second
    /// panel*, not empty space. `switchToChildPanel(_:isOnTop:)` refuses to install
    /// one unless the layout idiom is `.pad`.
    func testHidingTheKeyboardInstallsTheBottomPanel() throws {
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        manager.view.layoutIfNeeded()

        let toggle = try XCTUnwrap(manager.keyboardToggle)
        toggle.value = 0
        toggle.setValueCallback(0)
        manager.view.layoutIfNeeded()

        XCTAssertFalse(manager.bottomContainerView.subviews.isEmpty,
                       "the space the keyboard vacated has no panel in it — dead space")
    }
}

/// **The extension would not load at all** — `auval` failed with
/// `OpenAComponent: result: 4099`, and the reason was only in the extension's own
/// crash report (ADR-021): an out-of-range subscript in `Tunings.loadTunings`.
///
/// It indexes three banks that loading is assumed to have produced.
/// `loadTuningsFromDevice` catches its own errors and leaves the array **empty**,
/// which is exactly what a sandboxed AUv3 gets when it tries to read the app's
/// shared folder (ADR-020).
final class TuningBankLoadingTests: XCTestCase {

    /// Whatever loading did, the three banks the rest of the class subscripts have to
    /// exist afterwards.
    func testLoadingAlwaysLeavesTheThreeBanksItSubscripts() {
        let tunings = Tunings()
        let loaded = expectation(description: "tunings loaded")
        tunings.loadTunings { loaded.fulfill() }
        wait(for: [loaded], timeout: 10)

        XCTAssertGreaterThanOrEqual(tunings.tuningBanks.count, 3,
                                    "loadTunings would subscript past the end")
    }

    /// The fallback is the factory set, which is compiled in and therefore readable
    /// inside a sandbox — a plugin showing the curated tunings beats one that will
    /// not load.
    func testTheFallbackIsTheFactorySet() {
        let tunings = Tunings()
        tunings.loadTuningFactoryPresets()
        XCTAssertEqual(tunings.tuningBanks.count, 3)
        XCTAssertFalse(tunings.tuningBanks[0].tunings.isEmpty, "the curated bank is empty")
    }
}

/// P4-6: the Record button, and the raw-idiom reads the Mac idiom broke.
final class RecordingAndIdiomTests: XCTestCase {

    private static let started: Bool = { SynthOneApp.start(mode: .offline); return true }()
    override func setUp() { super.setUp(); _ = Self.started }

    /// Recordings go somewhere a person can find them. The temporary directory is
    /// right on iOS, where a share sheet takes the file away immediately; on a Mac
    /// the system is free to reap it.
    func testRecordingsGoToAFindableFolder() {
        let directory = AudioRecorder.defaultRecordingsDirectory
        XCTAssertNotEqual(directory, FileManager.default.temporaryDirectory,
                          "recordings are still going to a directory the system may reap")
        XCTAssertEqual(directory.lastPathComponent, "Arcade Ruins")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path),
                      "the folder is not created, so the first recording fails")
    }

    /// A new recorder uses it without being told.
    func testANewRecorderWritesThere() {
        XCTAssertEqual(AudioRecorder().directory, AudioRecorder.defaultRecordingsDirectory)
    }

    /// The other half: in the **standalone** the button has to be visible.
    ///
    /// ⚠️ **This test cannot reproduce the bug the owner hit**, and saying so matters.
    /// The first version hid the button when `audioRecorder == nil`. In the app the
    /// engine starts on a background queue and the recorder is built in
    /// `engineDidStart`, *after* the panels load — so the button was hidden and only
    /// its label showed. This suite starts the engine in `.offline` mode, where
    /// `engineDidStart` runs synchronously and the recorder already exists, so the
    /// broken version passes here too. Verified by reverting it.
    ///
    /// What is actually pinned is below: the visibility is not allowed to be derived
    /// from the recorder.
    func testTheRecordButtonIsVisibleInTheStandalone() throws {
        XCTAssertFalse(Conductor.sharedInstance.isHosted, "this suite runs the app's Conductor")

        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.loadViewIfNeeded()
        let generators = manager.generatorsPanel
        generators.loadViewIfNeeded()

        XCTAssertFalse(generators.recordButton.isHidden,
                       "the Record button is hidden in the app — only the label shows")
    }

    /// The condition itself, because the behaviour above cannot catch it: whether a
    /// control exists is a question about *which product this is*, and `isHosted`
    /// answers it deterministically. `audioRecorder` answers "has the engine finished
    /// starting yet", which is a race.
    func testControlVisibilityIsNotDerivedFromTheRecorder() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneCore/Generators/GeneratorsPanelController.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("recordButton.isHidden = conductor.isHosted"),
                      "the Record button's visibility must come from `isHosted`")
        XCTAssertFalse(text.contains("isHidden = (conductor.audioRecorder == nil)"),
                       "that is a race with engine startup, not a product distinction")
    }

    /// **No `UIDevice.current.userInterfaceIdiom` anywhere.** It returns `.mac` under
    /// Optimize Interface for Mac (ADR-023), and every use in this codebase is asking
    /// *iPad layout or iPhone layout?* — a question it stopped answering. Two of the
    /// three uses gated a `UIActivityViewController`'s popover source, which Catalyst
    /// throws without; the third drew microtonal key labels at the iPhone font size.
    func testNothingReadsTheRunningIdiom() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        var offenders: [String] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                if line.contains("UIDevice.current.userInterfaceIdiom") {
                    offenders.append("\(url.lastPathComponent): \(trimmed)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "use `Conductor.device` — the layout idiom — not the running one:\n  "
                      + offenders.joined(separator: "\n  "))
    }
}

final class ComputerKeyboardTests: XCTestCase {

    /// `Manager.viewDidLoad` force-unwraps `conductor.synth`, so the audio side has
    /// to exist before any view is loaded. Offline, so nothing opens a device.
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    /// The layout is GarageBand and Logic's Musical Typing. Checking the anchors a
    /// Mac musician's fingers already know.
    func testLayoutMatchesMusicalTyping() {
        let map = Manager.musicalTypingMap
        XCTAssertEqual(map["a"], 0,  "A is the root")
        XCTAssertEqual(map["w"], 1,  "W is the first black key")
        XCTAssertEqual(map["s"], 2)
        XCTAssertEqual(map["e"], 3)
        XCTAssertEqual(map["d"], 4)
        XCTAssertEqual(map["f"], 5)
        XCTAssertEqual(map["t"], 6)
        XCTAssertEqual(map["g"], 7)
        XCTAssertEqual(map["y"], 8)
        XCTAssertEqual(map["h"], 9)
        XCTAssertEqual(map["u"], 10)
        XCTAssertEqual(map["j"], 11)
        XCTAssertEqual(map["k"], 12, "K is the octave")
    }

    /// Two keys mapping to one semitone, or a note key doubling as a transport key,
    /// would be silent and maddening.
    func testNoKeyDoesTwoThings() {
        let map = Manager.musicalTypingMap
        XCTAssertEqual(Set(map.values).count, map.count, "two keys share a semitone")

        let transport = [Manager.octaveDownKey, Manager.octaveUpKey,
                         Manager.velocityDownKey, Manager.velocityUpKey]
        XCTAssertEqual(Set(transport).count, 4, "two transport keys are the same key")
        for key in transport {
            XCTAssertNil(map[key], "\(key) is both a note and a transport control")
        }
    }

    /// A loaded `Manager` with its view realised, so the outlets are connected.
    private func makeManager() throws -> Manager {
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(x: 0, y: 0, width: 1_024, height: 768)
        manager.loadViewIfNeeded()
        manager.view.layoutIfNeeded()
        return manager
    }

    /// Semitone zero is middle C at the default octave.
    func testNoteNumbersAreCorrectAtTheDefaultOctave() throws {
        let manager = try makeManager()
        XCTAssertEqual(manager.typedOctave, 0)
        XCTAssertEqual(manager.typedNoteNumber(forSemitone: 0), 60, "middle C")
        XCTAssertEqual(manager.typedNoteNumber(forSemitone: 12), 72)
    }

    /// **The `Octave:` stepper is what the typing keyboard plays in.**
    ///
    /// P3-5 first gave typing its own private octave, so the app had two: the
    /// stepper moved the on-screen keyboard while `Z`/`X` moved what you actually
    /// played, and the visible control appeared to do nothing. The owner reported
    /// exactly that. On the iPad there is only one octave, because touch is the only
    /// input; there has to be only one here too.
    func testOctaveStepperChangesWhatTypingPlays() throws {
        let manager = try makeManager()
        let stepper = try XCTUnwrap(manager.octaveStepper)

        stepper.value = 2
        stepper.setValueCallback(stepper.value)
        XCTAssertEqual(manager.typedOctave, 1)
        XCTAssertEqual(manager.typedNoteNumber(forSemitone: 0), 72, "one octave up from middle C")

        stepper.value = 0
        stepper.setValueCallback(stepper.value)
        XCTAssertEqual(manager.typedNoteNumber(forSemitone: 0), 48, "one octave down")
    }

    /// And it works the other way: `Z`/`X` move the stepper, so the visible control
    /// and the on-screen keyboard both follow the typing keyboard.
    func testTypingOctaveKeysMoveTheStepperAndKeyboard() throws {
        let manager = try makeManager()
        let stepper = try XCTUnwrap(manager.octaveStepper)
        let before = stepper.value

        manager.typedOctave += 1
        XCTAssertEqual(stepper.value, before + 1, "X should move the visible control")
        XCTAssertEqual(manager.keyboardView.firstOctave, Int(stepper.value) + 2,
                       "the on-screen keyboard should follow too")
    }

    /// Shifting the octave clamps to the stepper's own range rather than running off
    /// the end of MIDI.
    func testOctaveClampsToTheStepperRange() throws {
        let manager = try makeManager()
        let stepper = try XCTUnwrap(manager.octaveStepper)

        for _ in 0..<20 { manager.typedOctave += 1 }
        XCTAssertEqual(stepper.value, stepper.maxValue)
        XCTAssertLessThanOrEqual(manager.typedNoteNumber(forSemitone: 12), 127)

        for _ in 0..<40 { manager.typedOctave -= 1 }
        XCTAssertEqual(stepper.value, stepper.minValue)
        XCTAssertGreaterThanOrEqual(manager.typedNoteNumber(forSemitone: 0), 0)
    }

    // MARK: - The octave control and MIDI input

    /// Lets `receivedMIDINoteOff`'s `DispatchQueue.main.async` run.
    private func drainMainQueue() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func setOctave(_ manager: Manager, _ value: Double) throws {
        let stepper = try XCTUnwrap(manager.octaveStepper)
        stepper.value = value
        stepper.setValueCallback(stepper.value)
    }

    /// **The owner's requirement, 2026-09-09.** One control called "Octave": move it
    /// up one and the on-screen keys relabel C2 to C3 *and* a MIDI keyboard's C2
    /// plays C3.
    ///
    /// Upstream deliberately did the opposite — `Octave:` moved only the on-screen
    /// keyboard, on the reasoning that a MIDI note carries its own pitch. That holds
    /// on an iPad, where touch is the only input; on a Mac it leaves a control that
    /// two of the three input paths ignore.
    func testMIDINotesFollowTheOctaveControl() throws {
        let manager = try makeManager()

        try setOctave(manager, Double(Manager.typedOctaveOrigin))   // neutral
        manager.receivedMIDINoteOn(noteNumber: 60, velocity: 100, channel: 0)
        XCTAssertTrue(manager.notesFromMIDI.contains(60), "neutral octave must not shift anything")

        manager.receivedMIDINoteOff(noteNumber: 60, velocity: 0, channel: 0)
        drainMainQueue()

        try setOctave(manager, Double(Manager.typedOctaveOrigin + 1))  // up one octave
        manager.receivedMIDINoteOn(noteNumber: 60, velocity: 100, channel: 0)
        XCTAssertTrue(manager.notesFromMIDI.contains(72),
                      "MIDI 60 an octave up should sound 72, got \(manager.notesFromMIDI)")
        XCTAssertFalse(manager.notesFromMIDI.contains(60))
    }

    /// The typing keyboard and MIDI move together by construction — `midiOctaveShift`
    /// is derived from `typedOctave` rather than kept alongside it.
    func testTypingAndMIDIShiftByTheSameAmount() throws {
        let manager = try makeManager()
        for value in [-2.0, 0.0, 1.0, 3.0] {
            try setOctave(manager, value)
            XCTAssertEqual(manager.midiOctaveShift, manager.typedOctave * 12)
            XCTAssertEqual(manager.typedNoteNumber(forSemitone: 0),
                           MIDINoteNumber(60 + manager.midiOctaveShift))
        }
    }

    /// **The stuck-note case.** A note-off has to release the note its note-on
    /// started, not the note that number would start *now* — otherwise nudging the
    /// octave with a key held leaves it sounding forever.
    func testMovingTheOctaveWhileAKeyIsHeldStillReleasesTheNote() throws {
        let manager = try makeManager()
        try setOctave(manager, Double(Manager.typedOctaveOrigin))

        manager.receivedMIDINoteOn(noteNumber: 60, velocity: 100, channel: 0)
        XCTAssertTrue(manager.notesFromMIDI.contains(60))

        try setOctave(manager, Double(Manager.typedOctaveOrigin + 2))   // while held
        manager.receivedMIDINoteOff(noteNumber: 60, velocity: 0, channel: 0)
        drainMainQueue()

        XCTAssertTrue(manager.notesFromMIDI.isEmpty,
                      "the held note was left sounding: \(manager.notesFromMIDI)")
    }

    /// A shift that pushes a note past 127 drops it rather than clamping. Clamping
    /// would pile several keys onto one note, and `notesFromMIDI` is a *set* — so
    /// releasing one of them would silence the others.
    func testANoteShiftedOutOfRangeIsDroppedNotClamped() throws {
        let manager = try makeManager()
        let stepper = try XCTUnwrap(manager.octaveStepper)
        try setOctave(manager, stepper.maxValue)

        let tooHigh = MIDINoteNumber(127 - manager.midiOctaveShift + 1)
        manager.receivedMIDINoteOn(noteNumber: tooHigh, velocity: 100, channel: 0)
        XCTAssertTrue(manager.notesFromMIDI.isEmpty, "expected the note to be dropped")
        XCTAssertFalse(manager.notesFromMIDI.contains(127), "it was clamped onto 127")

        // And the note just below it still plays, so the boundary is not off by one.
        manager.receivedMIDINoteOn(noteNumber: tooHigh - 1, velocity: 100, channel: 0)
        XCTAssertTrue(manager.notesFromMIDI.contains(127))
    }

    /// Default velocity is musical rather than full-scale, and the C/V steps stay
    /// inside 1…127.
    func testVelocityDefaultAndBounds() throws {
        let manager = try makeManager()
        XCTAssertEqual(manager.typedVelocity, 100)
        XCTAssertGreaterThan(manager.typedVelocity, 0)
        XCTAssertLessThanOrEqual(manager.typedVelocity, 127)
    }
}
