import Foundation

/// What we can say about a cue today.
public struct SleepCueStat: Sendable, Equatable, Identifiable {
    public let cue: SleepCue
    public let occurrences: Int
    public let medianSleepDurationMinutes: Int?
    public let medianWakeWindowMinutes: Int?

    public var id: String { cue.rawValue }
}

/// Groundwork for cue personalisation, not an MVP feature.
///
/// The interesting question — "after eye rubbing, this baby is usually asleep
/// within 18 ± 7 minutes" — needs a timestamp per observed cue. Cues are
/// currently recorded against the sleep, not the moment they were seen, so this
/// only reports what each cue tends to precede. Add `observedAt` to cues when
/// the feature is picked up properly.
public struct CueAnalytics: Sendable {
    public let analytics: SleepAnalytics
    public let minOccurrences: Int

    public init(analytics: SleepAnalytics, minOccurrences: Int = 5) {
        self.analytics = analytics
        self.minOccurrences = minOccurrences
    }

    public func stats(events: [SleepEvent]) -> [SleepCueStat] {
        let completed = events.completedChronologically
        return SleepCue.allCases.compactMap { cue in
            let matching = completed.filter { $0.sleepCuesObserved.contains(cue) }
            guard matching.count >= minOccurrences else { return nil }
            return SleepCueStat(
                cue: cue,
                occurrences: matching.count,
                medianSleepDurationMinutes: Statistics.median(matching.compactMap(\.durationMinutes))
                    .map { Int($0.rounded()) },
                medianWakeWindowMinutes: Statistics.median(matching.compactMap(\.wakeWindowBeforeMinutes))
                    .map { Int($0.rounded()) }
            )
        }
    }
}
