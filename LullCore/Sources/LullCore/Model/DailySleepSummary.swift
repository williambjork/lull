import Foundation

/// Derived, regenerable roll-up for one sleep day. Never edited by hand.
public struct DailySleepSummary: Codable, Equatable, Identifiable, Sendable {
    public var day: SleepDay
    public var daytimeSleepMinutes: Int
    public var nightSleepMinutes: Int
    public var napCount: Int
    public var napDurationsMinutes: [Int]
    public var wakeWindowsMinutes: [Int]

    /// Morning wake: the end of the night sleep that this day starts from.
    public var morningWakeAt: Date?
    /// Start of the night sleep that closes this day.
    public var bedtimeAt: Date?
    public var isUnusual: Bool

    public var id: SleepDay { day }

    public init(
        day: SleepDay,
        daytimeSleepMinutes: Int,
        nightSleepMinutes: Int,
        napCount: Int,
        napDurationsMinutes: [Int],
        wakeWindowsMinutes: [Int],
        morningWakeAt: Date?,
        bedtimeAt: Date?,
        isUnusual: Bool
    ) {
        self.day = day
        self.daytimeSleepMinutes = daytimeSleepMinutes
        self.nightSleepMinutes = nightSleepMinutes
        self.napCount = napCount
        self.napDurationsMinutes = napDurationsMinutes
        self.wakeWindowsMinutes = wakeWindowsMinutes
        self.morningWakeAt = morningWakeAt
        self.bedtimeAt = bedtimeAt
        self.isUnusual = isUnusual
    }

    public var totalSleepMinutes: Int { daytimeSleepMinutes + nightSleepMinutes }

    public var longestNapMinutes: Int? { napDurationsMinutes.max() }
    public var shortestNapMinutes: Int? { napDurationsMinutes.min() }
}
