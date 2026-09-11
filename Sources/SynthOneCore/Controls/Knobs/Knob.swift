//
//  KnobView.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 7/20/17.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import UIKit

@IBDesignable
public class Knob: UIView, UIGestureRecognizerDelegate, S1Control {

    // MARK: - Init / Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityTraits = [
            .adjustable,
            .allowsDirectInteraction,
            .updatesFrequently
        ]
        // PORT (P3-5): upstream sets up gestures only in `init?(coder:)`, because
        // every knob comes out of a storyboard — so a knob built in code had none.
        // Latent upstream; a trap the moment anything constructs one.
        commonInit()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.isUserInteractionEnabled = true
        contentMode = .redraw

        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        doubleTapGesture.delegate = self
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        // P3-5: scroll-wheel support. `allowedTouchTypes = []` is the important
        // part — it makes this recogniser respond *only* to indirect scroll events,
        // so it never competes with the click-drag in `touchesMoved`.
        let scrollGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scrollGesture.allowedScrollTypesMask = .all
        scrollGesture.allowedTouchTypes = []
        addGestureRecognizer(scrollGesture)
    }

    override public func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        contentMode = .scaleAspectFit
        clipsToBounds = true
    }

    public class override var requiresConstraintBasedLayout: Bool {
        return true
    }

    // MARK: - Properties

    var onlyIntegers: Bool = false

    public var taper: Double = 1.0 // Linear by default

    var range: ClosedRange = 0.0...1.0 {
        didSet {
            _value = range.clamp(_value)
            knobValue = CGFloat(Double(knobValue).normalized(from: range, taper: taper))
        }
    }

    private var _value: Double = 0

    var knobValue: CGFloat = 0.0 {
        didSet {
            setNeedsDisplay()
        }
    }

    var knobFill: CGFloat = 0

    var knobSensitivity: CGFloat = 0.005

    var lastX: CGFloat = 0

    var lastY: CGFloat = 0

    lazy private var accessibilityChangeAmount: Double = {
        let widthOfRange = range.upperBound - range.lowerBound

        // We need Not to include 1.0
        let incrementRange: Range = 1.1..<128.0

        if incrementRange.contains(widthOfRange) && onlyIntegers {
            return 1.0
        } else {
            return widthOfRange * 0.01
        }

    }()

    // MARK: - S1Control

    var value: Double {
        get {
            return _value
        }
        set(newValue) {
            _value = onlyIntegers ? round(newValue) : newValue
            _value = range.clamp(_value)
            knobValue = CGFloat(newValue.normalized(from: range, taper: taper))
            accessibilityValue = onlyIntegers ?
                String(format: "%.0f", _value) :
                String(format: "%.2f", _value)
        }
    }

    var setValueCallback: (Double) -> Void = { _ in }

    var resetToDefaultCallback: () -> Void = { }

    // MARK: - Draw

    public override func draw(_ rect: CGRect) {
        KnobStyleKit.drawKnobOne(frame: CGRect(x: 0,
                                               y: 0,
                                               width: self.bounds.width,
                                               height: self.bounds.height),
                                 knobValue: knobValue)
    }

    // MARK: - Touches

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {

        for touch in touches {
            let touchPoint = touch.location(in: self)
            lastX = touchPoint.x
            lastY = touchPoint.y
        }
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {

        // P3-5: hold ⌥ for a finer drag. A knob that spans 20 kHz of cutoff in
        // 200 points of travel cannot be set precisely with a mouse otherwise —
        // this is the desktop equivalent of the iPad's larger absolute travel.
        let fine = event?.modifierFlags.contains(.alternate) ?? false
        for touch in touches {
            let touchPoint = touch.location(in: self)
            setPercentagesWithTouchPoint(touchPoint, fine: fine)
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {

        for _ in touches {
            setValueCallback(value)
        }
    }

    @objc public func handleTap(_ sender: Knob) {
        resetToDefaultCallback()
    }

    // MARK: - Pointer input (P3-5)

    /// How much ⌥ slows a drag or a scroll down by.
    static let fineAdjustmentFactor: CGFloat = 0.2

    /// Scroll deltas arrive far larger than drag deltas, so they get their own
    /// scale. Tuned so one notch of a mouse wheel is a small, deliberate step and a
    /// trackpad swipe sweeps the range without feeling loose.
    static let scrollSensitivity: CGFloat = 0.0015

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)

        let fine = gesture.modifierFlags.contains(.alternate)
        let scale = Self.scrollSensitivity * (fine ? Self.fineAdjustmentFactor : 1)
        // Same convention as dragging: up increases.
        apply(delta: -translation.y * scale)

        if gesture.state == .ended || gesture.state == .cancelled {
            setValueCallback(value)
        }
    }

    /// Move the knob by a normalised amount and publish the result.
    private func apply(delta: CGFloat) {
        guard delta != 0 else { return }
        knobValue = (0.0 ... 1.0).clamp(knobValue + delta)
        value = valueForCurrentKnobValue()
        setValueCallback(value)
    }

    /// The value this knob's current travel represents.
    ///
    /// PORT (P3-5): factored out so `RateKnob` can express the *one* thing it
    /// varies — reading its value off the tempo-synced rate instead of the taper —
    /// rather than duplicating the whole drag routine to change one line. It had to
    /// change anyway to gain ⌥ and the scroll wheel, and two copies would have
    /// drifted.
    func valueForCurrentKnobValue() -> Double {
        Double(knobValue).denormalized(to: range, taper: taper)
    }

    func setPercentagesWithTouchPoint(_ touchPoint: CGPoint, fine: Bool = false) {

        let sensitivity = knobSensitivity * (fine ? Self.fineAdjustmentFactor : 1)
        // Knobs assume up or right is increasing, and down or left is decreasing
        knobValue += (touchPoint.x - lastX) * sensitivity
        knobValue -= (touchPoint.y - lastY) * sensitivity
        knobValue = (0.0 ... 1.0).clamp(knobValue)
        value = valueForCurrentKnobValue()
        setValueCallback(value)
        lastX = touchPoint.x
        lastY = touchPoint.y
    }

    // MARK: - Accessibility

	override public func accessibilityIncrement() {}

	override public func accessibilityDecrement() {}
}
