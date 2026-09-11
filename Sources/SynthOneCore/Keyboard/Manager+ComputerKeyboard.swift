//  Computer-keyboard note entry (P3-5).
//
//  **New, not ported.** Upstream is an iPad app: you play it with ten fingers on
//  glass. A desktop synth is expected to be playable from the typing keyboard, and
//  under Mac Catalyst there is exactly one pointer — so without this, chords can
//  only be played by turning Hold on and clicking notes one at a time.
//
//  The layout is GarageBand and Logic's **Musical Typing**, deliberately: this is a
//  Mac synth, and its users already have that map in their fingers.
//
//      W E   T Y U        black keys
//     A S D F G H J K     white keys, C…C
//
//  `Z`/`X` shift the octave, `C`/`V` change velocity — also Musical Typing's.
//
//  Notes are routed through `keyboardView.pressAdded` / `pressRemoved`, the same
//  path MIDI input and the on-screen keyboard use, so hold mode, mono mode and the
//  key highlighting all behave identically whatever played the note.

import UIKit
import S1Support

extension Manager {

    /// Semitone offset from the base note for each key. Nil for keys that are not
    /// notes, so a stray letter does nothing rather than playing something.
    static let musicalTypingMap: [String: Int] = [
        "a": 0,  "w": 1,  "s": 2,  "e": 3,  "d": 4,  "f": 5,  "t": 6,
        "g": 7,  "y": 8,  "h": 9,  "u": 10, "j": 11, "k": 12, "o": 13,
        "l": 14, "p": 15, ";": 16, "'": 17
    ]

    static let octaveDownKey = "z"
    static let octaveUpKey = "x"
    static let velocityDownKey = "c"
    static let velocityUpKey = "v"

    /// Must be first responder to see key presses at all.
    open override var canBecomeFirstResponder: Bool { true }

    /// Called from `Manager.viewDidAppear`. Claims the keyboard once the view is on
    /// screen.
    ///
    /// A text field taking over — renaming a preset, importing a Scala file — makes
    /// itself first responder and gets the keys instead, which is exactly right.
    func startComputerKeyboard() {
        becomeFirstResponder()
    }

    /// Anything still held would sound forever.
    func stopComputerKeyboard() {
        releaseAllTypedNotes()
        resignFirstResponder()
    }

    open override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            // Let ⌘-shortcuts and anything modified through untouched — otherwise
            // ⌘S would play a D.
            guard key.modifierFlags.isDisjoint(with: [.command, .control, .alternate]) else { continue }
            if handle(key: key.charactersIgnoringModifiers.lowercased(), isDown: true) { handled = true }
        }
        // Anything we did not use goes on down the chain, so text fields, menu
        // shortcuts and the escape key still work.
        if !handled { super.pressesBegan(presses, with: event) }
    }

    open override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            if handle(key: key.charactersIgnoringModifiers.lowercased(), isDown: false) { handled = true }
        }
        if !handled { super.pressesEnded(presses, with: event) }
    }

    open override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // A cancelled press never gets an "ended", so release everything rather
        // than leaving a note stuck on.
        releaseAllTypedNotes()
        super.pressesCancelled(presses, with: event)
    }

    /// Returns whether the key meant something to us.
    @discardableResult
    private func handle(key: String, isDown: Bool) -> Bool {
        if let semitone = Self.musicalTypingMap[key] {
            let note = typedNoteNumber(forSemitone: semitone)
            if isDown {
                // Auto-repeat sends repeated `pressesBegan` for a held key; ignore
                // the repeats or every one retriggers the envelope.
                guard !typedNotes.contains(key) else { return true }
                typedNotes.insert(key)
                keyboardView.pressAdded(note, velocity: MIDIVelocity(typedVelocity))
            } else {
                guard typedNotes.remove(key) != nil else { return true }
                keyboardView.pressRemoved(note)
            }
            return true
        }

        guard isDown else { return Self.isTransportKey(key) }

        switch key {
        case Self.octaveDownKey:
            // Release first: the notes that are sounding belong to the old octave,
            // and their key-up would otherwise compute a different note number.
            releaseAllTypedNotes()
            typedOctave -= 1
            return true
        case Self.octaveUpKey:
            releaseAllTypedNotes()
            typedOctave += 1
            return true
        case Self.velocityDownKey:
            typedVelocity = max(1, typedVelocity - 16)
            conductor.updateDisplayLabel("Typing velocity: \(typedVelocity)")
            return true
        case Self.velocityUpKey:
            typedVelocity = min(127, typedVelocity + 16)
            conductor.updateDisplayLabel("Typing velocity: \(typedVelocity)")
            return true
        default:
            return false
        }
    }

    private static func isTransportKey(_ key: String) -> Bool {
        [octaveDownKey, octaveUpKey, velocityDownKey, velocityUpKey].contains(key)
    }

    /// The octave the typing keyboard plays in.
    ///
    /// **This is the `Octave:` stepper**, not a private counter. P3-5 originally gave
    /// the typing keyboard its own octave, which meant the app had two of them: the
    /// stepper moved the on-screen keyboard while `Z`/`X` moved what you actually
    /// played, and the visible control appeared to do nothing. On the iPad there is
    /// only one, because touch is the only input.
    ///
    /// So `Z`/`X` and the stepper now move the same value, and the on-screen
    /// keyboard follows either.
    ///
    /// Since 2026-09-09 this **is** applied to incoming MIDI as well, by the owner's
    /// decision: one control called "Octave" that the on-screen keys, the typing
    /// keyboard and a MIDI keyboard all follow. `Manager+MIDIListener.midiOctaveShift`
    /// reads this property, so the three cannot drift apart.
    var typedOctave: Int {
        get { Int((octaveStepper?.value ?? Double(Self.typedOctaveOrigin))) - Self.typedOctaveOrigin }
        set {
            guard let stepper = octaveStepper else { return }
            let target = Double(newValue + Self.typedOctaveOrigin)
            stepper.value = min(max(target, stepper.minValue), stepper.maxValue)
            // Same callback a click runs, so the keyboard redraws and the display
            // label updates.
            stepper.setValueCallback(stepper.value)
        }
    }

    /// The stepper value that means "middle C" — its own default.
    static let typedOctaveOrigin = 1

    func typedNoteNumber(forSemitone semitone: Int) -> MIDINoteNumber {
        // Middle C is 60; `typedOctave` 0 puts the `A` key there.
        let raw = 60 + (typedOctave * 12) + semitone
        return MIDINoteNumber(max(0, min(127, raw)))
    }

    /// Lift every note the typing keyboard is holding. Used when the octave shifts,
    /// when presses are cancelled, and when the window loses focus.
    func releaseAllTypedNotes() {
        for key in typedNotes {
            guard let semitone = Self.musicalTypingMap[key] else { continue }
            keyboardView.pressRemoved(typedNoteNumber(forSemitone: semitone))
        }
        typedNotes.removeAll()
    }
}
