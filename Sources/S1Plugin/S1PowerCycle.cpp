//
//  S1PowerCycle.cpp
//  Arcade Ruins
//
//  X3-9 (ADR-091). See the header; the numbers are `S1CabinetPower`'s (ADR-062).
//
#include "S1PowerCycle.hpp"

#include <algorithm>

namespace s1plugin {
namespace {

/// A small deterministic generator, so a cycle can be replayed exactly in a test on every OS —
/// `std::shuffle`'s results are not the same across standard libraries.
struct Rolling {
    uint32_t state;
    explicit Rolling(uint32_t seed) : state(seed == 0 ? 0x9e3779b9u : seed) {}
    uint32_t next() {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        return state;
    }
    /// 0…1
    double unit() { return double(next() % 100000u) / 100000.0; }
    int upTo(int count) { return count <= 0 ? 0 : int(next() % uint32_t(count)); }
};

} // namespace

PowerCycle::PowerCycle(std::vector<std::string> zones, bool toPowered, uint32_t seed) : powered(toPowered) {
    Rolling rolling(seed);
    // "zones still to change, shuffled" — Fisher-Yates, so every order is as likely.
    for (int i = int(zones.size()) - 1; i > 0; --i) {
        const int j = rolling.upTo(i + 1);
        std::swap(zones[size_t(i)], zones[size_t(j)]);
    }
    schedule.reserve(zones.size());
    const int count = int(zones.size());
    for (int i = 0; i < count; ++i) {
        PowerZonePlan plan;
        plan.zone = zones[size_t(i)];
        // The first settles at one second and the last at eight, spread evenly between.
        plan.settlesAt = count <= 1 ? kFirstSettles
                                    : kFirstSettles + (kLastSettles - kFirstSettles) * double(i) / double(count - 1);
        const double window = kBlinkWindowShortest + (kBlinkWindowLongest - kBlinkWindowShortest) * rolling.unit();
        const int blinks = kFewestBlinks + rolling.upTo(kMostBlinks - kFewestBlinks + 1);
        for (int b = 0; b < blinks; ++b) {
            // Inside the window before it settles, in order.
            plan.blinkAt.push_back(plan.settlesAt - window + window * (double(b) + 0.5) / double(blinks));
        }
        schedule.push_back(std::move(plan));
    }
}

bool PowerCycle::isLit(const std::string &zone, double seconds) const {
    for (const PowerZonePlan &plan : schedule) {
        if (plan.zone != zone) { continue; }
        if (seconds >= plan.settlesAt) { return powered; }
        // Before its window it is as it was; inside it, each blink flips it.
        int flips = 0;
        for (const double at : plan.blinkAt) { if (seconds >= at) { ++flips; } }
        const bool was = !powered;
        return (flips % 2 == 0) ? was : powered;
    }
    return powered;      // nobody planned it: it is already where this cycle is going
}

int PowerCycle::settledBy(double seconds) const {
    int count = 0;
    for (const PowerZonePlan &plan : schedule) { if (seconds >= plan.settlesAt) { ++count; } }
    return count;
}

} // namespace s1plugin
