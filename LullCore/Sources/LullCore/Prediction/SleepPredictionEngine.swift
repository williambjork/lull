import Foundation

public struct PredictionInput: Sendable {
    public let now: Date
    /// Corrected age when the profile asks for it, chronological otherwise.
    public let ageMonths: Double
    public let events: [SleepEvent]
    public let dayFlags: [DayFlag]
    public let sleepProfile: BabySleepProfile
    /// Parent-supplied wake time for days where nothing has been tracked yet.
    public let dayStartWake: Date?
    public let config: PredictionConfig

    public init(
        now: Date,
        ageMonths: Double,
        events: [SleepEvent],
        dayFlags: [DayFlag],
        sleepProfile: BabySleepProfile,
        dayStartWake: Date? = nil,
        config: PredictionConfig = .default
    ) {
        self.now = now
        self.ageMonths = ageMonths
        self.events = events
        self.dayFlags = dayFlags
        self.sleepProfile = sleepProfile
        self.dayStartWake = dayStartWake
        self.config = config
    }
}

/// The whole prediction surface the app talks to. Swapping the heuristic for
/// something better later means implementing this and nothing else.
public protocol SleepPredicting: Sendable {
    var version: String { get }
    func predictNextSleep(_ input: PredictionInput) -> SleepPrediction?
}

/// Hook for later personalisation, e.g. "after a short nap this baby usually
/// has a shorter wake window". Intentionally does nothing in the MVP: such
/// relationships should be derived from a baby's own data, not hard-coded.
public struct WakeWindowAdjustmentContext: Sendable {
    public let plan: NextSleepPlan
    public let previousSleep: SleepEvent?
    public let history: MatchedWakeWindowHistory
    public let ageMonths: Double
    public let sleepProfile: BabySleepProfile
}

public protocol WakeWindowAdjusting: Sendable {
    func adjustedTargetMinutes(_ target: Int, context: WakeWindowAdjustmentContext) -> Int
}

public struct NoWakeWindowAdjustment: WakeWindowAdjusting {
    public init() {}
    public func adjustedTargetMinutes(_ target: Int, context: WakeWindowAdjustmentContext) -> Int {
        target
    }
}

/// Deterministic, explainable prediction: an age prior, the baby's own median
/// for the same transition, and a weighted blend between them that shifts
/// towards the baby as evidence accumulates.
public struct HeuristicSleepPredictionEngine: SleepPredicting {
    public let version = "heuristic-prediction-1"

    private let calendar: SleepDayCalendar
    private let matcher: WakeWindowHistoryMatcher
    private let planner: NextSleepPlanner
    private let adjustment: WakeWindowAdjusting

    public init(
        calendar: SleepDayCalendar,
        adjustment: WakeWindowAdjusting = NoWakeWindowAdjustment()
    ) {
        self.calendar = calendar
        self.matcher = WakeWindowHistoryMatcher(analytics: SleepAnalytics(calendar: calendar))
        self.planner = NextSleepPlanner(calendar: calendar)
        self.adjustment = adjustment
    }

    public func predictNextSleep(_ input: PredictionInput) -> SleepPrediction? {
        // Nothing to predict while a sleep is in progress.
        guard input.events.activeEvent == nil else { return nil }

        // Step 1 — the current wake period starts when the last sleep ended.
        let wake = wakeStart(input)
        guard let wakeStart = wake?.date else { return nil }

        // Step 2 — which sleep is next. Decided in two passes because a late
        // target time can itself turn "nap 4" into "bedtime".
        let firstPass = planner.plan(
            events: input.events,
            now: input.now,
            tentativeStart: nil,
            sleepProfile: input.sleepProfile,
            config: input.config
        )
        let tentative = evaluate(plan: firstPass, wakeStart: wakeStart, wakeEventId: wake?.eventId, input: input)
        let secondPass = planner.plan(
            events: input.events,
            now: input.now,
            tentativeStart: tentative.predictedStartAt,
            sleepProfile: input.sleepProfile,
            config: input.config
        )

        guard secondPass != firstPass else { return tentative }
        return evaluate(plan: secondPass, wakeStart: wakeStart, wakeEventId: wake?.eventId, input: input)
    }

    // MARK: - Core evaluation

