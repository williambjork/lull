import Foundation

/// An age expressed in the units the product actually needs.
/// `monthsExact` is fractional so priors can be interpolated instead of
/// snapping between age bands.
public struct BabyAge: Equatable, Sendable {
    public let referenceDate: Date
    public let days: Int
    public let weeks: Int
    public let months: Int
    public let monthsExact: Double

    public init(referenceDate: Date, days: Int, weeks: Int, months: Int, monthsExact: Double) {
        self.referenceDate = referenceDate
        self.days = days
        self.weeks = weeks
        self.months = months
        self.monthsExact = monthsExact
    }

    public static let zero = BabyAge(referenceDate: .distantPast, days: 0, weeks: 0, months: 0, monthsExact: 0)
}

/// Both ages, plus which one the engine should use.
public struct BabyAges: Equatable, Sendable {
    public let chronological: BabyAge
    /// Nil unless the baby was premature with a known gestational age.
    public let corrected: BabyAge?
    /// Corrected when the profile asks for it and it is available.
    public let effective: BabyAge
    public let usesCorrectedAge: Bool
}

/// Derives age on demand. Age is never persisted: a stored `ageMonths` is wrong
/// the day after it is written.
public enum AgeCalculator {

    public static func ages(for profile: BabyProfile, at now: Date = Date()) -> BabyAges {
        let calendar = calendar(for: profile)
        let chronological = age(from: profile.dateOfBirth, to: now, calendar: calendar)
        let corrected = correctedAge(for: profile, at: now)
        let usesCorrected = profile.usesCorrectedAge && corrected != nil
        return BabyAges(
            chronological: chronological,
            corrected: corrected,
            effective: usesCorrected ? (corrected ?? chronological) : chronological,
            usesCorrectedAge: usesCorrected
        )
    }

    public static func effectiveAgeMonths(for profile: BabyProfile, at now: Date = Date()) -> Double {
        ages(for: profile, at: now).effective.monthsExact
    }

    /// Corrected (adjusted) age counts from the due date rather than the birth
    /// date: 40 weeks gestation minus the actual gestational age at birth.
    public static func correctedAge(for profile: BabyProfile, at now: Date = Date()) -> BabyAge? {
        guard profile.canUseCorrectedAge, let gestationalAgeWeeks = profile.gestationalAgeWeeks else {
            return nil
        }
        let calendar = calendar(for: profile)
        let weeksEarly = max(0, 40 - gestationalAgeWeeks)
        guard let dueDate = calendar.date(byAdding: .day, value: weeksEarly * 7, to: profile.dateOfBirth) else {
            return nil
        }
        // Before the due date the corrected age is simply zero rather than negative.
        guard now > dueDate else {
            return BabyAge(referenceDate: dueDate, days: 0, weeks: 0, months: 0, monthsExact: 0)
        }
        return age(from: dueDate, to: now, calendar: calendar)
    }

    /// Whole days/weeks are counted on day boundaries in the baby's timezone,
    /// which is how parents count them. Months are fractional for interpolation.
    public static func age(from start: Date, to now: Date, calendar: Calendar) -> BabyAge {
        guard now > start else {
            return BabyAge(referenceDate: start, days: 0, weeks: 0, months: 0, monthsExact: 0)
        }

        let startDay = calendar.startOfDay(for: start)
        let nowDay = calendar.startOfDay(for: now)
        let days = max(0, calendar.dateComponents([.day], from: startDay, to: nowDay).day ?? 0)

        let wholeMonths = max(0, calendar.dateComponents([.month], from: start, to: now).month ?? 0)
        let monthsExact = exactMonths(from: start, to: now, wholeMonths: wholeMonths, calendar: calendar)

        return BabyAge(
            referenceDate: start,
            days: days,
            weeks: days / 7,
            months: wholeMonths,
            monthsExact: monthsExact
        )
    }

    /// Fraction of the way through the current calendar month-step, so 4.5
    /// months means "halfway between the 4- and 5-month anniversaries" rather
    /// than an approximation based on a 30.44-day month.
    private static func exactMonths(
        from start: Date,
        to now: Date,
        wholeMonths: Int,
        calendar: Calendar
    ) -> Double {
        guard
            let thisAnniversary = calendar.date(byAdding: .month, value: wholeMonths, to: start),
            let nextAnniversary = calendar.date(byAdding: .month, value: wholeMonths + 1, to: start)
        else {
            return Double(wholeMonths)
        }
        let span = nextAnniversary.timeIntervalSince(thisAnniversary)
        guard span > 0 else { return Double(wholeMonths) }
        let progress = now.timeIntervalSince(thisAnniversary) / span
        return Double(wholeMonths) + progress.clamped(to: 0...1)
    }

    public static func calendar(for profile: BabyProfile) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = profile.timezone
        return calendar
    }
}
