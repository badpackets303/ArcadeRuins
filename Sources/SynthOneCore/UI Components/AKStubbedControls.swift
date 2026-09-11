//  Two controls the storyboards instantiate by name that have nothing behind them
//  on macOS (P3-1).
//
//  Both are kept as classes rather than edited out of the storyboards. Editing a
//  storyboard by hand to delete a control is a change we would have to redo every
//  time we diff against upstream, and it risks disturbing the constraints around
//  it — the opposite of "preserve the UI".

import UIKit
import S1Support

/// Upstream: `AKLinkButton`, which joins an Ableton Link session.
///
/// **Link is dropped** (ADR-004, the owner's decision), so there is nothing for
/// this button to do. It hides itself rather than sitting in the header panel
/// looking clickable — a dead control is worse than an absent one.
@objc(AKLinkButton)
open class AKLinkButton: UIButton {
    open override func awakeFromNib() {
        super.awakeFromNib()
        isHidden = true
    }
}

/// Upstream: `AKBluetoothMIDIButton`, which presents `CABTMIDICentralViewController`
/// to pair a Bluetooth MIDI device.
///
/// That view controller is iOS-only and has no Mac Catalyst equivalent. On macOS,
/// Bluetooth MIDI pairing lives in **Audio MIDI Setup**, so the button opens that
/// instead of hiding — which also closes the gap it left in the bottom bar
/// (`docs/06-ui-cross-check.md`). The layout uses fixed frames, so a hidden button
/// leaves a hole rather than reflowing.
@objc(AKBluetoothMIDIButton)
open class AKBluetoothMIDIButton: UIButton {

    open override func awakeFromNib() {
        super.awakeFromNib()
        addTarget(self, action: #selector(openAudioMIDISetup), for: .touchUpInside)
        accessibilityLabel = NSLocalizedString("Bluetooth MIDI",
                                               comment: "Opens Audio MIDI Setup for Bluetooth pairing")
    }

    @objc private func openAudioMIDISetup() {
        // Catalyst cannot launch another app directly, but it can ask the system to
        // open one by URL.
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { AKLog("could not open Audio MIDI Setup") }
        }
    }

    /// Upstream positions the Bluetooth picker's popover over a view. There is no
    /// popover; `Manager.viewDidLoad` still calls this.
    @objc open func centerPopupIn(view: UIView) {}
}
