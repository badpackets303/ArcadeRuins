//
//  Private.swift
//  AudioKitSynthOne
//
//  Created by Stéphane Peter on 7/12/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import Foundation

//
// IMPORTANT: Fill in your own private API keys here as needed.
//
// ⚠️ The `"***REMOVED***"` values below are **upstream's own placeholders** — AudioKit
// scrubbed their keys before open-sourcing — and they are **load-bearing**.
// `MailingListViewController`, `Manager` and `Manager+HeaderDelegate` all guard on
// `Private.MailChimpAPIKey != "***REMOVED***"`, so the string is what keeps the
// mailing-list signup disabled. Filling one in switches the feature on.
//
// Nothing here is used by the macOS port. See `Platform/PlatformServices.swift`.

class Private {

    //swiftlint:disable line_length

    // PORT (P3-2): upstream ships AudioKit's **real** Audiobus API key here — a
    // live credential in their public repository. Audiobus is iOS-only and this
    // port does not use it (P3-2), so carrying someone else's key serves nothing
    // and is removed. The declaration stays so any call site still compiles.
    public static let AudioBusAPIKey = ""

    // API key for MailChimp
    public static let MailChimpAPIKey = "***REMOVED***"
    public static let MailChimpID = "***REMOVED***"

    // App ID for OneSignal
    public static let OneSignalAppID = "***REMOVED***"

    // API Key for AppCenter
    public static let AppCenterAPIKey = "***REMOVED***"
}
