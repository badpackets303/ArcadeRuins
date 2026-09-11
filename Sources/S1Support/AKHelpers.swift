//  The slice of AudioKit's AudioKitHelpers.swift that the ported Table and
//  Microtonality sources actually need. Ported verbatim from AudioKit 4.9.2
//  (MIT) — see Sources/S1Support/PORTING.md. Names kept per ADR-009.

import Foundation

extension Array where Element: FloatingPoint {
    /// Create an array of zeros
    ///
    /// - parameter count: Number of elements in the array
    ///
    public init(zeros count: Int) {
        self.init(repeating: 0, count: count)
    }
}

extension ClosedRange {
    /// Clamp value to the range
    ///
    /// - parameter value: Value to clamp
    ///
    public func clamp(_ value: Bound) -> Bound {
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

/// AudioKit defines a prefix operator for boolean negation and uses it inside the
/// Scala parser and tuning validation. Ported verbatim so those files need no edits.
prefix operator ❗️

/// Negate a boolean.
prefix public func ❗️(a: Bool) -> Bool {
    return !a
}

/// Taper conversions between a knob's [0, 1] travel and a parameter's range.
/// Ported from AudioKit 4.9.2's `AudioKitHelpers.swift` (MIT) at P3-1, when the
/// knobs and steppers came across. The deprecated `minimum:maximum:` spellings are
/// not reproduced — Synth One uses only the `ClosedRange` ones.
extension Double {

    /// Return a value on [minimum, maximum] to a [0, 1] range, according to a taper
    ///
    /// - Parameters:
    ///   - range: Source range (cannot contain zero if taper is not positive)
    ///   - taper: For taper > 0, there is an algebraic curve, taper = 1 is linear, and taper < 0 is exponential
    ///
    public func normalized(from range: ClosedRange<Double>, taper: Double = 1) -> Double {
        assert(!(range.contains(0.0) && taper < 0), "Cannot have negative taper with a range containing zero.")

        if taper > 0 {
            // algebraic taper
            return pow(((self - range.lowerBound) / (range.upperBound - range.lowerBound)), (1.0 / taper))
        } else {
            // exponential taper
            return range.lowerBound * exp(log(range.upperBound / range.lowerBound) * self)
        }
    }

    /// Return a value on [0, 1] to a [minimum, maximum] range, according to a taper
    ///
    /// - Parameters:
    ///   - range: Target range (cannot contain zero if taper is not positive)
    ///   - taper: For taper > 0, there is an algebraic curve, taper = 1 is linear, and taper < 0 is exponential
    ///
    public func denormalized(to range: ClosedRange<Double>, taper: Double = 1) -> Double {
        assert(!(range.contains(0.0) && taper < 0), "Cannot have negative taper with a range containing zero.")

        // Avoiding division by zero in this trivial case
        if range.upperBound - range.lowerBound < 0.000_01 {
            return range.lowerBound
        }

        if taper > 0 {
            // algebraic taper
            return range.lowerBound + (range.upperBound - range.lowerBound) * pow(self, taper)
        } else {
            // exponential taper
            var adjustedMinimum: Double = 0.0
            var adjustedMaximum: Double = 0.0
            if range.lowerBound == 0 { adjustedMinimum = 0.000_000_000_01 }
            if range.upperBound == 0 { adjustedMaximum = 0.000_000_000_01 }

            return log(self / adjustedMinimum) / log(adjustedMaximum / adjustedMinimum)
        }
    }
}
