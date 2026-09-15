import Foundation

/// Read-only analytics over raw events. Nothing here is persisted: every value
/// can be regenerated from `SleepEvent`s at any time.
///
/// Day attribution, which parents care about more than they realise:
/// * naps count towards the sleep day they *start* in;
/// * night sleep counts towards the calendar day it *ends* in, so during
///   Tuesday the app shows the night that ran from Monday evening as
///   "last night", which is what a parent means by "sleep today".
public struct SleepAnalytics: Sendable {
    public let calendar: SleepDayCalendar
    public let derivationConfig: SleepDerivationConfig

    public init(calendar: SleepDayCalendar, derivationConfig: SleepDerivationConfig = .default) {
        self.calendar = calendar
        self.derivationConfig = derivationConfig
    }

    // MARK: - Day attribution

    public func attributedDay(for event: SleepEvent) -> SleepDay? {
        switch event.type {
        case .nap:
            return calendar.day(for: event.startedAt)
        case .night:
            guard let endedAt = event.endedAt else { return nil }
            let components = calendar.calendar.dateComponents([.year, .month, .day], from: endedAt)
            return SleepDay(
                year: components.year ?? 1970,
                month: components.month ?? 1,
                day: components.day ?? 1
            )
        }
    }

    // MARK: - Totals

    /// Minutes of sleep overlapping an arbitrary window. Events are clipped to
    /// the window, so a night that straddles the boundary contributes only the
    /// part that falls inside it.
    public func sleepMinutes(in window: DateInterval, events: [SleepEvent]) -> Int {
        let seconds = events.completedChronologically.reduce(0.0) { total, event in
            guard let interval = event.interval, let overlap = interval.intersection(with: window) else {
                return total
            }
            return total + overlap.duration
        }
        return Int((seconds / 60).rounded())
    }

    /// Rolling 24-hour total. Active timers are excluded until they are stopped.
    public func totalSleep24hMinutes(asOf now: Date, events: [SleepEvent]) -> Int {
        let window = DateInterval(start: now.addingTimeInterval(-24 * 60 * 60), end: now)
        return sleepMinutes(in: window, events: events)
    }

    // MARK: - Daily summaries

    public func summary(for day: SleepDay, events: [SleepEvent], dayFlags: [DayFlag]) -> DailySleepSummary {
        let completed = events.completedChronologically
        let dayEvents = completed.filter { attributedDay(for: $0) == day }
        let naps = dayEvents.filter { $0.type == .nap }.sorted { $0.startedAt < $1.startedAt }
        let nights = dayEvents.filter { $0.type == .night }

        let napDurations = naps.compactMap(\.durationMinutes)
        let nightMinutes = nights.compactMap(\.durationMinutes).reduce(0, +)

        // The morning wake that opens this day: the longest night sleep ending in it.
        let morningWake = nights
            .max { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }
            .flatMap(\.endedAt)

        // The bedtime that closes this day: night sleep starting within this sleep day.
        let bedtime = completed
            .filter { $0.type == .night && calendar.day(for: $0.startedAt) == day }
            .min { $0.startedAt < $1.startedAt }
            .map(\.startedAt)

        let wakeWindows = dayEvents.compactMap(\.wakeWindowBeforeMinutes)

        return DailySleepSummary(
            day: day,
            daytimeSleepMinutes: napDurations.reduce(0, +),
            nightSleepMinutes: nightMinutes,
            napCount: naps.count,
            napDurationsMinutes: napDurations,
            wakeWindowsMinutes: wakeWindows,
            morningWakeAt: morningWake,
            bedtimeAt: bedtime,
            isUnusual: unusualDays(events: events, dayFlags: dayFlags).contains(day)
        )
    }

    /// Summaries for the most recent `days` sleep days, newest first.
    public func recentSummaries(
        days: Int,
        asOf now: Date,
        events: [SleepEvent],
        dayFlags: [DayFlag]
    ) -> [DailySleepSummary] {
        let today = calendar.day(for: now)
        let oldest = calendar.adding(days: -(max(1, days) - 1), to: today)
        return calendar.days(from: oldest, to: today)
            .reversed()
            .map { summary(for: $0, events: events, dayFlags: dayFlags) }
    }

    /// Summaries for every day that actually has data, newest first.
    public func allSummaries(events: [SleepEvent], dayFlags: [DayFlag]) -> [DailySleepSummary] {
        let days = Set(events.completedChronologically.compactMap { attributedDay(for: $0) })
        return days.sorted(by: >).map { summary(for: $0, events: events, dayFlags: dayFlags) }
    }

    // MARK: - Unusual days

    /// Days the parent marked, plus days containing an event tagged with an
    /// excluded context. Used only for filtering, never to adjust a calculation.
    public func unusualDays(
        events: [SleepEvent],
        dayFlags: [DayFlag],
        excludedContexts: Set<SleepContext> = [.unusualDay]
    ) -> Set<SleepDay> {
        var days = Set<SleepDay>()
        for flag in dayFlags where !excludedContexts.isDisjoint(with: Set(flag.contexts)) {
            days.insert(flag.day)
        }
        for event in events where !excludedContexts.isDisjoint(with: Set(event.contexts)) {
            days.insert(calendar.day(for: event.startedAt))
        }
        return days
    }

    // MARK: - Awake time

    public func awakeMinutes(asOf now: Date, events: [SleepEvent]) -> Int? {
        guard events.activeEvent == nil,
              let wakeStart = SleepDerivation.currentWakeStart(events: events)?.date,
              now >= wakeStart
        else { return nil }
        return SleepEvent.minutes(from: wakeStart, to: now)
    }
}
