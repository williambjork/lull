import Foundation

public enum SleepTrendKind: String, Codable, Sendable {
    case possibleNapTransition
}

/// A soft observation about a pattern. Wording matters: transitions happen
/// gradually and differ between children, so the app suggests, never declares.
public struct SleepTrendSignal: Sendable, Equatable, Identifiable {
    public let kind: SleepTrendKind
    public let headline: String
    public let detail: String
    /// What in the data prompted this, so the parent can judge it themselves.
    public let evidence: [String]
    public let confidence: PredictionConfidence

    public var id: String { kind.rawValue }
}

/// Looks for the shape of a nap transition: fewer naps, longer wake windows,
/// stable total sleep, and one nap that keeps being refused or cut short.
public struct SleepTrendDetector: Sendable {

    public struct Configuration: Sendable, Equatable {
        public var recentDays: Int
        public var comparisonDays: Int
        public var minDaysWithData: Int
        /// How many of the four signals must agree before we say anything.
        public var minSignals: Int
        public var shortNapMinutes: Int
        public var wakeWindowIncreaseRatio: Double
        public var stableTotalSleepToleranceMinutes: Int
        public var shortLastNapDayShare: Double

        public init(
            recentDays: Int = 5,
            comparisonDays: Int = 9,
            minDaysWithData: Int = 10,
            minSignals: Int = 2,
            shortNapMinutes: Int = 25,
            wakeWindowIncreaseRatio: Double = 0.1,
            stableTotalSleepToleranceMinutes: Int = 45,
            shortLastNapDayShare: Double = 0.4
        ) {
            self.recentDays = recentDays
            self.comparisonDays = comparisonDays
            self.minDaysWithData = minDaysWithData
            self.minSignals = minSignals
            self.shortNapMinutes = shortNapMinutes
            self.wakeWindowIncreaseRatio = wakeWindowIncreaseRatio
            self.stableTotalSleepToleranceMinutes = stableTotalSleepToleranceMinutes
            self.shortLastNapDayShare = shortLastNapDayShare
        }

        public static let `default` = Configuration()
    }

    public let analytics: SleepAnalytics
    public let configuration: Configuration

    public init(analytics: SleepAnalytics, configuration: Configuration = .default) {
        self.analytics = analytics
        self.configuration = configuration
    }

    public func detect(
        events: [SleepEvent],
        dayFlags: [DayFlag],
        asOf now: Date
    ) -> [SleepTrendSignal] {
        let calendar = analytics.calendar
        let today = calendar.day(for: now)
        // Today is still in progress, so it cannot be compared with whole days.
        let usable = analytics
            .allSummaries(events: events, dayFlags: dayFlags)
            .filter { !$0.isUnusual && $0.day != today && $0.totalSleepMinutes > 0 }
            .sorted { $0.day > $1.day }

        guard usable.count >= configuration.minDaysWithData else { return [] }

        let recent = Array(usable.prefix(configuration.recentDays))
        let prior = Array(usable.dropFirst(configuration.recentDays).prefix(configuration.comparisonDays))
        guard recent.count >= 3, prior.count >= 3 else { return [] }

        var evidence: [String] = []
        var signals = 0

        // 1. Fewer naps than before.
        let recentNaps = Statistics.median(recent.map(\.napCount)) ?? 0
        let priorNaps = Statistics.median(prior.map(\.napCount)) ?? 0
        let fewerNaps = priorNaps - recentNaps >= 0.5
        if fewerNaps {
            signals += 1
            evidence.append("Naps per day: about \(format(priorNaps)) before, about \(format(recentNaps)) recently")
        }

        // 2. Progressively longer wake windows.
        let recentWindows = recent.flatMap(\.wakeWindowsMinutes)
        let priorWindows = prior.flatMap(\.wakeWindowsMinutes)
        if let recentMedian = Statistics.median(recentWindows),
           let priorMedian = Statistics.median(priorWindows),
           priorMedian > 0,
           (recentMedian - priorMedian) / priorMedian >= configuration.wakeWindowIncreaseRatio {
            signals += 1
            evidence.append(
                "Awake stretches are longer: about \(DurationFormatting.compact(Int(priorMedian))) before, "
                + "about \(DurationFormatting.compact(Int(recentMedian))) recently"
            )
        }

        // 3. Total sleep holding steady (a transition, not a sleep problem).
        if let recentTotal = Statistics.median(recent.map(\.totalSleepMinutes)),
           let priorTotal = Statistics.median(prior.map(\.totalSleepMinutes)),
           abs(recentTotal - priorTotal) <= Double(configuration.stableTotalSleepToleranceMinutes) {
            signals += 1
            evidence.append("Total sleep is holding steady at about \(DurationFormatting.compact(Int(recentTotal))) a day")
        }

        // 4. One nap repeatedly refused or very short.
        let daysWithShortLastNap = recent.filter { summary in
            guard let lastNap = summary.napDurationsMinutes.last else { return false }
            return lastNap < configuration.shortNapMinutes
        }.count
        let shortNapShare = Double(daysWithShortLastNap) / Double(recent.count)
        if shortNapShare >= configuration.shortLastNapDayShare {
            signals += 1
            evidence.append("The last nap of the day has been very short on \(daysWithShortLastNap) of the last \(recent.count) days")
        }

        guard signals >= configuration.minSignals, fewerNaps || shortNapShare >= configuration.shortLastNapDayShare else {
            return []
        }

        return [
            SleepTrendSignal(
                kind: .possibleNapTransition,
                headline: "Possible nap transition",
                detail: "Your baby's recent pattern looks like it may be moving toward fewer naps.",
                evidence: evidence,
                // Deliberately never "high": this is a hint, not a diagnosis.
                confidence: signals >= 3 ? .medium : .low
            )
        ]
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
