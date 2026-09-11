//  P3-4 acceptance: incoming MIDI becomes the right `AKMIDIListener` calls.
//
//  The parsing is what can be tested without a device attached, and it is also
//  where the bugs live — a status nibble read wrong, or pitch bend assembled from
//  its two 7-bit halves in the wrong order, is silent and wrong rather than loud
//  and wrong. Enumeration and connection need real hardware and are exercised by
//  running the app.

import XCTest
import CoreMIDI
@testable import SynthOneCore

/// Records what it is told, so a test can assert on it.
private final class RecordingListener: AKMIDIListener {
    var noteOns: [(MIDINoteNumber, MIDIVelocity, MIDIChannel)] = []
    var noteOffs: [(MIDINoteNumber, MIDIVelocity, MIDIChannel)] = []
    var controllers: [(MIDIByte, MIDIByte, MIDIChannel)] = []
    var programChanges: [(MIDIByte, MIDIChannel)] = []
    var pitchWheels: [(MIDIWord, MIDIChannel)] = []
    var channelPressures: [(MIDIByte, MIDIChannel)] = []
    var polyPressures: [(MIDINoteNumber, MIDIByte, MIDIChannel)] = []

    func receivedMIDINoteOn(noteNumber: MIDINoteNumber, velocity: MIDIVelocity,
                            channel: MIDIChannel, portID: MIDIUniqueID?, offset: MIDITimeStamp) {
        noteOns.append((noteNumber, velocity, channel))
    }
    func receivedMIDINoteOff(noteNumber: MIDINoteNumber, velocity: MIDIVelocity,
                             channel: MIDIChannel, portID: MIDIUniqueID?, offset: MIDITimeStamp) {
        noteOffs.append((noteNumber, velocity, channel))
    }
    func receivedMIDIController(_ controller: MIDIByte, value: MIDIByte,
                                channel: MIDIChannel, portID: MIDIUniqueID?, offset: MIDITimeStamp) {
        controllers.append((controller, value, channel))
    }
    func receivedMIDIProgramChange(_ program: MIDIByte, channel: MIDIChannel,
                                   portID: MIDIUniqueID?, offset: MIDITimeStamp) {
        programChanges.append((program, channel))
    }
    func receivedMIDIPitchWheel(_ pitchWheelValue: MIDIWord, channel: MIDIChannel,
                                portID: MIDIUniqueID?, offset: MIDITimeStamp) {
        pitchWheels.append((pitchWheelValue, channel))
    }
    func receivedMIDIAftertouch(_ pressure: MIDIByte, channel: MIDIChannel,
                                portID: MIDIUniqueID?, offset: MIDITimeStamp) {
        channelPressures.append((pressure, channel))
    }
    func receivedMIDIAftertouch(noteNumber: MIDINoteNumber, pressure: MIDIByte,
                                channel: MIDIChannel, portID: MIDIUniqueID?, offset: MIDITimeStamp) {
        polyPressures.append((noteNumber, pressure, channel))
    }
}

final class S1MIDITests: XCTestCase {

    private var listener: RecordingListener!

    override func setUp() {
        super.setUp()
        listener = RecordingListener()
        S1MIDI.shared.addListener(listener)
    }

    /// Build the 32-bit Universal MIDI Packet word CoreMIDI delivers for a MIDI 1.0
    /// channel-voice message, and push it through the same path a real packet takes.
    private func send(status: MIDIByte, _ data1: MIDIByte, _ data2: MIDIByte) {
        S1MIDI.shared.dispatch(word: S1MIDI.universalPacket(status: status, data1: data1, data2: data2),
                               timestamp: 0)
    }

    func testNoteOnAndNoteOffOnTheRightChannel() {
        send(status: 0x93, 60, 100)   // note on, channel 4 (0-based 3)
        send(status: 0x83, 60, 64)    // note off

        XCTAssertEqual(listener.noteOns.count, 1)
        XCTAssertEqual(listener.noteOns.first?.0, 60)
        XCTAssertEqual(listener.noteOns.first?.1, 100)
        XCTAssertEqual(listener.noteOns.first?.2, 3, "channel is the low nibble of the status byte")

        XCTAssertEqual(listener.noteOffs.count, 1)
        XCTAssertEqual(listener.noteOffs.first?.0, 60)
        XCTAssertEqual(listener.noteOffs.first?.2, 3)
    }

    /// Note-on with velocity 0 is a note-off by convention, and it is passed
    /// through as a note-on — `Manager.receivedMIDINoteOn` converts it. AudioKit's
    /// layer behaved the same way, and changing it here would double-handle it.
    func testNoteOnWithZeroVelocityIsPassedThrough() {
        send(status: 0x90, 64, 0)
        XCTAssertEqual(listener.noteOns.count, 1)
        XCTAssertEqual(listener.noteOns.first?.1, 0)
        XCTAssertTrue(listener.noteOffs.isEmpty)
    }

    /// The MIDI-learn layer keys entirely off controller numbers.
    func testControlChange() {
        send(status: 0xB0, 74, 96)
        XCTAssertEqual(listener.controllers.count, 1)
        XCTAssertEqual(listener.controllers.first?.0, 74)
        XCTAssertEqual(listener.controllers.first?.1, 96)
        XCTAssertEqual(listener.controllers.first?.2, 0)
    }

    /// Pitch bend is 14 bits split across two 7-bit bytes, **LSB first**. Getting
    /// the order backwards still produces plausible-looking numbers, which is why
    /// this is checked against three known values.
    func testPitchWheelIsAssembledLSBFirst() {
        send(status: 0xE0, 0x00, 0x40)   // centre
        send(status: 0xE0, 0x00, 0x00)   // minimum
        send(status: 0xE0, 0x7F, 0x7F)   // maximum

        XCTAssertEqual(listener.pitchWheels.map(\.0), [8_192, 0, 16_383])
    }

    func testProgramChangeAndAftertouch() {
        send(status: 0xC2, 7, 0)
        send(status: 0xD1, 90, 0)
        send(status: 0xA5, 48, 77)

        XCTAssertEqual(listener.programChanges.first?.0, 7)
        XCTAssertEqual(listener.programChanges.first?.1, 2)
        XCTAssertEqual(listener.channelPressures.first?.0, 90)
        XCTAssertEqual(listener.channelPressures.first?.1, 1)
        XCTAssertEqual(listener.polyPressures.first?.0, 48)
        XCTAssertEqual(listener.polyPressures.first?.1, 77)
        XCTAssertEqual(listener.polyPressures.first?.2, 5)
    }

    /// Only Universal MIDI Packet message type 0x2 — MIDI 1.0 channel voice — is
    /// ours. A system or MIDI 2.0 word must be ignored rather than misread as a
    /// note on.
    func testNonChannelVoiceWordsAreIgnored() {
        S1MIDI.shared.dispatch(word: 0x1000_0000, timestamp: 0)   // system real time
        S1MIDI.shared.dispatch(word: 0x4090_3C64, timestamp: 0)   // MIDI 2.0 note on
        XCTAssertTrue(listener.noteOns.isEmpty)
        XCTAssertTrue(listener.controllers.isEmpty)
    }

    /// Enumeration must work whether or not anything is plugged in, and must not
    /// need a client to have been created first.
    func testEnumeratingSourcesIsSafeWithNoDevices() {
        XCTAssertNoThrow(_ = S1MIDI.shared.inputNames)
        S1MIDI.shared.openInput(name: "no such device")
        S1MIDI.shared.closeInput(name: "no such device")
    }
}
