//  S1PlatformServices — the iOS-only services Synth One shipped with (P3-2).
//
//  Upstream integrates five things that exist on iOS and have no macOS
//  counterpart: Audiobus, Inter-App Audio, OneSignal push, AppCenter analytics,
//  and the StoreKit review prompt. None of them belong in this product — it is
//  local-only and unsigned (ADR-005), so there is no push service, no analytics
//  account and no App Store listing to be reviewed.
//
//  They are a protocol with a do-nothing implementation rather than deleted call
//  sites, for the reason the port plan gives: `diff upstream/ Sources/` should
//  keep showing real changes rather than absences, and reinstating any of them is
//  then a matter of filling in a body.
//
//  Same shape as `S1AudioSession` (P2-2), including the default: the no-op is what
//  you get if nobody configures anything.

import UIKit

public protocol S1PlatformServices: AnyObject {

    /// Ask the App Store for a review. Upstream: `SKStoreReviewController`.
    func requestAppStoreReview()

    /// Whether an inter-app audio host (Audiobus or IAA) is driving us.
    var isConnectedToInterAppHost: Bool { get }

    /// The host's icon, for the header. Upstream: `AudioOutputUnitGetHostIcon`.
    func interAppHostIcon(size: CGFloat) -> UIImage?

    /// Switch to the host application. Upstream reads `kAudioUnitProperty_PeerURL`.
    func openInterAppHost()

    /// Register for host transport/state callbacks.
    /// Upstream: `Audiobus.client?.controller.stateIODelegate = delegate`.
    func registerInterAppHostStateDelegate(_ delegate: AnyObject?)
}

public enum S1PlatformServicesProvider {
    /// Nothing is wired up unless something says otherwise. On macOS nothing ever does.
    public static var current: S1PlatformServices = S1NoPlatformServices()
}

/// Every call succeeds and does nothing.
public final class S1NoPlatformServices: S1PlatformServices {

    public init() {}

    /// Deliberately silent. There is no App Store listing for a locally built,
    /// ad-hoc-signed app, and a prompt that opened a dead URL would be worse than
    /// no prompt. Revisit only if ADR-005 is revisited.
    public func requestAppStoreReview() {}

    public var isConnectedToInterAppHost: Bool { false }

    public func interAppHostIcon(size: CGFloat) -> UIImage? { nil }

    public func openInterAppHost() {}

    public func registerInterAppHostStateDelegate(_ delegate: AnyObject?) {}
}
