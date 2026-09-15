import Foundation

public enum DurationFormatting {

    /// "13h 42m", "1h 12m", "58m"
    public static func compact(_ minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let remainder = total % 60
        if hours == 0 { return "\(remainder)m" }
        return "\(hours)h \(String(format: "%02d", remainder))m"
    }

    /// Live running timer: "4:32", "0:05", "1:05:22".
    public static func timer(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "~2h 20m" — the tilde is doing real work: these are estimates.
    public static func approximate(_ minutes: Int) -> String {
        "~" + compact(minutes)
    }

    /// "~2–4 hours" for broad age guidance.
    public static func approximateHourRange(minMinutes: Int, maxMinutes: Int) -> String {
        "~\(hours(minMinutes))–\(hours(maxMinutes)) hours"
    }

    private static func hours(_ minutes: Int) -> String {
        let value = Double(minutes) / 60
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}

public enum TimeFormatting {

    public static func clock(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        formatter(timeZone: timeZone, locale: locale).string(from: date)
    }

    /// "12:45–1:15 PM" — one range, one AM/PM marker where the locale uses them.
    public static func clockRange(
        from earliest: Date,
        to latest: Date,
        timeZone: TimeZone,
        locale: Locale = .current
    ) -> String {
        let formatter = formatter(timeZone: timeZone, locale: locale)
        var start = formatter.string(from: earliest)
        let end = formatter.string(from: latest)

        for symbol in [formatter.amSymbol, formatter.pmSymbol].compactMap({ $0 }) {
            if start.hasSuffix(symbol), end.hasSuffix(symbol) {
                start = String(start.dropLast(symbol.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return "\(start)–\(end)"
    }

    private static func formatter(timeZone: TimeZone, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

/// Copy lives here so the "this is a guide, not a prescription" tone is applied
/// consistently and can be reviewed in one place.
public enum SleepCopy {

    public static let predictionHeadline = "Likely ready for sleep"
    public static let awakeLabel = "AWAKE"
    public static let sleepingLabel = "SLEEPING"

    public static let disclaimer = """
        Nana learns your baby's pattern to suggest a likely window. Every baby is \
        different, and these suggestions aren't medical advice.
        """

    /// "Based on …" line under the predicted range.
    public static func basedOn(_ dataSource: PredictionDataSource) -> String {
        switch dataSource {
        case .personalHistory: "your baby's recent pattern"
        case .combined: "your baby's recent pattern and typical ranges for this age"
        case .agePrior: "typical ranges for this age"
        }
    }

    public static func nextSleepTitle(_ prediction: SleepPrediction) -> String {
        switch prediction.expectedType {
        case .night: return "Bedtime"
        case .nap:
            if let index = prediction.expectedNapIndex { return "Nap \(index)" }
            return "Next nap"
        }
    }

    public static func eventTitle(_ event: SleepEvent) -> String {
        switch event.type {
        case .night: return "Night sleep"
        case .nap:
            if let index = event.napIndex { return "Nap \(index)" }
            return "Nap"
        }
    }

    /// "Typical for this age: ~2–4 hours awake"
    public static func typicalForAge(_ range: WakeWindowRange) -> String {
        "Typical for this age: "
            + DurationFormatting.approximateHourRange(minMinutes: range.minMinutes, maxMinutes: range.maxMinutes)
            + " awake"
    }

    /// "Your baby usually: ~2h 20m"
    public static func thisBabyUsually(_ minutes: Int) -> String {
        "Your baby usually: " + DurationFormatting.approximate(minutes)
    }

    public static func confidenceLabel(_ confidence: PredictionConfidence, sampleSize: Int) -> String {
        switch confidence {
        case .low:
            return sampleSize == 0
                ? "Rough estimate — still learning your baby"
                : "Rough estimate — only \(sampleSize) similar days so far"
        case .medium:
            return "Getting to know your baby's pattern (\(sampleSize) similar days)"
        case .high:
            return "Based on a steady pattern (\(sampleSize) similar days)"
        }
    }

    public static func cueLabel(_ cue: SleepCue) -> String {
        switch cue {
        case .yawning: "Yawning"
        case .eyeRubbing: "Eye rubbing"
        case .staring: "Staring"
        case .lessActive: "Less active"
        case .fussy: "Fussy"
        case .clingy: "Clingy"
        case .feedingCue: "Feeding cue"
        case .other: "Other"
        }
    }

    public static func contextLabel(_ context: SleepContext) -> String {
        switch context {
        case .illness: "Illness"
        case .teething: "Teething"
        case .travel: "Travel"
        case .unusualDay: "Unusual day"
        case .developmentalChange: "Developmental change"
        case .scheduleChange: "Schedule change"
        }
    }

    public static func locationLabel(_ location: SleepLocation) -> String {
        switch location {
        case .crib: "Crib"
        case .bassinet: "Bassinet"
        case .stroller: "Stroller"
        case .car: "Car"
        case .contact: "Contact"
        case .other: "Other"
        }
    }

    public static func methodLabel(_ method: SleepMethod) -> String {
        switch method {
        case .independent: "Independently"
        case .feeding: "Feeding"
        case .rocking: "Rocking"
        case .contact: "Contact"
        case .other: "Other"
        }
    }

    public static func ageDescription(_ age: BabyAge) -> String {
        if age.days < 14 { return "\(age.days) day\(age.days == 1 ? "" : "s") old" }
        if age.days < 90 { return "\(age.weeks) week\(age.weeks == 1 ? "" : "s") old" }
        return "\(age.months) month\(age.months == 1 ? "" : "s") old"
    }
}
