import Foundation

public struct SleepHistoryFilter: Sendable, Equatable {
    /// How far back to look. Recent history describes the baby better than all
    /// history: a 9-month-old's 4-month-old pattern is irrelevant.
    public var lookbackDays: Int
    /// Days marked with any of these contexts are left out of personal stats.
    public var excludedContexts: Set<SleepContext>
    /// Leave the in-progress day out of per-day medians (it is incomplete).
    public var excludesCurrentDay: Bool

    public init(
        lookbackDays: Int = 14,
        excludedContexts: Set<SleepContext> = [.unusualDay],
        excludesCurrentDay: Bool = true
    ) {
        self.lookbackDays = lookbackDays
        self.excludedContexts = excludedContexts
        self.excludesCurrentDay = excludesCurrentDay
    }

    public static let `default` = SleepHistoryFilter()
    /// Durations are more stable than wake windows, so they tolerate a longer window.
    public static let durations = SleepHistoryFilter(lookbackDays: 28)
}

/// Builds `BabySleepProfile` from raw events. Pure derivation: throw the result
/// away and rebuild it whenever anything changes.
public struct SleepProfileBuilder: Sendable {
    public let analytics: SleepAnalytics

    public init(analytics: SleepAnalytics) {
        self.analytics = analytics
    }

    public func build(
        babyId: UUID,
        events: [SleepEvent],
        dayFlags: [DayFlag],
        asOf now: Date,
        wakeWindowFilter: SleepHistoryFilter = .default,
        durationFilter: SleepHistoryFilter = .durations
    ) -> BabySleepProfile {
        let calendar = analytics.calendar
        let unusual = analytics.unusualDays(
            events: events,
            dayFlags: dayFlags,
            excludedContexts: wakeWindowFilter.excludedContexts
        )
        let completed = events.completedChronologically

        let durationEvents = filter(completed, using: durationFilter, unusual: unusual, asOf: now)
        let windowEvents = filter(completed, using: wakeWindowFilter, unusual: unusual, asOf: now)

        let naps = durationEvents.filter { $0.type == .nap }
        let nights = durationEvents.filter { $0.type == .night && isBedtimeTransition($0, in: completed) }

        let napDurations = naps.compactMap(\.durationMinutes)
        let nightDurations = nights.compactMap(\.durationMinutes)

        // Per-day values, ignoring incomplete and unusual days.
        let summaries = analytics.allSummaries(events: events, dayFlags: dayFlags)
            .filter { summary in
                guard !unusual.contains(summary.day) else { return false }
                if durationFilter.excludesCurrentDay, summary.day == calendar.day(for: now) { return false }
                let cutoff = calendar.adding(days: -durationFilter.lookbackDays, to: calendar.day(for: now))
                return summary.day > cutoff
            }
        let dailyTotals = summaries.map(\.totalSleepMinutes).filter { $0 > 0 }
        let napCounts = summaries.filter { $0.totalSleepMinutes > 0 }.map(\.napCount)

        // Wake windows grouped by the nap they precede.
        var windowsByNap: [Int: [Int]] = [:]
        var napDurationsByNap: [Int: [Int]] = [:]
        for event in windowEvents where event.type == .nap {
            guard let index = event.napIndex else { continue }
            if let window = event.wakeWindowBeforeMinutes {
                windowsByNap[index, default: []].append(window)
            }
            if let duration = event.durationMinutes {
                napDurationsByNap[index, default: []].append(duration)
            }
        }

        let nightWakeWindows = windowEvents
            .filter { $0.type == .night && isBedtimeTransition($0, in: completed) }
            .compactMap(\.wakeWindowBeforeMinutes)

        let allWakeWindows = windowEvents
            .filter { $0.type == .nap }
            .compactMap(\.wakeWindowBeforeMinutes)

        let bedtimes = nights.map { calendar.eveningAnchoredMinutes(of: $0.startedAt) }
        let morningWakes = nights.compactMap { event -> Int? in
            guard let endedAt = event.endedAt else { return nil }
            return calendar.minutesFromMidnight(of: endedAt)
        }

        return BabySleepProfile(
            babyId: babyId,
            generatedAt: now,
            lookbackDays: wakeWindowFilter.lookbackDays,
            averageNapDurationMinutes: Statistics.mean(napDurations)?.rounded().intValue,
            medianNapDurationMinutes: Statistics.median(napDurations)?.rounded().intValue,
            averageNightSleepMinutes: Statistics.mean(nightDurations)?.rounded().intValue,
            medianNightSleepMinutes: Statistics.median(nightDurations)?.rounded().intValue,
            averageTotalSleep24hMinutes: Statistics.mean(dailyTotals)?.rounded().intValue,
            medianTotalSleep24hMinutes: Statistics.median(dailyTotals)?.rounded().intValue,
            medianWakeWindowMinutes: Statistics.median(allWakeWindows)?.rounded().intValue,
            medianWakeWindowByNap: windowsByNap.compactMapValues { Statistics.median($0)?.rounded().intValue },
            medianNapDurationByNap: napDurationsByNap.compactMapValues { Statistics.median($0)?.rounded().intValue },
            sampleCountsByNap: windowsByNap.mapValues(\.count),
            medianWakeWindowBeforeNightMinutes: Statistics.median(nightWakeWindows)?.rounded().intValue,
            nightWakeWindowSampleCount: nightWakeWindows.count,
            medianBedtimeMinutesFromMidnight: Statistics.median(bedtimes)?.rounded().intValue,
            medianMorningWakeMinutesFromMidnight: Statistics.median(morningWakes)?.rounded().intValue,
            medianNapsPerDay: Statistics.median(napCounts),
            daysWithData: summaries.count
        )
    }

    /// A night sleep that follows a nap (or nothing) is the bedtime transition.
    /// One that follows another night sleep is a night waking, which would
    /// otherwise pollute bedtime and night-length stats.
    public func isBedtimeTransition(_ event: SleepEvent, in completed: [SleepEvent]) -> Bool {
        guard event.type == .night else { return false }
        let previous = completed
            .filter { $0.id != event.id && ($0.endedAt ?? $0.startedAt) <= event.startedAt }
            .max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
        guard let previous else { return true }
        return previous.type != .night
    }

    private func filter(
        _ events: [SleepEvent],
        using filter: SleepHistoryFilter,
        unusual: Set<SleepDay>,
        asOf now: Date
    ) -> [SleepEvent] {
        let calendar = analytics.calendar
        let today = calendar.day(for: now)
        let cutoff = calendar.adding(days: -filter.lookbackDays, to: today)
        return events.filter { event in
            let day = calendar.day(for: event.startedAt)
            guard day > cutoff else { return false }
            guard !unusual.contains(day) else { return false }
            return true
        }
    }
}

extension Double {
    var intValue: Int { Int(self) }
}
