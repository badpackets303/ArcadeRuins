//  S1MIDI — CoreMIDI input for the standalone app (P3-4).
//
//  Replaces `AudioKit.midi`. Upstream's MIDI layer is ~15 files of AudioKit; Synth
//  One touches seven entry points, so this is those seven over CoreMIDI directly:
//  enumerate sources, connect and disconnect them by name, publish a virtual
//  destination other apps can send to, and turn incoming packets into the
//  `AKMIDIListener` calls `Manager` and `KeyboardView` already implement.
//
//  Named `S1MIDI` rather than restoring an `AudioKit` namespace — there is no
//  global engine any more (ADR-014).
//
//  ## The MIDI 1.0 protocol over Universal MIDI Packets
//
//  `MIDIInputPortCreateWithProtocol` is macOS 11 / iOS 14, which is exactly our
//  deployment target, and it is the API that is not deprecated. Asking for
//  `._1_0` means CoreMIDI hands us MIDI 1.0 channel-voice messages already packed
//  one per 32-bit word, which is easier to read than a `MIDIPacketList` and does
//  not need running-status handling.
//
//  ## Threading
//
//  Every callback arrives on CoreMIDI's own high-priority thread. Nothing here
//  touches UIKit; the listeners hop to the main queue themselves, which is what
//  upstream's `Manager+MIDIListener` already does.

import Foundation
import CoreMIDI
import S1Support

public final class S1MIDI {

    public static let shared = S1MIDI()

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var virtualDestination = MIDIEndpointRef()
    private var virtualSource = MIDIEndpointRef()

    /// Endpoints we have connected, by display name.
    private var connected: [String: MIDIEndpointRef] = [:]
    private let lock = NSLock()

    /// Strong, like upstream's. The listeners are the app's long-lived
    /// `Manager` and `KeyboardView`, and a weak box here would be a lifetime
    /// puzzle for no benefit.
    private var listeners: [AKMIDIListener] = []

    private init() {}

    // MARK: - Client lifecycle

    /// Idempotent: the app calls this at launch, and `openInput` calls it in case
    /// something reaches MIDI before that.
    @discardableResult
    public func startIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard client == 0 else { return true }

        let notifyBlock: MIDINotifyBlock = { [weak self] notification in
            // Devices coming and going. `Manager` rebuilds its input list and
            // connects anything new.
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            self?.forEachListener { $0.receivedMIDISetupChange() }
        }
        var status = MIDIClientCreateWithBlock("SynthOne" as CFString, &client, notifyBlock)
        guard status == noErr else {
            AKLog("S1MIDI: MIDIClientCreateWithBlock failed: \(status)")
            return false
        }

