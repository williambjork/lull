import Foundation

public enum SleepType: String, Codable, CaseIterable, Sendable {
    case nap
    case night
}

public enum SleepLocation: String, Codable, CaseIterable, Sendable {
    case crib, bassinet, stroller, car, contact, other
}

public enum SleepMethod: String, Codable, CaseIterable, Sendable {
    case independent, feeding, rocking, contact, other
}

public enum SleepCue: String, Codable, CaseIterable, Sendable {
    case yawning
    case eyeRubbing = "eye_rubbing"
    case staring
    case lessActive = "less_active"
    case fussy
    case clingy
    case feedingCue = "feeding_cue"
    case other
}

/// Context tags exist to *explain* anomalies and to filter history.
/// They never silently modify a wake-window calculation.
public enum SleepContext: String, Codable, CaseIterable, Sendable {
    case illness
    case teething
    case travel
    case unusualDay = "unusual_day"
    case developmentalChange = "developmental_change"
    case scheduleChange = "schedule_change"
}

/// Whether the nap/night label was decided by the classifier or by the parent.
/// Stored so that re-running a newer classifier never overwrites a human answer.
public enum ClassificationSource: String, Codable, Sendable {
    case automatic
    case manual
}

/// A single observed sleep. `SleepEvent`s are the source of truth for the whole
/// app: every summary, average and prediction can be regenerated from them.
public struct SleepEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var babyId: UUID

    /// Actual sleep onset, as observed by the parent.
    public var startedAt: Date
    /// Actual wake time. `nil` means the timer is still running.
    public var endedAt: Date?

    /// Optional, secondary: when the baby was put down. Enables sleep latency
    /// later on. Never used as the sleep start.
    public var putDownAt: Date?

    public var type: SleepType
    public var classificationSource: ClassificationSource
    /// Human-readable trace of why the classifier chose this type.
    public var classificationReason: String?

    /// 1-based index within its sleep day. `nil` for night sleep.
    public var napIndex: Int?

    /// Minutes awake between the previous completed sleep and this one.
    public var wakeWindowBeforeMinutes: Int?

    public var sleepLocation: SleepLocation?
    public var sleepMethod: SleepMethod?
    public var notes: String?
    public var sleepCuesObserved: [SleepCue]
    public var contexts: [SleepContext]

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        babyId: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        putDownAt: Date? = nil,
        type: SleepType = .nap,
        classificationSource: ClassificationSource = .automatic,
        classificationReason: String? = nil,
        napIndex: Int? = nil,
        wakeWindowBeforeMinutes: Int? = nil,
        sleepLocation: SleepLocation? = nil,
        sleepMethod: SleepMethod? = nil,
        notes: String? = nil,
        sleepCuesObserved: [SleepCue] = [],
        contexts: [SleepContext] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.babyId = babyId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.putDownAt = putDownAt
        self.type = type
        self.classificationSource = classificationSource
        self.classificationReason = classificationReason
        self.napIndex = napIndex
        self.wakeWindowBeforeMinutes = wakeWindowBeforeMinutes
        self.sleepLocation = sleepLocation
        self.sleepMethod = sleepMethod
        self.notes = notes
        self.sleepCuesObserved = sleepCuesObserved
        self.contexts = contexts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Always derived, never stored and never editable by the parent.
    public var durationMinutes: Int? {
        guard let endedAt else { return nil }
        return Self.minutes(from: startedAt, to: endedAt)
    }

    /// Secondary metric: how long it took to fall asleep after being put down.
    public var sleepLatencyMinutes: Int? {
        guard let putDownAt, putDownAt <= startedAt else { return nil }
        return Self.minutes(from: putDownAt, to: startedAt)
    }

    public var isActive: Bool { endedAt == nil }
    public var isCompleted: Bool { endedAt != nil }

    /// Elapsed minutes for a running timer.
    public func elapsedMinutes(asOf now: Date) -> Int {
        Self.minutes(from: startedAt, to: max(now, startedAt))
    }

    public var interval: DateInterval? {
        guard let endedAt, endedAt >= startedAt else { return nil }
        return DateInterval(start: startedAt, end: endedAt)
    }

    static func minutes(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 60).rounded())
    }
}

public extension Array where Element == SleepEvent {
    /// Completed sleeps only, oldest first. Active timers are excluded from all
    /// historical maths until the parent stops them.
    var completedChronologically: [SleepEvent] {
        filter(\.isCompleted).sorted { $0.startedAt < $1.startedAt }
    }

    var activeEvent: SleepEvent? {
        filter(\.isActive).max { $0.startedAt < $1.startedAt }
    }

    var lastCompleted: SleepEvent? {
        completedChronologically.max { lhs, rhs in
            (lhs.endedAt ?? lhs.startedAt) < (rhs.endedAt ?? rhs.startedAt)
        }
    }
}
