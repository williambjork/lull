import Foundation

public struct SleepDerivationConfig: Sendable, Equatable {
    /// Longer gaps than this are treated as missing data rather than a real
    /// wake window (the parent probably forgot to track a sleep).
    public var maxPlausibleWakeWindowMinutes: Int

    public init(maxPlausibleWakeWindowMinutes: Int = 16 * 60) {
        self.maxPlausibleWakeWindowMinutes = maxPlausibleWakeWindowMinutes
    }

    public static let `default` = SleepDerivationConfig()
}

/// Recomputes the structural derived fields — nap index and preceding wake
/// window — from the raw events.
///
/// This runs after every change because a retroactively added sleep renumbers
/// the naps around it. Classification is deliberately *not* recomputed here:
/// the stored nap/night label keeps history reproducible.
public enum SleepDerivation {

    public static func recomputeDerivedFields(
        events: [SleepEvent],
        calendar: SleepDayCalendar,
        config: SleepDerivationConfig = .default
    ) -> [SleepEvent] {
        var sorted = events.sorted { $0.startedAt < $1.startedAt }
        sorted = assignWakeWindows(to: sorted, config: config)
        sorted = assignNapIndices(to: sorted, calendar: calendar)
        return sorted
    }

    /// Wake window is measured from real sleep to real sleep:
    /// `currentSleep.startedAt - previousSleep.endedAt`. No bedtime or clock
    /// assumptions are involved.
    public static func assignWakeWindows(
        to events: [SleepEvent],
        config: SleepDerivationConfig = .default
    ) -> [SleepEvent] {
        let sorted = events.sorted { $0.startedAt < $1.startedAt }
        var result: [SleepEvent] = []
        result.reserveCapacity(sorted.count)

        for event in sorted {
            var updated = event
            let previousWake = sorted
                .compactMap { candidate -> Date? in
                    guard candidate.id != event.id, let endedAt = candidate.endedAt else { return nil }
                    guard endedAt <= event.startedAt else { return nil }
                    return endedAt
                }
                .max()
            updated.wakeWindowBeforeMinutes = previousWake.flatMap {
                wakeWindowMinutes(from: $0, to: event.startedAt, config: config)
            }
            result.append(updated)
        }
        return result
    }

    public static func wakeWindowMinutes(
        from previousWake: Date,
        to sleepStart: Date,
        config: SleepDerivationConfig = .default
    ) -> Int? {
        guard sleepStart >= previousWake else { return nil }
        let minutes = SleepEvent.minutes(from: previousWake, to: sleepStart)
        guard minutes <= config.maxPlausibleWakeWindowMinutes else { return nil }
        return minutes
    }

    /// Naps are numbered 1…n within their sleep day. Night sleep gets no index.
    public static func assignNapIndices(
        to events: [SleepEvent],
        calendar: SleepDayCalendar
    ) -> [SleepEvent] {
        var indexByEvent: [UUID: Int] = [:]
        let napsByDay = Dictionary(grouping: events.filter { $0.type == .nap }) { event in
            calendar.day(for: event.startedAt)
        }
        for (_, naps) in napsByDay {
            for (offset, nap) in naps.sorted(by: { $0.startedAt < $1.startedAt }).enumerated() {
                indexByEvent[nap.id] = offset + 1
            }
        }
        return events.map { event in
            var updated = event
            updated.napIndex = event.type == .nap ? indexByEvent[event.id] : nil
            return updated
        }
    }

    /// The wake period the baby is currently in: it starts when the last
    /// completed sleep ended.
    public static func currentWakeStart(events: [SleepEvent]) -> (date: Date, sourceEventId: UUID)? {
        guard let last = events.lastCompleted, let endedAt = last.endedAt else { return nil }
        return (endedAt, last.id)
    }
}
