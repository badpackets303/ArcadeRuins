//  Typealiases the ported AudioKit sources rely on (AudioKit's AKTypes.swift).
//  Names kept as upstream — see ADR-009.

import Foundation

/// A single byte of a MIDI message. The MIDI-learn layer types every status,
/// controller number and value through this.
public typealias MIDIByte = UInt8

/// A 14-bit MIDI value carried in two bytes — pitch bend, and nothing else here.
public typealias MIDIWord = UInt16

public typealias MIDINoteNumber = UInt8
public typealias MIDIVelocity = UInt8
public typealias MIDIChannel = UInt8
