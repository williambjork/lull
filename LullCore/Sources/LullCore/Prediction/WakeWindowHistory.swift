import Foundation

/// One historical wake window, with the context needed to compare it — and the
/// context later personalisation will need (e.g. "after a short nap this baby
/// usually has a shorter wake window").
public struct WakeWindowSample: Sendable, Equatable {
    public let eventId: UUID
    public let day: SleepDay
    public let startedAt: Date
    public let minutes: Int
    public let sleepType: SleepType
    public let napIndex: Int?
    public let previousSleepDurationMinutes: Int?
    public let previousSleepType: SleepType?
}

/// How closely the matched history actually matches the transition being predicted.
public enum HistoryMatchQuality: String, Sendable, Equatable {
    /// Same sleep type and same nap number.
    case exactTransition
    /// Same sleep type, nap number within ±1.
    case neighbouringNap
    /// Same sleep type, any nap number.
    case sameTypeOnly
}

public struct MatchedWakeWindowHistory: Sendable, Equatable {
    public let samples: [WakeWindowSample]
    public let quality: HistoryMatchQuality

    public var minutes: [Int] { samples.map(\.minutes) }
    public var sampleSize: Int { samples.count }

    /// Median, not mean: robust against the one day the whole schedule fell apart.
    public var medianMinutes: Double? { Statistics.median(minutes) }

    /// Relative spread, used to decide whether "high" confidence is honest.
    public var relativeDispersion: Double? {
        guard let median = medianMinutes, median > 0,
              let mad = Statistics.medianAbsoluteDeviation(minutes.map(Double.init))
        else { return nil }
        return mad / median
    }

    public static let empty = MatchedWakeWindowHistory(samples: [], quality: .exactTransition)
}

/// Selects the historical wake windows that are comparable to the transition we
/// are predicting: same baby, same sleep type, same-ish nap index, recent,
/// completed sleeps only, unusual days excluded.
public struct WakeWindowHistoryMatcher: Sendable {
    public let analytics: SleepAnalytics
    public let profileBuilder: SleepProfileBuilder

    public init(analytics: SleepAnalytics) {
        self.analytics = analytics
        self.profileBuilder = SleepProfileBuilder(analytics: analytics)
    }

    public func match(
        plan: NextSleepPlan,
        events: [SleepEvent],
        dayFlags: [DayFlag],
        asOf now: Date,
        config: PredictionConfig
    ) -> MatchedWakeWindowHistory {
        let all = comparableSamples(events: events, dayFlags: dayFlags, asOf: now, config: config)

        switch plan.type {
        case .night:
            // Bedtime only: night wakings are a different animal entirely.
            let samples = all.filter { $0.sleepType == .night }
            return MatchedWakeWindowHistory(samples: samples, quality: .exactTransition)

        case .nap:
            let naps = all.filter { $0.sleepType == .nap }
            guard let targetIndex = plan.napIndex else {
                return MatchedWakeWindowHistory(samples: naps, quality: .sameTypeOnly)
            }

            let exact = naps.filter { $0.napIndex == targetIndex }
            if exact.count >= config.minSamplesForPersonal || !config.allowsNeighbouringNapIndexFallback {
                return MatchedWakeWindowHistory(samples: exact, quality: .exactTransition)
            }

            let neighbouring = naps.filter { sample in
                guard let index = sample.napIndex else { return false }
                return abs(index - targetIndex) <= 1
            }
            if neighbouring.count >= config.minSamplesForPersonal {
                return MatchedWakeWindowHistory(samples: neighbouring, quality: .neighbouringNap)
            }
            if naps.count >= config.minSamplesForPersonal {
                return MatchedWakeWindowHistory(samples: naps, quality: .sameTypeOnly)
            }
            // Not enough of anything: return the exact match and let the engine
            // fall back to the age prior.
            return MatchedWakeWindowHistory(samples: exact, quality: .exactTransition)
        }
    }

    /// All usable wake-window observations within the lookback window.
    public func comparableSamples(
        events: [SleepEvent],
        dayFlags: [DayFlag],
        asOf now: Date,
        config: PredictionConfig
    ) -> [WakeWindowSample] {
        let calendar = analytics.calendar
        let completed = events.completedChronologically
        let unusual = analytics.unusualDays(
            events: events,
            dayFlags: dayFlags,
            excludedContexts: config.excludedContexts
        )
        let cutoffDay = calendar.adding(days: -config.lookbackDays, to: calendar.day(for: now))

        return completed.compactMap { event -> WakeWindowSample? in
            guard let minutes = event.wakeWindowBeforeMinutes else { return nil }
            let day = calendar.day(for: event.startedAt)
            guard day > cutoffDay, !unusual.contains(day) else { return nil }
            // Night wakings are not a wake window anyone wants to plan around.
            if event.type == .night, !profileBuilder.isBedtimeTransition(event, in: completed) { return nil }

            let previous = completed
                .filter { $0.id != event.id && ($0.endedAt ?? $0.startedAt) <= event.startedAt }
                .max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }

            return WakeWindowSample(
                eventId: event.id,
                day: day,
                startedAt: event.startedAt,
                minutes: minutes,
                sleepType: event.type,
                napIndex: event.napIndex,
                previousSleepDurationMinutes: previous?.durationMinutes,
                previousSleepType: previous?.type
            )
        }
    }
}
