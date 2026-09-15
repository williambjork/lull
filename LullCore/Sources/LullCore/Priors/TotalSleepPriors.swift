import Foundation

/// Recommended total sleep in 24 hours, by age. These ranges have stronger
/// evidence behind them than wake-window charts, but they are still context for
/// the parent — never a verdict on a single day.
public struct TotalSleepPrior: Equatable, Sendable {
    public let minMonths: Double
    public let maxMonths: Double
    public let minMinutes: Int
    public let maxMinutes: Int

    public var anchorMonths: Double { (minMonths + maxMonths) / 2 }
}

public struct TotalSleepRange: Equatable, Sendable {
    public let minMinutes: Int
    public let maxMinutes: Int

    public var minHours: Double { Double(minMinutes) / 60 }
    public var maxHours: Double { Double(maxMinutes) / 60 }
}

public enum TotalSleepPriors {

    /// 0–3 months: 14–17h · 4–12 months: 12–16h · 1–2 years: 11–14h
    /// (naps included where applicable)
    public static let bands: [TotalSleepPrior] = [
        TotalSleepPrior(minMonths: 0, maxMonths: 3, minMinutes: 14 * 60, maxMinutes: 17 * 60),
        TotalSleepPrior(minMonths: 4, maxMonths: 12, minMinutes: 12 * 60, maxMinutes: 16 * 60),
        TotalSleepPrior(minMonths: 12, maxMonths: 24, minMinutes: 11 * 60, maxMinutes: 14 * 60)
    ]

    public static func range(forAgeMonths ageMonths: Double) -> TotalSleepRange {
        let sorted = bands.sorted { $0.anchorMonths < $1.anchorMonths }
        guard let first = sorted.first, let last = sorted.last else {
            return TotalSleepRange(minMinutes: 0, maxMinutes: 0)
        }
        let age = max(0, ageMonths)
        if age <= first.anchorMonths {
            return TotalSleepRange(minMinutes: first.minMinutes, maxMinutes: first.maxMinutes)
        }
        if age >= last.anchorMonths {
            return TotalSleepRange(minMinutes: last.minMinutes, maxMinutes: last.maxMinutes)
        }
        for (lower, upper) in zip(sorted, sorted.dropFirst()) where age >= lower.anchorMonths && age <= upper.anchorMonths {
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
            return TotalSleepRange(
                minMinutes: Int((minMinutes / 15).rounded()) * 15,
                maxMinutes: Int((maxMinutes / 15).rounded()) * 15
            )
        }
        return TotalSleepRange(minMinutes: last.minMinutes, maxMinutes: last.maxMinutes)
    }
}
