import Foundation

/// Which sleep we think is coming next.
public struct NextSleepPlan: Sendable, Equatable {
    public let type: SleepType
    /// 1-based nap number, `nil` when the next sleep is night sleep.
    public let napIndex: Int?
    public let reason: String

    public init(type: SleepType, napIndex: Int?, reason: String) {
        self.type = type
        self.napIndex = napIndex
        self.reason = reason
    }
}

/// Works out whether the next sleep is nap 1, nap 2, … or bedtime.
///
/// Babies are never forced into a fixed number of naps: the count comes from
/// what this baby has actually been doing, and from the clock only as a backstop.
public struct NextSleepPlanner: Sendable {
    public let calendar: SleepDayCalendar

    public init(calendar: SleepDayCalendar) {
        self.calendar = calendar
    }

    public func plan(
        events: [SleepEvent],
        now: Date,
        tentativeStart: Date?,
        sleepProfile: BabySleepProfile,
        config: PredictionConfig
    ) -> NextSleepPlan {
        let today = calendar.day(for: now)
        let completed = events.completedChronologically
        let todaysEvents = completed.filter { calendar.day(for: $0.startedAt) == today }
        let napsToday = todaysEvents.filter { $0.type == .nap }.count
        let expectedNapIndex = napsToday + 1

        // Bedtime already started today, so anything further is night sleep.
        let hasStartedNightToday = todaysEvents.contains { $0.type == .night }
        if hasStartedNightToday {
            return NextSleepPlan(type: .night, napIndex: nil, reason: "Night sleep has already started")
        }

        let referenceStart = tentativeStart ?? now
        let referenceMinutes = calendar.eveningAnchoredMinutes(of: referenceStart)
        let bedtimeThreshold = bedtimeThresholdMinutes(sleepProfile: sleepProfile, config: config)

        if referenceMinutes >= bedtimeThreshold {
            return NextSleepPlan(
                type: .night,
                napIndex: nil,
                reason: "Next sleep lands at this baby's usual bedtime"
            )
        }

        // This baby has had the number of naps they usually have, and it is late
        // enough in the day that bedtime is the more likely next sleep.
        if let medianNaps = sleepProfile.medianNapsPerDay,
           sleepProfile.daysWithData >= config.minSamplesForPersonal,
           Double(expectedNapIndex) > medianNaps.rounded(),
           calendar.localHour(of: referenceStart) >= config.earliestHourForBedtimeInference {
            return NextSleepPlan(
                type: .night,
                napIndex: nil,
                reason: "Already had the usual number of naps today"
            )
        }

        return NextSleepPlan(
            type: .nap,
            napIndex: expectedNapIndex,
            reason: napsToday == 0 ? "First nap of the day" : "Follows nap \(napsToday)"
        )
    }

    /// Bedtime is judged against this baby's own bedtime when we know it,
    /// falling back to a broad default otherwise.
    public func bedtimeThresholdMinutes(sleepProfile: BabySleepProfile, config: PredictionConfig) -> Int {
        guard
            let bedtime = sleepProfile.medianBedtimeMinutesFromMidnight,
            sleepProfile.daysWithData >= config.minBedtimeSamplesForAnchor
        else {
            return config.defaultBedtimeThresholdMinutes
        }
        // Within 45 minutes of the usual bedtime, treat it as bedtime.
        return bedtime - 45
    }
}
