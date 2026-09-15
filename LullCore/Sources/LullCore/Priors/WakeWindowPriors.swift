import Foundation

/// A span of awake time. Always a range: published wake-window charts are
/// practical heuristics, not clinically validated rules, so the product never
/// pretends there is one correct number of minutes.
public struct WakeWindowRange: Codable, Equatable, Sendable {
    public let minMinutes: Int
    public let maxMinutes: Int

    public init(minMinutes: Int, maxMinutes: Int) {
        self.minMinutes = min(minMinutes, maxMinutes)
        self.maxMinutes = max(minMinutes, maxMinutes)
    }

    /// The prior's target value, i.e. the middle of the published range.
    public var midpointMinutes: Int { (minMinutes + maxMinutes) / 2 }
}

/// One published age band.
public struct WakeWindowPrior: Equatable, Sendable {
    public let minMonths: Double
    public let maxMonths: Double
    public let minMinutes: Int
    public let maxMinutes: Int

    public init(minMonths: Double, maxMonths: Double, minMinutes: Int, maxMinutes: Int) {
        self.minMonths = minMonths
        self.maxMonths = maxMonths
        self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes
    }

    /// Bands are treated as being centred on their mid-age, and values between
    /// band centres are interpolated.
    public var anchorMonths: Double { (minMonths + maxMonths) / 2 }
    public var range: WakeWindowRange { WakeWindowRange(minMinutes: minMinutes, maxMinutes: maxMinutes) }
}

/// The age prior, plus how much the engine should trust it.
public struct AgeWakeWindowPrior: Equatable, Sendable {
    public let ageMonths: Double
    public let range: WakeWindowRange
    /// True past the last published band, where any single number would be invented.
    public let isExtrapolated: Bool
    /// 1.0 while inside published bands, decaying through toddlerhood.
    public let reliability: Double
    /// From roughly a year, nap structure and total sleep matter more than
    /// wake-window arithmetic.
    public let emphasizeNapStructure: Bool

    public var targetMinutes: Int { range.midpointMinutes }
}

public enum WakeWindowPriors {

    /// Broad defaults, not hard rules. Ranges are the commonly published
    /// practical guidance; the gaps between bands are interpolated rather than
    /// filled in with invented precision.
    public static let bands: [WakeWindowPrior] = [
        WakeWindowPrior(minMonths: 0, maxMonths: 1, minMinutes: 30, maxMinutes: 60),
        WakeWindowPrior(minMonths: 1, maxMonths: 3, minMinutes: 60, maxMinutes: 120),
        WakeWindowPrior(minMonths: 3, maxMonths: 4, minMinutes: 75, maxMinutes: 150),
        WakeWindowPrior(minMonths: 5, maxMonths: 7, minMinutes: 120, maxMinutes: 240),
        WakeWindowPrior(minMonths: 7, maxMonths: 10, minMinutes: 150, maxMinutes: 270),
        WakeWindowPrior(minMonths: 10, maxMonths: 12, minMinutes: 180, maxMinutes: 360)
    ]

    /// Age at which the wake-window heuristic starts losing usefulness.
    public static let napStructureEmphasisMonths: Double = 12
    /// Reliability floor for toddlers, so the age prior never disappears entirely.
    public static let toddlerReliabilityFloor: Double = 0.3
    /// Age by which reliability has decayed to the floor.
    public static let toddlerReliabilityFloorMonths: Double = 24

    public static func prior(forAgeMonths ageMonths: Double, bands: [WakeWindowPrior] = bands) -> AgeWakeWindowPrior {
        let sorted = bands.sorted { $0.anchorMonths < $1.anchorMonths }
        precondition(!sorted.isEmpty, "At least one wake-window prior band is required")

        let age = max(0, ageMonths)
        let range = interpolatedRange(forAgeMonths: age, bands: sorted)
        let lastPublishedMonth = sorted.map(\.maxMonths).max() ?? 0
        let isExtrapolated = age > lastPublishedMonth

        return AgeWakeWindowPrior(
            ageMonths: age,
            range: range,
            isExtrapolated: isExtrapolated,
            reliability: reliability(forAgeMonths: age),
            emphasizeNapStructure: age >= napStructureEmphasisMonths
        )
    }

    /// Piecewise-linear between band centres. A 4.5-month-old lands between the
    /// 3–4 and 5–7 month bands instead of jumping from one to the other.
    private static func interpolatedRange(forAgeMonths age: Double, bands: [WakeWindowPrior]) -> WakeWindowRange {
        guard let first = bands.first, let last = bands.last else {
            return WakeWindowRange(minMinutes: 0, maxMinutes: 0)
        }
        if age <= first.anchorMonths { return first.range }
        // Past the last band we hold the last published range rather than
        // extrapolating a toddler wake window that nobody has measured.
        if age >= last.anchorMonths { return last.range }

        for (lower, upper) in zip(bands, bands.dropFirst()) where age >= lower.anchorMonths && age <= upper.anchorMonths {
            let minMinutes = Statistics.interpolate(
                x: age,
                x0: lower.anchorMonths, y0: Double(lower.minMinutes),
                x1: upper.anchorMonths, y1: Double(upper.minMinutes)
            )
            let maxMinutes = Statistics.interpolate(
                x: age,
                x0: lower.anchorMonths, y0: Double(lower.maxMinutes),
                x1: upper.anchorMonths, y1: Double(upper.maxMinutes)
            )
            return WakeWindowRange(
                minMinutes: roundedToFiveMinutes(minMinutes),
                maxMinutes: roundedToFiveMinutes(maxMinutes)
            )
        }
        return last.range
    }

    /// Full trust inside the published bands, then a linear decay to a floor so
    /// toddler predictions lean on the baby's own pattern instead.
    public static func reliability(forAgeMonths ageMonths: Double) -> Double {
        guard ageMonths > napStructureEmphasisMonths else { return 1.0 }
        let decayed = Statistics.interpolate(
            x: ageMonths,
            x0: napStructureEmphasisMonths, y0: 1.0,
            x1: toddlerReliabilityFloorMonths, y1: toddlerReliabilityFloor
        )
        return decayed.clamped(to: toddlerReliabilityFloor...1.0)
    }

    /// Rounding to five minutes keeps interpolated values honest-looking.
    private static func roundedToFiveMinutes(_ minutes: Double) -> Int {
        Int((minutes / 5).rounded()) * 5
    }
}
