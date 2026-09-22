//
//  S1PowerCycle.hpp
//  Arcade Ruins
//
//  X3-9 (ADR-091): the cabinet's red buttons cut and restore the power — the SCHEDULE of it.
//
//  A port of `S1CabinetPower.run(powered:)` (ADR-062, the Mac's, 2026-09-17), and **no JUCE in
//  here**: which zone changes when, how many times it blinks on the way and what it looks like at
//  any moment are arithmetic, so the whole eight-second cycle is tested in microseconds with no
//  window and no clock (ADR-086's pattern).
//
//  The owner's words, of the Cabinet painting's console: the left red button should "randomly
//  flicker off the panels until it seems like the synth has slowly shut down from losing power
//  (no highlight colors) and the synth UI is in grayscale", the right one bring them back the
//  same way, "each cycle … about 8 seconds."
//
//  **A look and nothing else**: every control works and sounds in the dark.
//
#ifndef S1_POWER_CYCLE_HPP
#define S1_POWER_CYCLE_HPP

#include <cstdint>
#include <string>
#include <vector>

namespace s1plugin {

/// One zone's schedule: when it settles, and the blinks before it.
struct PowerZonePlan {
    std::string zone;
    double settlesAt = 0;              ///< seconds from the press
    std::vector<double> blinkAt;       ///< each moment it flips, before it settles
};

/// The cycle as a whole. Ask it what a zone looks like at a moment; nothing here draws.
class PowerCycle {
public:
    /// The Mac's numbers: the first zone settles a second in and the last at eight, and each
    /// blinks two to four times in the 0.35–0.9 s before it settles.
    static constexpr double kFirstSettles = 1.0, kLastSettles = 8.0;
    static constexpr double kBlinkWindowShortest = 0.35, kBlinkWindowLongest = 0.9;
    static constexpr int kFewestBlinks = 2, kMostBlinks = 4;

    /// `seed` makes the shuffle and the blinks repeatable, which is how they are tested.
    PowerCycle(std::vector<std::string> zones, bool toPowered, uint32_t seed);

    /// True when the cycle's target is "lit".
    bool towardsPowered() const { return powered; }
    double length() const { return kLastSettles; }
    const std::vector<PowerZonePlan> &plans() const { return schedule; }

    /// Whether `zone` is LIT at `seconds` from the press. **A cycle is given only the zones that
    /// still have to change** (ADR-062: "zones still to change, shuffled"), so a zone nobody
    /// planned is one that is ALREADY where this cycle is going: the answer is `powered`. It
    /// answered `!powered` until 2026-09-22, which assumed every zone started in the opposite
    /// state — true of a cycle begun at rest, false of one begun in the middle of another, and
    /// that is what blacked out the lit half of the interface when the other button was pressed
    /// part way through (ADR-099).
    bool isLit(const std::string &zone, double seconds) const;
    /// Every zone that has settled by `seconds`.
    int settledBy(double seconds) const;
    /// Nothing is left to do.
    bool isFinished(double seconds) const { return seconds >= kLastSettles; }

private:
    bool powered;
    std::vector<PowerZonePlan> schedule;
};

} // namespace s1plugin

#endif
