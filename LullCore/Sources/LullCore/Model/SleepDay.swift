import Foundation

/// A "sleep day" in the baby's own timezone. It does not start at midnight:
/// a 19:30 bedtime and the 02:00 night waking that follows belong to the same
/// sleep day, so nap numbering and daily totals behave the way parents expect.
public struct SleepDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: SleepDay, rhs: SleepDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// Parent-supplied marker for a whole day ("we were travelling", "she was ill").
/// Used to filter history out of the personalised prediction, never to adjust it.
public struct DayFlag: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var babyId: UUID
    public var day: SleepDay
    public var contexts: [SleepContext]
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        babyId: UUID,
        day: SleepDay,
        contexts: [SleepContext] = [.unusualDay],
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.babyId = babyId
        self.day = day
        self.contexts = contexts
        self.note = note
        self.createdAt = createdAt
    }

    public var isUnusual: Bool { !contexts.isEmpty }
}
