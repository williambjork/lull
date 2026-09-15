import Foundation

/// Every number the prediction heuristic leans on, in one place.
///
/// These weights are an application heuristic, not a clinically validated
/// formula. They are configurable precisely so they can be improved later with
/// real product data instead of being rewritten in code.
public struct PredictionConfig: Sendable, Equatable {

    // MARK: History matching

    /// Recent history only: this baby three months ago is a different baby.
    public var lookbackDays: Int
    /// Below this many comparable observations we use the age prior alone.
    public var minSamplesForPersonal: Int
    /// At or above this many observations we lean on personal history hardest.
    public var strongHistorySampleCount: Int
    /// When the exact nap index has too little data, widen to neighbouring naps.
    public var allowsNeighbouringNapIndexFallback: Bool
    /// Contexts whose days are excluded from personal history.
    public var excludedContexts: Set<SleepContext>

    // MARK: Weighting

    /// Personal weight with 5–9 comparable observations.
    public var personalWeightSomeHistory: Double
    /// Personal weight with 10+ comparable observations.
    public var personalWeightStrongHistory: Double

    // MARK: Output shape

    /// Half-width of the displayed range. The clock is a guide, not a deadline.
    public var rangePaddingMinutes: Int
    public var minTargetMinutes: Int
    public var maxTargetMinutes: Int

    // MARK: Confidence

    /// Above this relative spread (MAD ÷ median) the baby simply is not
    /// consistent yet, so confidence is capped even with lots of data.
    public var highConfidenceMaxRelativeDispersion: Double

    // MARK: Bedtime

    /// Bedtime is partly clock-anchored, not purely wake-window driven. This is
    /// how much weight the baby's habitual bedtime gets for night predictions.
    public var bedtimeAnchorWeight: Double
    public var minBedtimeSamplesForAnchor: Int
    /// Without personal data, a predicted sleep starting after this local time
    /// is treated as bedtime rather than another nap.
    public var defaultBedtimeThresholdMinutes: Int
    /// Earliest local hour at which "they have had their usual naps" can imply bedtime.
    public var earliestHourForBedtimeInference: Int

    public init(
        lookbackDays: Int = 14,
        minSamplesForPersonal: Int = 5,
        strongHistorySampleCount: Int = 10,
        allowsNeighbouringNapIndexFallback: Bool = true,
        excludedContexts: Set<SleepContext> = [.unusualDay],
        personalWeightSomeHistory: Double = 0.7,
        personalWeightStrongHistory: Double = 0.8,
        rangePaddingMinutes: Int = 15,
        minTargetMinutes: Int = 20,
        maxTargetMinutes: Int = 8 * 60,
        highConfidenceMaxRelativeDispersion: Double = 0.2,
        bedtimeAnchorWeight: Double = 0.5,
        minBedtimeSamplesForAnchor: Int = 5,
        defaultBedtimeThresholdMinutes: Int = 18 * 60 + 30,
        earliestHourForBedtimeInference: Int = 14
    ) {
        self.lookbackDays = lookbackDays
        self.minSamplesForPersonal = minSamplesForPersonal
        self.strongHistorySampleCount = strongHistorySampleCount
        self.allowsNeighbouringNapIndexFallback = allowsNeighbouringNapIndexFallback
        self.excludedContexts = excludedContexts
        self.personalWeightSomeHistory = personalWeightSomeHistory
        self.personalWeightStrongHistory = personalWeightStrongHistory
        self.rangePaddingMinutes = rangePaddingMinutes
        self.minTargetMinutes = minTargetMinutes
        self.maxTargetMinutes = maxTargetMinutes
        self.highConfidenceMaxRelativeDispersion = highConfidenceMaxRelativeDispersion
        self.bedtimeAnchorWeight = bedtimeAnchorWeight
        self.minBedtimeSamplesForAnchor = minBedtimeSamplesForAnchor
        self.defaultBedtimeThresholdMinutes = defaultBedtimeThresholdMinutes
        self.earliestHourForBedtimeInference = earliestHourForBedtimeInference
    }

    public static let `default` = PredictionConfig()

    /// Personal weight for a given amount of comparable history.
    /// 0–4 observations: age prior only · 5–9: 70% personal · 10+: 80% personal.
    public func personalWeight(forSampleSize sampleSize: Int) -> Double {
        if sampleSize < minSamplesForPersonal { return 0 }
        if sampleSize < strongHistorySampleCount { return personalWeightSomeHistory }
        return personalWeightStrongHistory
    }
}
