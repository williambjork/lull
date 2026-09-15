import Foundation

/// The baby's identity and the few facts that never go stale.
///
/// Deliberately does *not* store an age. Age is derived on demand from
/// `dateOfBirth` (see `AgeCalculator`) so it can never drift out of date.
public struct BabyProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var dateOfBirth: Date

    /// Only relevant for premature babies.
    public var wasPremature: Bool
    /// Gestational age at birth in weeks (typically 22...37).
    public var gestationalAgeWeeks: Int?

    /// When true, and a gestational age is known, the prediction engine uses
    /// corrected (adjusted) age instead of chronological age.
    public var correctedAgeEnabled: Bool

    /// IANA identifier, e.g. "Europe/Stockholm". Sleep days and clock-time
    /// heuristics are always evaluated in the baby's own timezone.
    public var timezoneIdentifier: String

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "",
        dateOfBirth: Date,
        wasPremature: Bool = false,
        gestationalAgeWeeks: Int? = nil,
        correctedAgeEnabled: Bool = false,
        timezoneIdentifier: String = TimeZone.current.identifier,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.wasPremature = wasPremature
        self.gestationalAgeWeeks = gestationalAgeWeeks
        self.correctedAgeEnabled = correctedAgeEnabled
        self.timezoneIdentifier = timezoneIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var timezone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? .current
    }

    /// Corrected age is only meaningful when we know how early the baby arrived.
    public var canUseCorrectedAge: Bool {
        wasPremature && (gestationalAgeWeeks ?? 40) < 40
    }

    public var usesCorrectedAge: Bool {
        correctedAgeEnabled && canUseCorrectedAge
    }
}
