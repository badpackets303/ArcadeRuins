//  S1AudioSession — P2-2.
//
//  Upstream calls `AKSettings.setSession(...)`, `AKSettings.session.setActive(false)`
//  and `AVAudioSession.sharedInstance().setPreferredIOBufferDuration(_:)` from five
//  places. Four of them are UI (Manager, MIDI settings); one is `Conductor.start()`.
//
//  **An AUv3 extension must never do any of this.** The audio session belongs to
//  the host application; a plugin that sets a category or an I/O buffer duration is
//  reaching into a process it does not own, and hosts are entitled to misbehave in
//  response. But the same `SynthOneCore` code — the same panels, the same settings
//  screen — runs in both products. So the call sites stay, and what they talk to
//  changes.
//
//  The default is the no-op. Forgetting to configure the standalone app costs you
//  a silent app you will notice in a second; forgetting to *suppress* it in the
//  plugin costs you a bug in someone else's DAW that you will never see.

import AVFoundation

public protocol S1AudioSession: AnyObject {

    /// Hardware sample rate, or 0 when unknown.
    var sampleRate: Double { get }

    /// Put the session into the category Synth One needs and activate it.
    func configure() throws

    func setActive(_ active: Bool) throws

    /// Preferred I/O buffer duration in seconds — the MIDI settings panel's
    /// buffer-length control.
    func setPreferredIOBufferDuration(_ duration: Double) throws
}

/// Which session the code in this framework is talking to.
///
/// The standalone app sets this to `S1SystemAudioSession` at launch. The AUv3
/// leaves it alone.
public enum S1AudioSessionProvider {
    public static var current: S1AudioSession = S1HostedAudioSession()
}

/// The real thing, for the standalone app.
public final class S1SystemAudioSession: S1AudioSession {

    private let session = AVAudioSession.sharedInstance()

    public init() {}

    public var sampleRate: Double { session.sampleRate }

    /// PORT: upstream is
    /// `AKSettings.setSession(category: .playAndRecord, with: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])`.
    ///
    /// **`.playback`, not `.playAndRecord`** — and this one is worth explaining,
    /// because it cost 72 seconds of launch time before anyone noticed.
    ///
    /// `.playAndRecord` makes macOS ask the user for **microphone access**, and the
    /// app blocks on that dialog. Measured on the owner's machine: the window did
    /// not appear for 72 seconds, because the prompt was sitting there unanswered.
    /// It looked exactly like a device-open stall and was misdiagnosed as one.
    ///
    /// Synth One on macOS never records audio *input*. Its recorder taps the mixer's
    /// **output** (P2-3, `S1NodeRecorder`), and the two features that did want input
    /// on iOS — Audiobus and Inter-App Audio — do not exist here (P3-2). So the
    /// permission was being requested for nothing.
    ///
    /// `.defaultToSpeaker` and `.allowBluetoothHFP` go with it: both are
    /// record-category options and are meaningless without one.
    public func configure() throws {
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)
    }

    public func setActive(_ active: Bool) throws {
        try session.setActive(active)
    }

    public func setPreferredIOBufferDuration(_ duration: Double) throws {
        try session.setPreferredIOBufferDuration(duration)
    }
}

/// What the AUv3 gets: nothing happens.
///
/// Not an error and not a log — the call sites are shared code doing the right
/// thing for the standalone app, and there is nothing to warn about.
public final class S1HostedAudioSession: S1AudioSession {

    public init() {}

    /// The host owns the session. `AKSettings.sampleRate` is what the audio unit
    /// is actually rendering at, and it is set from the host's format.
    public var sampleRate: Double { AKSettings.sampleRate }

    public func configure() throws {}
    public func setActive(_ active: Bool) throws {}
    public func setPreferredIOBufferDuration(_ duration: Double) throws {}
}
