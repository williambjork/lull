import Foundation

public enum PredictionConfidence: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
}

public enum PredictionDataSource: String, Codable, Sendable {
    case agePrior = "age_prior"
    case personalHistory = "personal_history"
    case combined
}

/// A guess about the next sleep. Always a range, never a single authoritative
/// minute, and never stored as if it were an observation.
public struct SleepPrediction: Codable, Equatable, Sendable {
    public var predictedStartAt: Date
    public var earliestStartAt: Date
    public var latestStartAt: Date

    public var targetWakeWindowMinutes: Int
    public var confidence: PredictionConfidence
    public var dataSource: PredictionDataSource
    public var sampleSize: Int

    /// Which sleep we think is coming next, for copy like "Nap 3".
    public var expectedType: SleepType
    public var expectedNapIndex: Int?

    /// The wake period this prediction counts from.
    public var basedOnWakeStartAt: Date
    /// The completed sleep whose wake time anchored the prediction, if any.
    public var basedOnSleepEventId: UUID?

    /// Age-prior range for the "typical for this age" context line.
    public var agePriorRange: WakeWindowRange
    /// The baby's own median for this transition, when there is enough history.
    public var personalMedianMinutes: Int?

    public init(
        predictedStartAt: Date,
        earliestStartAt: Date,
        latestStartAt: Date,
        targetWakeWindowMinutes: Int,
        confidence: PredictionConfidence,
        dataSource: PredictionDataSource,
        sampleSize: Int,
        expectedType: SleepType,
        expectedNapIndex: Int?,
        basedOnWakeStartAt: Date,
        basedOnSleepEventId: UUID?,
        agePriorRange: WakeWindowRange,
        personalMedianMinutes: Int?
    ) {
        self.predictedStartAt = predictedStartAt
        self.earliestStartAt = earliestStartAt
        self.latestStartAt = latestStartAt
        self.targetWakeWindowMinutes = targetWakeWindowMinutes
        self.confidence = confidence
        self.dataSource = dataSource
        self.sampleSize = sampleSize
        self.expectedType = expectedType
        self.expectedNapIndex = expectedNapIndex
        self.basedOnWakeStartAt = basedOnWakeStartAt
        self.basedOnSleepEventId = basedOnSleepEventId
        self.agePriorRange = agePriorRange
        self.personalMedianMinutes = personalMedianMinutes
    }

    public func hasPassed(asOf now: Date) -> Bool {
        now > latestStartAt
    }

    public func isInWindow(asOf now: Date) -> Bool {
        now >= earliestStartAt && now <= latestStartAt
    }
}

/// An audit record of a prediction that was actually shown to a parent.
/// Kept apart from `SleepEvent` so the engine can change without rewriting
/// history, and so past predictions can be scored against what happened.
public struct SleepPredictionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var babyId: UUID
    public var generatedAt: Date
    public var basedOnSleepEventId: UUID?
    public var predictionVersion: String

    public var predictedStartAt: Date
    public var earliestStartAt: Date
    public var latestStartAt: Date
    public var targetWakeWindowMinutes: Int
    public var confidence: PredictionConfidence
    public var dataSource: PredictionDataSource
    public var sampleSize: Int

    public init(
        id: UUID = UUID(),
        babyId: UUID,
        generatedAt: Date,
        predictionVersion: String,
        prediction: SleepPrediction
    ) {
        self.id = id
        self.babyId = babyId
        self.generatedAt = generatedAt
        self.basedOnSleepEventId = prediction.basedOnSleepEventId
        self.predictionVersion = predictionVersion
        self.predictedStartAt = prediction.predictedStartAt
        self.earliestStartAt = prediction.earliestStartAt
        self.latestStartAt = prediction.latestStartAt
        self.targetWakeWindowMinutes = prediction.targetWakeWindowMinutes
        self.confidence = prediction.confidence
        self.dataSource = prediction.dataSource
        self.sampleSize = prediction.sampleSize
    }
}
