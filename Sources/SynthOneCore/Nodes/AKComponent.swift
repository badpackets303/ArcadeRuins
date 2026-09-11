//  The slice of AudioKit 4.9.2's `AKComponent.swift` and `AudioKitHelpers.swift`
//  that `AKSynthOne.swift` needs to register and instantiate its audio unit (MIT).
//  Names kept per ADR-009.

import AVFoundation
import S1Support

/// Helpful in reducing repetitive code in AudioKit
public protocol Aliased {
    associatedtype _Self = Self
}

/// A type that describes an audio component.
public protocol AUComponent: AnyObject, Aliased {
    static var ComponentDescription: AudioComponentDescription { get }
}

/// An `AUComponent` backed by an `AUAudioUnit` subclass we own.
public protocol AKComponent: AUComponent {
    associatedtype AKAudioUnitType: AnyObject
}

extension AKComponent {

    /// Register the audio unit subclass so it can be instantiated in-process.
    public static func register() {
        AUAudioUnit.registerSubclass(Self.AKAudioUnitType.self,
                                     as: Self.ComponentDescription,
                                     name: "Local \(Self.self)",
                                     version: .max)
    }
}

/// Pack a four-character string into an `OSType`.
public func fourCC(_ string: String) -> UInt32 {
    let utf8 = string.utf8
    precondition(utf8.count == 4, "Must be a 4 char string")
    var out: UInt32 = 0
    for char in utf8 {
        out <<= 8
        out |= UInt32(char)
    }
    return out
}

/// The manufacturer code Synth One registers under.
///
/// PORT: AudioKit hardcodes its own `"AuKt"` in the convenience initialisers
/// below. Using ours instead means the in-process node the standalone app plays
/// through and the AUv3 the host loads describe the *same* instrument
/// (`project.yml`: `aumu` / `ruin` / `BP03`). Manufacturer code per ADR-005.
public let S1ManufacturerCode: OSType = fourCC("BP03")

extension AudioComponentDescription {

    /// Initialize with type and sub-type
    public init(type: OSType, subType: OSType) {
        self.init(componentType: type,
                  componentSubType: subType,
                  componentManufacturer: S1ManufacturerCode,
                  componentFlags: AudioComponentFlags.sandboxSafe.rawValue,
                  componentFlagsMask: 0)
    }

    /// Initialize as an instrument with a sub-type string
    public init(instrument subType: String) {
        self.init(type: kAudioUnitType_MusicDevice, subType: fourCC(subType))
    }
}

extension AVAudioUnit {

    /// Instantiate a registered audio unit subclass, in-process.
    ///
    /// PORT: upstream's `_instantiate` also did `AudioKit.engine.attach($0)`.
    /// There is no global engine any more (ADR-014) — attaching is
    /// `S1AudioEngine`'s job, and it happens when the node is given to it.
    ///
    /// No `.loadInProcess`: that option is **unavailable in Mac Catalyst**, which
    /// gets the iOS API surface where registered subclasses are always loaded in
    /// process anyway. It does mean the shipping AUv3 registers the same
    /// `aumu`/`ruin`/`BP03` description system-wide, so `S1AudioEngineTests`
    /// asserts the instance we get back really is our `S1AudioUnit` subclass and
    /// not the installed extension.
    public class func _instantiate(with component: AudioComponentDescription,
                                   callback: @escaping (AVAudioUnit) -> Void) {
        AVAudioUnit.instantiate(with: component, options: []) { avAudioUnit, error in
            if let error = error {
                AKLog("could not instantiate audio unit: \(error)")
            }
            avAudioUnit.map { callback($0) }
        }
    }
}
