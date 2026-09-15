import Foundation

/// Maps instants onto sleep days in the baby's timezone.
///
/// The boundary is `dayStartHour` (05:00 by default) rather than midnight, so a
/// bedtime at 19:30 and the 02:00 waking that follows it belong to the same
/// sleep day. Nap numbering and daily totals depend on this.
public struct SleepDayCalendar: Sendable, Equatable {
    public let timeZone: TimeZone
    public let dayStartHour: Int
    public let calendar: Calendar

    public init(timeZone: TimeZone = .current, dayStartHour: Int = 5) {
        self.timeZone = timeZone
        self.dayStartHour = dayStartHour.clamped(to: 0...12)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public init(profile: BabyProfile, dayStartHour: Int = 5) {
        self.init(timeZone: profile.timezone, dayStartHour: dayStartHour)
    }

    public func day(for date: Date) -> SleepDay {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        var reference = date
        if (components.hour ?? 0) < dayStartHour {
            reference = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        let shifted = calendar.dateComponents([.year, .month, .day], from: reference)
        return SleepDay(
            year: shifted.year ?? 1970,
            month: shifted.month ?? 1,
            day: shifted.day ?? 1
        )
    }

    public func start(of day: SleepDay) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = dayStartHour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public func end(of day: SleepDay) -> Date {
        start(of: adding(days: 1, to: day))
    }

    public func interval(of day: SleepDay) -> DateInterval {
        DateInterval(start: start(of: day), end: end(of: day))
    }

    public func adding(days: Int, to day: SleepDay) -> SleepDay {
        let date = calendar.date(byAdding: .day, value: days, to: start(of: day)) ?? start(of: day)
        return self.day(for: date)
    }

    /// Inclusive list of sleep days, oldest first.
    public func days(from first: SleepDay, to last: SleepDay) -> [SleepDay] {
        guard first <= last else { return [] }
        var result: [SleepDay] = []
        var cursor = first
        while cursor <= last, result.count < 3652 {
            result.append(cursor)
            cursor = adding(days: 1, to: cursor)
        }
        return result
    }

    public func localHour(of date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    public func minutesFromMidnight(of date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Minutes from midnight, shifted past 24h for early-morning times, so that
    /// a 23:50 bedtime and a 00:10 bedtime average sensibly instead of cancelling out.
    public func eveningAnchoredMinutes(of date: Date) -> Int {
        let minutes = minutesFromMidnight(of: date)
        return minutes < dayStartHour * 60 ? minutes + 24 * 60 : minutes
    }

    /// Date for a clock time (minutes from midnight, possibly > 1440) within a sleep day.
    public func date(minutesFromMidnight minutes: Int, on day: SleepDay) -> Date {
        let dayCount = minutes / (24 * 60)
        let remainder = minutes % (24 * 60)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = remainder / 60
        components.minute = remainder % 60
        let base = calendar.date(from: components) ?? start(of: day)
        return calendar.date(byAdding: .day, value: dayCount, to: base) ?? base
    }
}
