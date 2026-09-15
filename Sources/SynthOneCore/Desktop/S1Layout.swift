//  Which interface the products show (P6, ADR-045).
//
//  **New, not ported.** Two layouts share one set of controls and bindings:
//
//  - `.classic` is upstream's 1024×768 iPad layout, loaded from the storyboards and
//    scaled to the window by `S1ScalingContainer` (ADR-019). It is what shipped as 0.1.0.
//  - `.desktop` is the Mac layout: a drop-down preset browser, every section visible at once, no
//    on-screen keyboard. The same storyboards are still loaded — every knob, switch and
//    binding comes from them — and `S1DesktopLayout` re-homes the controls into new
//    sections. See ADR-045 for why it is done that way rather than as new views.
//
//  The choice is a user default rather than a build setting, and since P7-8 (ADR-052, the
//  owner's decision) **classic is what a fresh install opens with**: Settings ▸ Layout, or
//
//      defaults write com.badpackets303.ArcadeRuins S1ClassicLayout -bool NO
//
//  picks the desktop one. The key still means "classic", so a machine that already answered the
//  question keeps its answer either way. The plugin keeps its own container and therefore its
//  own default.

import Foundation

import UIKit

/// Where the layout and skin choices live (P7-6). `.standard` in both products — which in the
/// plugin is the extension's own container.
///
/// **The test bundle points this at a scratch suite**, as ADR-036 does for `Disk`. `xcodebuild
/// test` runs the tests inside the app, so `UserDefaults.standard` there is the owner's real
/// domain: before this, a test that chose a layout or a skin wrote their settings, and a test
/// that tidied up afterwards deleted them.
public enum S1Preferences {
    public static var store: UserDefaults = .standard
}

extension UIViewController {
    /// The desktop layout this controller lives under, if any (P6-7). `Manager` owns it; its
    /// children reach it through their parent chain.
    var enclosingDesktopLayout: S1DesktopLayout? {
        var controller: UIViewController? = self
        while let current = controller {
            if let manager = current as? Manager { return manager.desktopLayout }
            controller = current.parent
        }
        return nil
    }
}

public enum S1Layout: String {

    case classic
    case desktop

    /// `true` selects the classic layout, `false` the desktop one. **Absent means classic**
    /// since P7-8 (ADR-052): the owner asked for the original iPad interface as the default.
    public static let classicDefaultsKey = "S1ClassicLayout"

    /// The layout the products open with. Unanswered is classic; `object(forKey:)` rather than
    /// `bool(forKey:)` because only the former tells absent from an explicit `NO`.
    public static var current: S1Layout {
        guard S1Preferences.store.object(forKey: classicDefaultsKey) != nil else { return .classic }
        return S1Preferences.store.bool(forKey: classicDefaultsKey) ? .classic : .desktop
    }

    /// Remembered for the next launch; the running interface does not change.
    public static func setCurrent(_ layout: S1Layout) {
        S1Preferences.store.set(layout == .classic, forKey: classicDefaultsKey)
    }
}