        status = MIDIInputPortCreateWithProtocol(client, "SynthOne In" as CFString, ._1_0, &inputPort) {
            [weak self] eventList, _ in
            self?.handle(eventList)
        }
        guard status == noErr else {
            AKLog("S1MIDI: MIDIInputPortCreateWithProtocol failed: \(status)")
            return false
        }
        return true
    }

    // MARK: - Sources

    /// Display names of every MIDI source on the system.
    public var inputNames: [String] {
        (0..<MIDIGetNumberOfSources()).compactMap { Self.displayName(of: MIDIGetSource($0)) }
    }

    public func addListener(_ listener: AKMIDIListener) {
        lock.lock()
        listeners.append(listener)
        lock.unlock()

        // Tell the new listener about the devices that are *already* attached.
        // CoreMIDI only notifies on change, and upstream relied on AudioKit having
        // scanned before the UI registered — without this, nothing is connected
        // until you unplug something.
        startIfNeeded()
        DispatchQueue.main.async { listener.receivedMIDISetupChange() }
    }

    /// Whether `listener` is registered. Internal, for tests: the plugin must never be (ADR-031).
    func isListening(_ listener: AKMIDIListener) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return listeners.contains { ($0 as AnyObject) === (listener as AnyObject) }
    }

    public func openInput(name: String) {
        guard startIfNeeded() else { return }
        lock.lock()
        let alreadyOpen = connected[name] != nil
        lock.unlock()
        guard !alreadyOpen else { return }

        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard Self.displayName(of: source) == name else { continue }
            let status = MIDIPortConnectSource(inputPort, source, nil)
            if status == noErr {
                lock.lock(); connected[name] = source; lock.unlock()
                AKLog("S1MIDI: opened \(name)")
            } else {
                AKLog("S1MIDI: could not connect \(name): \(status)")
            }
            return
        }
        AKLog("S1MIDI: no source named \(name)")
    }

    public func closeInput(name: String) {
        lock.lock()
        let source = connected.removeValue(forKey: name)
        lock.unlock()
        guard let source = source else { return }
        MIDIPortDisconnectSource(inputPort, source)
        AKLog("S1MIDI: closed \(name)")
    }

    /// A destination other applications can send to, so Synth One shows up in
    /// their MIDI output lists.
    public func createVirtualInputPort(_ uniqueID: Int32, name: String) {
        guard startIfNeeded(), virtualDestination == 0 else { return }
        let status = MIDIDestinationCreateWithProtocol(client, name as CFString, ._1_0,
                                                       &virtualDestination) { [weak self] eventList, _ in
            self?.handle(eventList)
        }
        guard status == noErr else {
            AKLog("S1MIDI: could not create virtual destination \(name): \(status)")
            return
        }
        MIDIObjectSetIntegerProperty(virtualDestination, kMIDIPropertyUniqueID, uniqueID)
    }

    /// A source other applications can listen to. Upstream opens this to forward
    /// Inter-App Audio MIDI, which does not exist on macOS — but a virtual source
    /// is useful on its own and costs nothing.
    public func openOutput(name: String) {
        guard startIfNeeded(), virtualSource == 0 else { return }
        let status = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &virtualSource)
        if status != noErr { AKLog("S1MIDI: could not create virtual source \(name): \(status)") }
    }

    /// Send a raw MIDI 1.0 message out of the virtual source.
    public func sendMessage(_ data: [MIDIByte]) {
        guard virtualSource != 0, data.count == 3 else { return }
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        var word = Self.universalPacket(status: data[0], data1: data[1], data2: data[2])
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
        MIDIReceivedEventList(virtualSource, &list)
    }

    // MARK: - Parsing

    private func handle(_ eventList: UnsafePointer<MIDIEventList>) {
        for packet in eventList.unsafeSequence() {
            for word in packet.words() {
                dispatch(word: word, timestamp: packet.pointee.timeStamp)
            }
        }
    }

    /// One MIDI 1.0 channel-voice message per 32-bit Universal MIDI Packet word:
    /// `[type:4][group:4][status:8][data1:8][data2:8]`, with message type `0x2`.
    // Internal rather than private so the parsing can be tested without hardware.
    func dispatch(word: UInt32, timestamp: MIDITimeStamp) {
        guard (word >> 28) & 0xF == 0x2 else { return }   // MIDI 1.0 channel voice
        let status = MIDIByte((word >> 16) & 0xFF)
        let data1 = MIDIByte((word >> 8) & 0x7F)
        let data2 = MIDIByte(word & 0x7F)
        let channel = MIDIChannel(status & 0x0F)

        switch status & 0xF0 {
        case 0x80:
            forEachListener { $0.receivedMIDINoteOff(noteNumber: data1, velocity: data2,
                                                     channel: channel, portID: nil, offset: timestamp) }
        case 0x90:
            // Note on with velocity 0 is note off. `Manager` handles that itself,
            // and so does anything else conforming to the protocol, so it is passed
            // through as upstream's AudioKit layer did.
            forEachListener { $0.receivedMIDINoteOn(noteNumber: data1, velocity: data2,
                                                    channel: channel, portID: nil, offset: timestamp) }
        case 0xA0:
            forEachListener { $0.receivedMIDIAftertouch(noteNumber: data1, pressure: data2,
                                                        channel: channel, portID: nil, offset: timestamp) }
        case 0xB0:
            forEachListener { $0.receivedMIDIController(data1, value: data2,
                                                        channel: channel, portID: nil, offset: timestamp) }
        case 0xC0:
            forEachListener { $0.receivedMIDIProgramChange(data1, channel: channel,
                                                           portID: nil, offset: timestamp) }
        case 0xD0:
            forEachListener { $0.receivedMIDIAftertouch(data1, channel: channel,
                                                        portID: nil, offset: timestamp) }
        case 0xE0:
            // 14-bit, LSB first.
            let bend = MIDIWord(data1) | (MIDIWord(data2) << 7)
            forEachListener { $0.receivedMIDIPitchWheel(bend, channel: channel,
                                                        portID: nil, offset: timestamp) }
        default:
            break
        }
    }

    static func universalPacket(status: MIDIByte, data1: MIDIByte, data2: MIDIByte) -> UInt32 {
        (UInt32(0x2) << 28) | (UInt32(status) << 16) | (UInt32(data1) << 8) | UInt32(data2)
    }

    private func forEachListener(_ body: (AKMIDIListener) -> Void) {
        lock.lock()
        let snapshot = listeners
        lock.unlock()
        snapshot.forEach(body)
    }

    private static func displayName(of endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }
}
