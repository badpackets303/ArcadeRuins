//  Window chrome for the standalone Mac app (P3-6).
//
//  **New, not ported.** Upstream is a full-screen iPad app: no window, no title
//  bar, no menu bar, and no resizing. Everything here is the macOS half that has no
//  counterpart on iOS.
//
//  The size constraint is the important part. Synth One's storyboards are a fixed
//  1024×768 iPad layout with hand-placed frames — there is no adaptive layout to
//  fall back on, and stretching it would leave controls stranded. So the window
//  holds that aspect ratio and scales, which is exactly what ADR-007 is deciding
//  between at P3-1b; until then, iPad-scaled is the behaviour that preserves the
//  interface (hard requirement 1).

import UIKit
import SynthOneCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// The iPad layout the storyboards are built at. Single source of truth lives
    /// with the container that scales it.
    private static var designSize: CGSize { S1ScalingContainer.designSize }

    /// The design size plus the room macOS takes for the window buttons.
    private static var windowSizeForDesign: CGSize {
        CGSize(width: S1ScalingContainer.designSize.width,
               height: S1ScalingContainer.designSize.height + S1ScalingContainer.titlebarAllowance)
    }

    /// Three times the design, plus the allowance: past any display worth having.
    private static var largestWindowSize: CGSize {
        CGSize(width: designSize.width * 3,
               height: designSize.height * 3 + S1ScalingContainer.titlebarAllowance)
    }

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        configure(windowScene)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = SynthOneApp.makeRootViewController(layout: layout)
        // Open at 1:1 so the first thing anyone sees is the interface as designed.
        // `requestGeometryUpdate` would be the modern way and needs Catalyst 16;
        // our floor is 14, and setting the frame directly works on both.
        // Taller than the design by the traffic-light allowance, so the interface
        // itself still opens at 1:1 — `S1ScalingContainer` lays out inside the safe
        // area, and on macOS the top of the window belongs to the window buttons.
        window.frame = CGRect(origin: window.frame.origin, size: Self.windowSizeForDesign)
        if layout == .desktop {
            // P6 (ADR-045): the desktop layout draws its own toolbar under the traffic
            // lights, so no allowance is added; it opens at its design size and is
            // fluid above its minimum.
            window.frame = CGRect(origin: window.frame.origin, size: SynthOneApp.desktopWindowSize)
            // P6-4: the layout is dark by design, and so are the sheets and popovers it
            // presents; they read the window's style, not the layout's.
            window.overrideUserInterfaceStyle = .dark
        }
        window.makeKeyAndVisible()
        self.window = window

        // ADR-042: `configure` capped the window at the design size, so a size saved from an
        // earlier session cannot reopen it larger. Once the window is up it may grow again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak windowScene] in
            windowScene?.sizeRestrictions?.maximumSize = Self.largestWindowSize
        }

        if let url = connectionOptions.urlContexts.first?.url {
            SynthOneApp.open(url: url)
        }
    }

    /// Which interface this window shows, decided once per launch.
    private let layout = S1Layout.current

    private func configure(_ windowScene: UIWindowScene) {
        windowScene.title = "SynthOne"

        if layout == .desktop {
            // P6 (ADR-045): Auto Layout, not scaling. Any size above the minimum works.
            // macOS reopens the window at its last saved frame — the classic layout's
            // 1024×800, the first time — so, as ADR-042 does, the size is pinned to the
            // design size for the first second and then freed.
            windowScene.sizeRestrictions?.minimumSize = SynthOneApp.desktopWindowSize
            windowScene.sizeRestrictions?.maximumSize = SynthOneApp.desktopWindowSize
            windowScene.titlebar?.titleVisibility = .hidden
            windowScene.titlebar?.toolbar = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak windowScene] in
                windowScene?.sizeRestrictions?.minimumSize = SynthOneApp.desktopMinimumWindowSize
                windowScene?.sizeRestrictions?.maximumSize = CGSize(width: 4_096, height: 4_096)
            }
            return
        }

        // Bound the window, but let it move. The interface is scaled to fit by
        // `S1ScalingContainer`, so any size in this range renders the full layout —
        // grab the corner and it scales continuously.
        //
        // Half size is where the labels stop being readable; three times is past any
        // display worth having.
        //
        // The allowance is added to both ends: the bounds are on the *interface*, and
        // the window is always that much taller than the interface it contains.
        windowScene.sizeRestrictions?.minimumSize = CGSize(
            width: Self.designSize.width * S1ScalingContainer.minimumScale,
            height: Self.designSize.height * S1ScalingContainer.minimumScale
                + S1ScalingContainer.titlebarAllowance)
        // ADR-042: the largest size starts at the design size and is raised to
        // `largestWindowSize` in `willConnectTo` once the window is up. macOS reopens the window
        // at its last saved size, over the frame set in `willConnectTo`, and ADR-037's 1024×900
        // was still saved: the interface opened letterboxed, with bands above and below it.
        windowScene.sizeRestrictions?.maximumSize = Self.windowSizeForDesign

        // A title bar over a synth panel is noise; the panel *is* the interface.
        // The window still drags by its background and keeps its traffic lights.
        windowScene.titlebar?.titleVisibility = .hidden
        windowScene.titlebar?.toolbar = nil
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        SynthOneApp.open(url: url)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Nothing is torn down: a synth that stops sounding when it loses focus is
        // useless next to a DAW. `Conductor.stopEngine()` is for termination.
    }
}
