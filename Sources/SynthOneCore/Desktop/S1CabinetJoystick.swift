//  The cabinet's joystick, live (P7-11, ADR-061).
//
//  **New, not ported.** The Cabinet skin's painting has an arcade machine with a red joystick.
//  The owner asked (2026-09-17) for it to move, as an easter egg: push it up and it is the mod
//  wheel; lean it left or right and it bends the pitch; let go and it springs back. The painting
//  has the joystick lifted off it (`generate.py`, `lift_joystick`) and this view draws the same
//  pixels as two sprites, a ball on a rod, hinged where the rod meets its socket.
//
//  **Nothing is ever stretched** (owner, the same day: "don't stretch it for maximum realism").
//  The rod leans about its socket and the ball slides along it: up a little when the stick is
//  pushed away, showing more rod, and down over the rod when it is pulled forward, covering it.
//
//  It drives the classic wheels — `Manager.modWheelPad` and `Manager.pitchBend` — through the
//  same two calls a touch on them makes, so the routing (cutoff, LFO 1 rate, LFO 2 rate), the
//  bend range and the Wheels sheet all follow. It owns no parameter of its own.

import UIKit

final class S1CabinetJoystick: UIView {

    /// Push, 0...1: the mod wheel. Called while dragging.
    var onPush: (Double) -> Void = { _ in }
    /// Lean, 0...1 with 0.5 upright: the pitch wheel. Called while dragging.
    var onLean: (Double) -> Void = { _ in }
    var onGrab: () -> Void = { }
    var onRelease: () -> Void = { }

    /// Leans about the socket; holds the rod, and the ball over it.
    private let stick = UIView()
    private let rod = UIImageView()
    private let ball = UIImageView()
    private let parts: S1TemplateJoystick
    private var pixel = CGPoint(x: 1, y: 1)

    /// How far the ball slides along the rod, in the painting's pixels. The rod is painted on
    /// up behind the ball for exactly this much, and the ball covers no more than is there.
    static let slideUp: CGFloat = 7
    static let slideDown: CGFloat = 8

    /// How far a drag travels for the whole range, and the lean ignored around upright so that
    /// a push meant for the mod wheel does not also bend the pitch.
    static let travel: CGFloat = 36
    static let deadZone: CGFloat = 0.15

    private var grabbedAt: CGPoint?
    private(set) var push: Double = 0
    private(set) var lean: Double = 0.5

    init(parts: S1TemplateJoystick) {
        self.parts = parts
        super.init(frame: .zero)
        rod.image = UIImage.synthOne(parts.rodImageName)
        ball.image = UIImage.synthOne(parts.ballImageName)
        stick.isUserInteractionEnabled = false
        stick.addSubview(rod)
        stick.addSubview(ball)
        addSubview(stick)
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("Joystick", comment: "The Cabinet skin's joystick")
        accessibilityHint = NSLocalizedString("Drag up for the mod wheel, sideways to bend the pitch",
                                              comment: "Accessibility hint")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let reach = parts.reach
        pixel = CGPoint(x: bounds.width / reach.width, y: bounds.height / reach.height)
        func placed(_ box: CGRect) -> CGRect {
            CGRect(x: (box.minX - reach.minX) * pixel.x, y: (box.minY - reach.minY) * pixel.y,
                   width: box.width * pixel.x, height: box.height * pixel.y)
        }
        // The stick fills the view and turns about the socket, so its parts keep plain frames
        let lean = stick.transform
        let slide = ball.transform
        stick.transform = .identity
        ball.transform = .identity
        stick.layer.anchorPoint = CGPoint(x: (parts.pivot.x - reach.minX) / reach.width,
                                          y: (parts.pivot.y - reach.minY) / reach.height)
        stick.bounds = bounds
        stick.layer.position = CGPoint(x: bounds.width * stick.layer.anchorPoint.x, y: bounds.height * stick.layer.anchorPoint.y)
        rod.frame = placed(parts.rodBox)
        ball.frame = placed(parts.ballBox)
        stick.transform = lean
        ball.transform = slide
    }

    // MARK: - Dragging

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        grabbedAt = touch.location(in: self)
        onGrab()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let grabbedAt else { return }
        let here = touch.location(in: self)
        drag(by: CGPoint(x: here.x - grabbedAt.x, y: here.y - grabbedAt.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release() }

    /// A drag of `offset` points from where the stick was grabbed. Up is a push.
    func drag(by offset: CGPoint) {
        let x = max(-1, min(1, offset.x / Self.travel))
        let y = max(-1, min(1, -offset.y / Self.travel))
        let leaning = abs(x) <= Self.deadZone ? 0 : (x - Self.deadZone * (x < 0 ? -1 : 1)) / (1 - Self.deadZone)
        let newPush = Double(max(0, y))
        let newLean = 0.5 + Double(leaning) * 0.5
        pose(lean: x, push: y)
        if newPush != push { push = newPush; onPush(newPush) }
        if newLean != lean { lean = newLean; onLean(newLean) }
    }

    func release() {
        guard grabbedAt != nil || push != 0 || lean != 0.5 else { return }
        grabbedAt = nil
        push = 0
        lean = 0.5
        onRelease()
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.stick.transform = .identity
            self.ball.transform = .identity
        }
    }

    /// The rod leans about its socket; the ball slides along it, up for a push away and down,
    /// over the rod, for a pull forward. No scaling anywhere.
    private func pose(lean: CGFloat, push: CGFloat) {
        stick.transform = CGAffineTransform(rotationAngle: lean * 0.5)
        let slide = push >= 0 ? -push * Self.slideUp : -push * Self.slideDown
        ball.transform = CGAffineTransform(translationX: 0, y: slide * pixel.y)
    }

    // MARK: - For tests

    var stickTransform: CGAffineTransform { stick.transform }
    var ballTransform: CGAffineTransform { ball.transform }
}
