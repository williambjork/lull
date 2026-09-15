import Foundation

/// The baby's own baseline, derived entirely from `SleepEvent`s.
/// Nothing here is hand-maintained; rebuild it whenever events change.
public struct BabySleepProfile: Codable, Equatable, Sendable {
    public var babyId: UUID
    public var generatedAt: Date
    public var lookbackDays: Int

    public var averageNapDurationMinutes: Int?
    public var medianNapDurationMinutes: Int?

    public var averageNightSleepMinutes: Int?
    public var medianNightSleepMinutes: Int?

    public var averageTotalSleep24hMinutes: Int?
    public var medianTotalSleep24hMinutes: Int?

    public var medianWakeWindowMinutes: Int?

    public var medianWakeWindowByNap: [Int: Int]
    public var medianNapDurationByNap: [Int: Int]
    public var sampleCountsByNap: [Int: Int]

    /// Median wake window before bedtime (the last stretch of the day).
    public var medianWakeWindowBeforeNightMinutes: Int?
    public var nightWakeWindowSampleCount: Int

    /// Habitual clock times, in minutes from local midnight.
    public var medianBedtimeMinutesFromMidnight: Int?
    public var medianMorningWakeMinutesFromMidnight: Int?

    public var medianNapsPerDay: Double?
    public var daysWithData: Int

    public init(
        babyId: UUID,
        generatedAt: Date = Date(),
        lookbackDays: Int,
        averageNapDurationMinutes: Int? = nil,
        medianNapDurationMinutes: Int? = nil,
        averageNightSleepMinutes: Int? = nil,
        medianNightSleepMinutes: Int? = nil,
        averageTotalSleep24hMinutes: Int? = nil,
        medianTotalSleep24hMinutes: Int? = nil,
        medianWakeWindowMinutes: Int? = nil,
        medianWakeWindowByNap: [Int: Int] = [:],
        medianNapDurationByNap: [Int: Int] = [:],
        sampleCountsByNap: [Int: Int] = [:],
        medianWakeWindowBeforeNightMinutes: Int? = nil,
        nightWakeWindowSampleCount: Int = 0,
        medianBedtimeMinutesFromMidnight: Int? = nil,
        medianMorningWakeMinutesFromMidnight: Int? = nil,
        medianNapsPerDay: Double? = nil,
        daysWithData: Int = 0
    ) {
        self.babyId = babyId
        self.generatedAt = generatedAt
        self.lookbackDays = lookbackDays
        self.averageNapDurationMinutes = averageNapDurationMinutes
        self.medianNapDurationMinutes = medianNapDurationMinutes
        self.averageNightSleepMinutes = averageNightSleepMinutes
        self.medianNightSleepMinutes = medianNightSleepMinutes
        self.averageTotalSleep24hMinutes = averageTotalSleep24hMinutes
        self.medianTotalSleep24hMinutes = medianTotalSleep24hMinutes
        self.medianWakeWindowMinutes = medianWakeWindowMinutes
        self.medianWakeWindowByNap = medianWakeWindowByNap
        self.medianNapDurationByNap = medianNapDurationByNap
        self.sampleCountsByNap = sampleCountsByNap
        self.medianWakeWindowBeforeNightMinutes = medianWakeWindowBeforeNightMinutes
        self.nightWakeWindowSampleCount = nightWakeWindowSampleCount
        self.medianBedtimeMinutesFromMidnight = medianBedtimeMinutesFromMidnight
        self.medianMorningWakeMinutesFromMidnight = medianMorningWakeMinutesFromMidnight
        self.medianNapsPerDay = medianNapsPerDay
        self.daysWithData = daysWithData
    }

    public static func empty(babyId: UUID, lookbackDays: Int) -> BabySleepProfile {
        BabySleepProfile(babyId: babyId, lookbackDays: lookbackDays)
    }

    public var hasAnyData: Bool { daysWithData > 0 }
}
