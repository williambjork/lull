import Foundation

/// Parent-visible settings that affect derivation.
public struct SleepSettings: Codable, Equatable, Sendable {
    /// Boundary between sleep days, in local hours. 05:00 by default.
    public var dayStartHour: Int
    /// Morning wake times the parent entered for days with nothing tracked yet.
    public var dayStartWakes: [DayStartWake]

    public init(dayStartHour: Int = 5, dayStartWakes: [DayStartWake] = []) {
        self.dayStartHour = dayStartHour
        self.dayStartWakes = dayStartWakes
    }

    public func dayStartWake(for day: SleepDay) -> Date? {
        dayStartWakes.first { $0.day == day }?.wokeAt
    }

    public mutating func setDayStartWake(_ wokeAt: Date, for day: SleepDay) {
        dayStartWakes.removeAll { $0.day == day }
        dayStartWakes.append(DayStartWake(day: day, wokeAt: wokeAt))
        // Keep this small; it is only useful for recent days.
        dayStartWakes = dayStartWakes.sorted { $0.day > $1.day }.prefix(60).map { $0 }
    }
}

public struct DayStartWake: Codable, Equatable, Sendable {
    public var day: SleepDay
    public var wokeAt: Date

    public init(day: SleepDay, wokeAt: Date) {
        self.day = day
        self.wokeAt = wokeAt
    }
}

/// Everything persisted for one baby.
///
/// `events` are the source of truth. Summaries, the derived sleep profile and
/// trends are never stored — they are recomputed on demand, so improving the
/// analytics never requires a migration. `predictions` is an append-only audit
/// log kept deliberately separate from observations.
public struct BabyDataset: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var profile: BabyProfile
    public var events: [SleepEvent]
    public var dayFlags: [DayFlag]
    public var predictions: [SleepPredictionRecord]
    public var settings: SleepSettings

    public init(
        schemaVersion: Int = BabyDataset.currentSchemaVersion,
        profile: BabyProfile,
        events: [SleepEvent] = [],
        dayFlags: [DayFlag] = [],
        predictions: [SleepPredictionRecord] = [],
        settings: SleepSettings = SleepSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.events = events
        self.dayFlags = dayFlags
        self.predictions = predictions
        self.settings = settings
    }
}

public enum LullJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
