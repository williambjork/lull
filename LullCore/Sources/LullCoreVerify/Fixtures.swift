import Foundation
import LullCore

/// Deterministic clock helpers. UTC keeps the local-time heuristics predictable.
let testTimeZone = TimeZone(identifier: "UTC")!

let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = testTimeZone
    return calendar
}()

func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = testTimeZone
    return testCalendar.date(from: components)!
}

func addingDays(_ days: Int, to date: Date) -> Date {
    testCalendar.date(byAdding: .day, value: days, to: date)!
}

func settingTime(_ date: Date, hour: Int, minute: Int) -> Date {
    testCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
}

func minutes(_ count: Int) -> TimeInterval { Double(count) * 60 }

func makeProfile(
    dateOfBirth: Date,
    premature: Bool = false,
    gestationalAgeWeeks: Int? = nil,
    correctedAgeEnabled: Bool = false
) -> BabyProfile {
    BabyProfile(
        name: "Test baby",
        dateOfBirth: dateOfBirth,
        wasPremature: premature,
        gestationalAgeWeeks: gestationalAgeWeeks,
        correctedAgeEnabled: correctedAgeEnabled,
        timezoneIdentifier: testTimeZone.identifier
    )
}

/// One synthetic day, described by wake windows so history can be built with
/// exact, predictable wake-window values.
struct DaySpec {
    var morningWake: (hour: Int, minute: Int) = (7, 0)
    /// Each nap: minutes awake beforehand, then how long it lasted.
    var naps: [(wakeWindow: Int, duration: Int)]
    /// Minutes awake between the last nap and bedtime.
    var bedtimeWakeWindow: Int = 180
    /// Used only for the final day, where there is no following morning wake.
    var nightMinutes: Int = 660
    /// False for a day still in progress, where bedtime has not happened yet.
    var includeNight: Bool = true
}

/// Builds a chronological history from day specs (oldest first) and fills in the
/// derived fields the app would have computed as the days happened.
func buildHistory(babyId: UUID, oldestDay: Date, specs: [DaySpec], calendar: SleepDayCalendar) -> [SleepEvent] {
    var events: [SleepEvent] = []

    for (offset, spec) in specs.enumerated() {
        let dayBase = addingDays(offset, to: oldestDay)
        var cursor = settingTime(dayBase, hour: spec.morningWake.hour, minute: spec.morningWake.minute)

        for nap in spec.naps {
            let start = cursor.addingTimeInterval(minutes(nap.wakeWindow))
            let end = start.addingTimeInterval(minutes(nap.duration))
            events.append(
                SleepEvent(
                    babyId: babyId,
                    startedAt: start,
                    endedAt: end,
                    type: .nap,
                    classificationSource: .manual
                )
            )
            cursor = end
        }

        guard spec.includeNight else { continue }

        let bedtime = cursor.addingTimeInterval(minutes(spec.bedtimeWakeWindow))
        let nightEnd: Date
        if offset + 1 < specs.count {
            let nextSpec = specs[offset + 1]
            nightEnd = settingTime(
                addingDays(offset + 1, to: oldestDay),
                hour: nextSpec.morningWake.hour,
                minute: nextSpec.morningWake.minute
            )
        } else {
            nightEnd = bedtime.addingTimeInterval(minutes(spec.nightMinutes))
        }
        events.append(
            SleepEvent(
                babyId: babyId,
                startedAt: bedtime,
                endedAt: nightEnd,
                type: .night,
                classificationSource: .manual
            )
        )
    }

    return SleepDerivation.recomputeDerivedFields(events: events, calendar: calendar)
}