    private func evaluate(
        plan: NextSleepPlan,
        wakeStart: Date,
        wakeEventId: UUID?,
        input: PredictionInput
    ) -> SleepPrediction {
        let config = input.config

        // Step 3 — the age prior, interpolated across the published bands.
        let prior = WakeWindowPriors.prior(forAgeMonths: input.ageMonths)
        let agePriorTarget = Double(prior.targetMinutes)

        // Step 4 — this baby's own history for the same transition.
        let history = matcher.match(
            plan: plan,
            events: input.events,
            dayFlags: input.dayFlags,
            asOf: input.now,
            config: config
        )
        let personalTarget = history.medianMinutes

        // Weighting: no personal weight until there is enough comparable data.
        var personalWeight = config.personalWeight(forSampleSize: history.sampleSize)
        if personalTarget == nil { personalWeight = 0 }
        // Past the published bands the prior is an educated guess, so lean further
        // on the baby's own pattern rather than on invented toddler numbers.
        if personalWeight > 0, prior.isExtrapolated {
            personalWeight += (1 - prior.reliability) * (1 - personalWeight)
        }
        personalWeight = personalWeight.clamped(to: 0...1)

        let blended = personalWeight * (personalTarget ?? agePriorTarget)
            + (1 - personalWeight) * agePriorTarget

        let previousSleep = input.events.lastCompleted
        let adjusted = adjustment.adjustedTargetMinutes(
            Int(blended.rounded()),
            context: WakeWindowAdjustmentContext(
                plan: plan,
                previousSleep: previousSleep,
                history: history,
                ageMonths: input.ageMonths,
                sleepProfile: input.sleepProfile
            )
        )
        var targetMinutes = adjusted.clamped(to: config.minTargetMinutes...config.maxTargetMinutes)
        var predictedStart = wakeStart.addingTimeInterval(Double(targetMinutes) * 60)

        // Bedtime is partly clock-anchored: a baby with a settled 19:15 bedtime
        // does not move it by an hour because one nap ran short.
        if plan.type == .night,
           let anchored = bedtimeAnchoredStart(predictedStart: predictedStart, wakeStart: wakeStart, input: input) {
            predictedStart = anchored
            targetMinutes = SleepEvent.minutes(from: wakeStart, to: predictedStart)
        }

        let padding = Double(config.rangePaddingMinutes) * 60
        return SleepPrediction(
            predictedStartAt: predictedStart,
            earliestStartAt: predictedStart.addingTimeInterval(-padding),
            latestStartAt: predictedStart.addingTimeInterval(padding),
            targetWakeWindowMinutes: targetMinutes,
            confidence: confidence(history: history, personalWeight: personalWeight, prior: prior, config: config),
            dataSource: dataSource(personalWeight: personalWeight),
            sampleSize: history.sampleSize,
            expectedType: plan.type,
            expectedNapIndex: plan.napIndex,
            basedOnWakeStartAt: wakeStart,
            basedOnSleepEventId: wakeEventId,
            agePriorRange: prior.range,
            personalMedianMinutes: personalTarget.map { Int($0.rounded()) }
        )
    }

    // MARK: - Pieces

    /// Step 1: the wake period begins at the last completed sleep's end. With
    /// nothing tracked yet we use the parent-supplied morning wake time.
    private func wakeStart(_ input: PredictionInput) -> (date: Date, eventId: UUID?)? {
        if let current = SleepDerivation.currentWakeStart(events: input.events) {
            return (current.date, current.sourceEventId)
        }
        if let dayStartWake = input.dayStartWake {
            return (dayStartWake, nil)
        }
        return nil
    }

    private func bedtimeAnchoredStart(predictedStart: Date, wakeStart: Date, input: PredictionInput) -> Date? {
        let config = input.config
        guard
            config.bedtimeAnchorWeight > 0,
            input.sleepProfile.daysWithData >= config.minBedtimeSamplesForAnchor,
            let bedtimeMinutes = input.sleepProfile.medianBedtimeMinutesFromMidnight
        else { return nil }

        let day = calendar.day(for: wakeStart)
        let habitualBedtime = calendar.date(minutesFromMidnight: bedtimeMinutes, on: day)
        let weight = config.bedtimeAnchorWeight.clamped(to: 0...1)
        let blendedInterval = predictedStart.timeIntervalSince1970 * (1 - weight)
            + habitualBedtime.timeIntervalSince1970 * weight
        let blended = Date(timeIntervalSince1970: blendedInterval)
        // Never predict a bedtime before the baby woke up.
        return max(blended, wakeStart)
    }

    private func dataSource(personalWeight: Double) -> PredictionDataSource {
        if personalWeight <= 0.001 { return .agePrior }
        if personalWeight >= 0.999 { return .personalHistory }
        return .combined
    }

    private func confidence(
        history: MatchedWakeWindowHistory,
        personalWeight: Double,
        prior: AgeWakeWindowPrior,
        config: PredictionConfig
    ) -> PredictionConfidence {
        // Age prior alone is never more than a broad guess.
        guard personalWeight > 0 else { return .low }

        var level: PredictionConfidence
        if history.sampleSize < config.strongHistorySampleCount {
            level = .medium
        } else if let dispersion = history.relativeDispersion,
                  dispersion > config.highConfidenceMaxRelativeDispersion {
            // Plenty of data, but this baby is genuinely inconsistent.
            level = .medium
        } else {
            level = .high
        }

        // Borrowed history (neighbouring or any nap) is weaker evidence.
        if history.quality != .exactTransition, level == .high {
            level = .medium
        }
        return level
    }
}
