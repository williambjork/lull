import Foundation

public struct SleepClassificationInput: Sendable {
    public let startedAt: Date
    public let endedAt: Date?
    public let ageMonths: Double
    /// Other events belonging to the same sleep day, used so a 17:30 sleep can
    /// be read in context instead of against a fixed clock rule.
    public let sameDayEvents: [SleepEvent]
    public let sleepProfile: BabySleepProfile?
    public let calendar: SleepDayCalendar

    public init(
        startedAt: Date,
        endedAt: Date?,
        ageMonths: Double,
        sameDayEvents: [SleepEvent],
        sleepProfile: BabySleepProfile?,
        calendar: SleepDayCalendar
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.ageMonths = ageMonths
        self.sameDayEvents = sameDayEvents
        self.sleepProfile = sleepProfile
        self.calendar = calendar
    }

    public var durationMinutes: Int? {
        guard let endedAt, endedAt >= startedAt else { return nil }
        return SleepEvent.minutes(from: startedAt, to: endedAt)
    }
}

public struct SleepClassificationResult: Sendable, Equatable {
    public let type: SleepType
    /// Stored on the event so the decision stays explainable later.
    public let reason: String
    /// True when the call was genuinely close (typically the 17:00–19:00 zone).
    public let isAmbiguous: Bool

    public init(type: SleepType, reason: String, isAmbiguous: Bool = false) {
        self.type = type
        self.reason = reason
        self.isAmbiguous = isAmbiguous
    }
}

/// Replaceable: the app only ever talks to this protocol, so the heuristic can
/// be swapped for a better one without touching storage or the UI.
public protocol SleepClassifying: Sendable {
    var version: String { get }
    func classify(_ input: SleepClassificationInput) -> SleepClassificationResult
}

/// Time of day *and* surrounding events decide nap vs night — not a single
/// clock threshold.
public struct HeuristicSleepClassifier: SleepClassifying {

    public struct Configuration: Sendable, Equatable {
        /// A sleep this long, starting in the evening, is night sleep.
        public var longSleepMinutes: Int
        /// Sleeps shorter than this in the evening are still catnaps.
        public var eveningCatnapCeilingMinutes: Int
        /// At or after this local time, sleep is night sleep unless it is clearly a catnap.
        public var confidentNightStartHour: Int
        /// Start of the genuinely ambiguous late-afternoon zone.
        public var ambiguousZoneStartHour: Int
        /// How close to the baby's habitual bedtime counts as "this is bedtime".
        public var bedtimeMatchToleranceMinutes: Int
        /// Minimum days of history before the habitual bedtime is trusted.
        public var minDaysForPersonalBedtime: Int
        /// Without personal data, an evening sleep of at least this long is night sleep.
        public var fallbackNightDurationMinutes: Int

        public init(
            longSleepMinutes: Int = 300,
            eveningCatnapCeilingMinutes: Int = 90,
            confidentNightStartHour: Int = 19,
            ambiguousZoneStartHour: Int = 17,
            bedtimeMatchToleranceMinutes: Int = 75,
            minDaysForPersonalBedtime: Int = 5,
            fallbackNightDurationMinutes: Int = 240
        ) {
            self.longSleepMinutes = longSleepMinutes
            self.eveningCatnapCeilingMinutes = eveningCatnapCeilingMinutes
            self.confidentNightStartHour = confidentNightStartHour
            self.ambiguousZoneStartHour = ambiguousZoneStartHour
            self.bedtimeMatchToleranceMinutes = bedtimeMatchToleranceMinutes
            self.minDaysForPersonalBedtime = minDaysForPersonalBedtime
            self.fallbackNightDurationMinutes = fallbackNightDurationMinutes
        }

        public static let `default` = Configuration()
    }

    public let configuration: Configuration
    public let version = "heuristic-classifier-1"

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func classify(_ input: SleepClassificationInput) -> SleepClassificationResult {
        let calendar = input.calendar
        // Evening-anchored so 01:00 reads as "late", not "very early".
        let startMinutes = calendar.eveningAnchoredMinutes(of: input.startedAt)
        let duration = input.durationMinutes

        // After midnight and before the day boundary: this is night sleep,
        // typically a waking in the middle of the night.
        if startMinutes >= 24 * 60 {
            return SleepClassificationResult(type: .night, reason: "Started overnight")
        }

        // Already had night sleep today and this starts later: still night.
        let hadNightSleepEarlier = input.sameDayEvents.contains {
            $0.type == .night && $0.startedAt < input.startedAt
        }
        if hadNightSleepEarlier {
            return SleepClassificationResult(type: .night, reason: "Follows night sleep in the same night")
        }

        // A long sleep beginning in the evening is night sleep.
        if let duration,
           duration >= configuration.longSleepMinutes,
           startMinutes >= configuration.ambiguousZoneStartHour * 60 {
            return SleepClassificationResult(type: .night, reason: "Long sleep starting in the evening")
        }

        if startMinutes >= configuration.confidentNightStartHour * 60 {
            // A brief evening sleep is a catnap even at 19:30 — common in young babies.
            if let duration, duration <= configuration.eveningCatnapCeilingMinutes {
                return SleepClassificationResult(
                    type: .nap,
                    reason: "Short sleep in the evening",
                    isAmbiguous: true
                )
            }
            return SleepClassificationResult(type: .night, reason: "Started at typical night-sleep time")
        }

        // The genuinely ambiguous zone: could be a late nap or bedtime, and only
        // this baby's established pattern can really tell them apart.
        if startMinutes >= configuration.ambiguousZoneStartHour * 60 {
            if let habitualBedtime = personalBedtimeMinutes(input),
               abs(startMinutes - habitualBedtime) <= configuration.bedtimeMatchToleranceMinutes,
               duration == nil || (duration ?? 0) >= configuration.fallbackNightDurationMinutes {
                return SleepClassificationResult(
                    type: .night,
                    reason: "Matches this baby's usual bedtime",
                    isAmbiguous: true
                )
            }
            if let duration, duration >= configuration.fallbackNightDurationMinutes {
                return SleepClassificationResult(
                    type: .night,
                    reason: "Long sleep in the late afternoon",
                    isAmbiguous: true
                )
            }
            return SleepClassificationResult(
                type: .nap,
                reason: "Late-afternoon sleep, shorter than bedtime sleep",
                isAmbiguous: true
            )
        }

        return SleepClassificationResult(type: .nap, reason: "Daytime sleep")
    }

    private func personalBedtimeMinutes(_ input: SleepClassificationInput) -> Int? {
        guard
            let profile = input.sleepProfile,
            profile.daysWithData >= configuration.minDaysForPersonalBedtime,
            let bedtime = profile.medianBedtimeMinutesFromMidnight
        else { return nil }
        return bedtime
    }
}
