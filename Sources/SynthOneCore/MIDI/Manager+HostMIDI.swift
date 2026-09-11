//  Manager+HostMIDI.swift — the plugin's side of MIDI input (ADR-031).
//
//  The plugin opens no MIDI inputs of its own (see `Manager.viewDidLoad`). Host MIDI arrives
//  in the render block, where `S1HostMIDI` plays notes exactly as `Manager+MIDIListener`
//  would. This file is the part that cannot happen there:
//
//  - **The settings.** The octave, MIDI channel, white-keys-only and hold all live in the
//    interface. Velocity sensitivity is not one of them: it is always on, in both products
//    (ADR-032). `syncHostMIDISettings()` copies every one of them to the
//    render thread whenever any might have changed. Each call site is one line, and
//    `HostMIDIInterfaceTests` checks each setting arrives through the path a user changes it by.
//  - **The controls.** A control change or program change comes back here and goes through
//    the same `AKMIDIListener` methods CoreMIDI drives in the standalone — the mod wheel, MIDI
//    learn, the sustain pedal's hold on on-screen keys, bank select and program change.
//  - **The lit keys.** What the host is holding, for the on-screen keyboard to draw.

extension Manager {

    /// Copies the interface's MIDI settings to the render thread.
    ///
    /// Plugin only. The standalone reads these same properties on the main thread as each
    /// note arrives, so it has nothing to copy.
    func syncHostMIDISettings() {
        guard conductor.isHosted, let hosted = conductor.synth as? S1HostedSynth else { return }
        hosted.audioUnit.hostMIDISettings = S1HostMIDISettings(
            octaveShift: Int32(midiOctaveShift),
            midiChannel: Int32(conductor.midiInChannel),
            omniMode: conductor.isOmniMode,
            whiteKeysOnly: appSettings.whiteKeysOnly,
            holdMode: keyboardView?.holdMode ?? false)
    }

    /// A control change or program change from the host.
    ///
    /// Its note-level effects were already applied on the render thread — the sustain pedal's
    /// hold on host notes included. CC64 still comes here as well, deliberately: in the
    /// standalone the pedal also holds keys played on the on-screen keyboard, and that
    /// sustainer lives on this side.
    func receivedHostMIDIControl(_ message: S1HostMIDIMessage) {
        let channel = MIDIChannel(message.status & 0x0F)
        switch message.status & 0xF0 {
        case 0xB0:
            receivedMIDIController(message.data1, value: message.data2, channel: channel)
        case 0xC0:
            receivedMIDIProgramChange(message.data1, channel: channel)
        default:
            break
        }
    }

    /// Lights the keys host MIDI is holding.
    func showHostHeldKeys(_ keys: S1HostKeys) {
        var held = Set<MIDINoteNumber>()
        for bit in 0..<64 {
            if keys.low & (UInt64(1) << UInt64(bit)) != 0 { held.insert(MIDINoteNumber(bit)) }
            if keys.high & (UInt64(1) << UInt64(bit)) != 0 { held.insert(MIDINoteNumber(64 + bit)) }
        }
        keyboardView?.hostOnKeys = held
    }
}
