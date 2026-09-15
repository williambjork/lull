import Foundation

/// Small statistics helpers used across the derived-analytics layer.
///
/// Medians are preferred over means throughout the prediction path: a single
/// travel day or illness day can drag an average a long way, while the median
/// barely moves.
public enum Statistics {

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    public static func median(_ values: [Int]) -> Double? {
        median(values.map(Double.init))
    }

    public static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public static func mean(_ values: [Int]) -> Double? {
        mean(values.map(Double.init))
    }

    /// Median absolute deviation: a robust measure of spread.
    public static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let center = median(values) else { return nil }
        return median(values.map { abs($0 - center) })
    }

    public static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let average = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    /// Linear interpolation between two anchors, clamped outside the anchor range.
    public static func interpolate(
        x: Double,
        x0: Double,
        y0: Double,
        x1: Double,
        y1: Double
    ) -> Double {
        guard x1 != x0 else { return (y0 + y1) / 2 }
        let t = (x - x0) / (x1 - x0)
        return y0 + (y1 - y0) * min(max(t, 0), 1)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
