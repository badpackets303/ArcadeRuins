//  Proportional scaling for a fixed-size interface (P3-6b).
//
//  **New, not ported.** Upstream is a full-screen iPad app at one size.
//
//  ## Why scale rather than relayout
//
//  Synth One's twelve storyboards place every control by hand at 1024×768. There is
//  no adaptive layout underneath — no stack views, no size classes, nothing that
//  would reflow. Letting the window stretch the interface would leave controls
//  stranded and gaps opening between panels, which is the opposite of hard
//  requirement 1, "preserve the user interface".
//
//  So the interface keeps its exact 1024×768 geometry and a `CGAffineTransform`
//  scales the whole thing to fit the window, like a plugin GUI. Every proportion,
//  every gap and every knob size stays exactly as designed; only the overall size
//  changes. Hit-testing goes through the transform, so the controls stay live and
//  land where they look.
//
//  ## Letterboxing
//
//  The scale is `min(width, height)` so the interface always fits and never crops.
//  When the window's aspect differs from 4:3 the leftover is filled with the panel
//  background colour, so it reads as part of the instrument rather than as a gap.
//  Locking the window's aspect ratio would be the alternative, but Catalyst has no
//  API for it and fighting the user's drag is worse than a matched border.
//
//  ## The safe area is the title bar
//
//  `SceneDelegate` hides the title bar, so the window's content runs to the top edge
//  and the close/minimise/zoom buttons float **over** it. Catalyst reports the space
//  they need as `safeAreaInsets.top` — 32 points, measured, not assumed — so the
//  interface is laid out inside the safe area rather than the full bounds. Without
//  that the top-left of the header panel, which is the "AudioKit Synth One" label,
//  sits underneath the traffic lights.
//
//  The inset arrives on the *second* layout pass (the first reports zero), which is
//  why `viewSafeAreaInsetsDidChange` re-applies the scale.

import UIKit

public final class S1ScalingContainer: UIViewController {

    /// The size the storyboards are laid out at.
    public static let designSize = CGSize(width: 1_024, height: 768)

    /// Never smaller than this fraction of the design size — below it the text stops
    /// being readable, whatever the window will allow.
    public static let minimumScale: CGFloat = 0.5

    /// Room for the window's traffic lights, used only to size the window at launch
    /// so the interface still opens at 1:1. Layout itself uses the *measured*
    /// `safeAreaInsets`, so if the system ever reserves a different amount the
    /// interface is still laid out correctly — only the opening size would be off.
    public static let titlebarAllowance: CGFloat = 32

    /// The interface it is scaling. Exposed so callers can reach the real UI.
    public let content: UIViewController

    /// Matches the panel background in `Main.storyboard`
    /// (`white 0.157`), so the letterbox is not a visible frame.
    private static let letterboxColor = UIColor(white: 0.156_862_745, alpha: 1)

    public init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.letterboxColor

        addChild(content)
        view.addSubview(content.view)
        content.didMove(toParent: self)

        // The content is laid out by transform, not by constraints — Auto Layout and
        // a scale transform on the same view fight each other.
        content.view.translatesAutoresizingMaskIntoConstraints = true
        content.view.autoresizingMask = []
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyScale()
    }

    /// The safe-area inset only appears on the second layout pass, so the first one
    /// would otherwise leave the interface under the traffic lights until something
    /// else forced a relayout.
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applyScale()
    }

    /// Where the interface goes, given a window and the space the system has spoken
    /// for. Separated from the view deliberately: a Catalyst safe area only exists
    /// inside a real window, and the test bundle has no host application to make one
    /// in — so this is the part a unit test can reach.
    ///
    /// That the *caller* passes `view.safeAreaInsets` is not covered by a test. It
    /// was verified by measurement on a running build (32 points at the top).
    public static func layout(in bounds: CGRect,
                              safeArea: UIEdgeInsets) -> (scale: CGFloat, center: CGPoint)? {
        // Inside the safe area, not the full bounds: on macOS the top of the window
        // is where the close/minimise/zoom buttons are drawn, over the content.
        let region = bounds.inset(by: safeArea)
        guard region.width > 0, region.height > 0 else { return nil }

        let scale = max(minimumScale,
                        min(region.width / designSize.width,
                            region.height / designSize.height))
        return (scale, CGPoint(x: region.midX, y: region.midY))
    }

    /// Recomputed on every layout pass, so a live window drag scales continuously.
    private func applyScale() {
        guard let placement = Self.layout(in: view.bounds, safeArea: view.safeAreaInsets) else {
            return
        }

        // Order matters: the transform has to be cleared before setting `frame`, or
        // UIKit interprets the frame in the *scaled* coordinate space and the size
        // drifts on every pass.
        content.view.transform = .identity
        content.view.frame = CGRect(origin: .zero, size: Self.designSize)
        content.view.transform = CGAffineTransform(scaleX: placement.scale, y: placement.scale)
        content.view.center = placement.center
    }

    /// The size the window would need for the interface to render at 1:1.
    public static var nativeWindowSize: CGSize { designSize }
}
