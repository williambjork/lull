import Foundation

public enum SleepServiceError: LocalizedError, Equatable {
    case activeSleepAlreadyRunning
    case noActiveSleep
    case endBeforeStart
    case startInFuture
    case eventNotFound
    case overlapsExistingSleep

    public var errorDescription: String? {
        switch self {
        case .activeSleepAlreadyRunning: "A sleep is already being tracked."
        case .noActiveSleep: "No sleep is being tracked right now."
        case .endBeforeStart: "A wake time can't be before the sleep started."
        case .startInFuture: "A sleep can't start in the future."
        case .eventNotFound: "That sleep couldn't be found."
        case .overlapsExistingSleep: "That overlaps a sleep you've already saved."
        }
    }
}

/// Today's totals, shown separately so a parent can see night and naps on their
/// own terms rather than as a single number.
public struct SleepTotals: Sendable, Equatable {
    public let day: SleepDay
    public let daytimeSleepMinutes: Int
    public let nightSleepMinutes: Int
    public let totalSleep24hMinutes: Int
    public let recommendedRange: TotalSleepRange

    public var todayTotalMinutes: Int { daytimeSleepMinutes + nightSleepMinutes }
}

public struct SleepStopResult: Sendable, Equatable {
    public let event: SleepEvent
    public let prediction: SleepPrediction?
}

/// The app-facing facade over the domain.
///
/// Holds the raw dataset, keeps derived fields consistent after every change,
/// and exposes analytics and predictions. Not thread-safe by design: drive it
/// from the main actor.
public final class SleepService {

    public private(set) var dataset: BabyDataset
    public var predictionConfig: PredictionConfig

    private let repository: any SleepRepository
    private let classifier: any SleepClassifying
    private let makeEngine: @Sendable (SleepDayCalendar) -> any SleepPredicting
    private let derivationConfig: SleepDerivationConfig
    private let trendConfiguration: SleepTrendDetector.Configuration

    public init(
        dataset: BabyDataset,
        repository: any SleepRepository,
        classifier: any SleepClassifying = HeuristicSleepClassifier(),
        predictionConfig: PredictionConfig = .default,
        derivationConfig: SleepDerivationConfig = .default,
        trendConfiguration: SleepTrendDetector.Configuration = .default,
        engineBuilder: @escaping @Sendable (SleepDayCalendar) -> any SleepPredicting = { calendar in
            HeuristicSleepPredictionEngine(calendar: calendar)
        }
    ) {
        self.dataset = dataset
        self.repository = repository
        self.classifier = classifier
        self.predictionConfig = predictionConfig
        self.derivationConfig = derivationConfig
        self.trendConfiguration = trendConfiguration
        self.makeEngine = engineBuilder
    }

    /// Returns nil when no baby has been set up yet.
    public static func loadExisting(
        repository: any SleepRepository,
        classifier: any SleepClassifying = HeuristicSleepClassifier()
    ) throws -> SleepService? {
        guard let dataset = try repository.load() else { return nil }
        return SleepService(dataset: dataset, repository: repository, classifier: classifier)
    }

    public static func create(
        profile: BabyProfile,
        repository: any SleepRepository,
        classifier: any SleepClassifying = HeuristicSleepClassifier()
    ) throws -> SleepService {
        let dataset = BabyDataset(profile: profile)
        let service = SleepService(dataset: dataset, repository: repository, classifier: classifier)
        try service.persist()
        return service
    }

    // MARK: - Context

    public var profile: BabyProfile { dataset.profile }
    public var events: [SleepEvent] { dataset.events }

    public var calendar: SleepDayCalendar {
        SleepDayCalendar(profile: dataset.profile, dayStartHour: dataset.settings.dayStartHour)
    }

    public var analytics: SleepAnalytics {
        SleepAnalytics(calendar: calendar, derivationConfig: derivationConfig)
    }

    public var predictionEngine: any SleepPredicting { makeEngine(calendar) }

    public func ages(asOf now: Date = Date()) -> BabyAges {
        AgeCalculator.ages(for: dataset.profile, at: now)
    }

    public func ageMonths(asOf now: Date = Date()) -> Double {
        ages(asOf: now).effective.monthsExact
    }

    // MARK: - Timer

    public var activeSleep: SleepEvent? { dataset.events.activeEvent }

    /// The parent starts the timer when the baby actually falls asleep — not
    /// when they were put down. `putDownAt` is optional context only.
    @discardableResult
    public func startSleep(
        at startedAt: Date = Date(),
        now: Date = Date(),
        putDownAt: Date? = nil,
        location: SleepLocation? = nil,
        method: SleepMethod? = nil,
        cues: [SleepCue] = [],
        contexts: [SleepContext] = [],
        notes: String? = nil
    ) throws -> SleepEvent {
        guard activeSleep == nil else { throw SleepServiceError.activeSleepAlreadyRunning }
        guard startedAt <= now.addingTimeInterval(60) else { throw SleepServiceError.startInFuture }
        if let last = dataset.events.lastCompleted, let endedAt = last.endedAt, startedAt < endedAt {
            throw SleepServiceError.overlapsExistingSleep
        }

        var event = SleepEvent(
            babyId: dataset.profile.id,
            startedAt: startedAt,
            putDownAt: putDownAt,
            sleepLocation: location,
            sleepMethod: method,
            notes: notes,
            sleepCuesObserved: cues,
            contexts: contexts,
            createdAt: now,
            updatedAt: now
        )
        // Provisional label while the timer runs; settled when it stops.
        let classification = classify(startedAt: startedAt, endedAt: nil, excluding: event.id, asOf: now)
        event.type = classification.type
        event.classificationReason = classification.reason

        dataset.events.append(event)
        try recomputeAndPersist()
        return dataset.events.first { $0.id == event.id } ?? event
    }

    @discardableResult
    public func stopSleep(at endedAt: Date = Date(), now: Date = Date()) throws -> SleepStopResult {
        guard let active = activeSleep else { throw SleepServiceError.noActiveSleep }
        guard endedAt >= active.startedAt else { throw SleepServiceError.endBeforeStart }

        guard let index = dataset.events.firstIndex(where: { $0.id == active.id }) else {
            throw SleepServiceError.eventNotFound
        }
        dataset.events[index].endedAt = endedAt
        dataset.events[index].updatedAt = now

        // Now that the duration is known, settle the nap/night label — unless
        // the parent already decided it themselves.
        if dataset.events[index].classificationSource == .automatic {
            let classification = classify(
                startedAt: active.startedAt,
                endedAt: endedAt,
                excluding: active.id,
                asOf: now
            )
            dataset.events[index].type = classification.type
            dataset.events[index].classificationReason = classification.reason
        }

        try recomputeAndPersist()
        let stored = dataset.events.first { $0.id == active.id } ?? dataset.events[index]
        return SleepStopResult(event: stored, prediction: prediction(asOf: max(now, endedAt)))
    }

    /// For "I forgot to start the timer": the start moves, the duration follows.
    /// The duration itself is never editable.
    public func adjustActiveStart(to startedAt: Date, now: Date = Date()) throws {
        guard let active = activeSleep else { throw SleepServiceError.noActiveSleep }
        guard startedAt <= now.addingTimeInterval(60) else { throw SleepServiceError.startInFuture }
        guard let index = dataset.events.firstIndex(where: { $0.id == active.id }) else {
            throw SleepServiceError.eventNotFound
        }
        dataset.events[index].startedAt = startedAt
        dataset.events[index].updatedAt = now
        try recomputeAndPersist()
    }

    /// Discard a timer started by mistake.
    public func cancelActiveSleep() throws {
        guard let active = activeSleep else { throw SleepServiceError.noActiveSleep }
        dataset.events.removeAll { $0.id == active.id }
        try recomputeAndPersist()
    }

    // MARK: - Editing history

    @discardableResult
    public func addCompletedSleep(
        startedAt: Date,
        endedAt: Date,
        now: Date = Date(),
        type: SleepType? = nil,
        location: SleepLocation? = nil,
        method: SleepMethod? = nil,
        cues: [SleepCue] = [],
        contexts: [SleepContext] = [],
        notes: String? = nil
    ) throws -> SleepEvent {
        guard endedAt >= startedAt else { throw SleepServiceError.endBeforeStart }
        guard startedAt <= now.addingTimeInterval(60) else { throw SleepServiceError.startInFuture }

        var event = SleepEvent(
            babyId: dataset.profile.id,
            startedAt: startedAt,
            endedAt: endedAt,
            sleepLocation: location,
            sleepMethod: method,
            notes: notes,
            sleepCuesObserved: cues,
            contexts: contexts,
            createdAt: now,
            updatedAt: now
        )
        if let type {
            event.type = type
            event.classificationSource = .manual
            event.classificationReason = "Set by parent"
        } else {
            let classification = classify(startedAt: startedAt, endedAt: endedAt, excluding: event.id, asOf: now)
            event.type = classification.type
            event.classificationReason = classification.reason
        }

        dataset.events.append(event)
        try recomputeAndPersist()
        return dataset.events.first { $0.id == event.id } ?? event
    }

    /// Times, context and notes are editable; duration is not.
    public func updateSleep(
        id: UUID,
        startedAt: Date? = nil,
        endedAt: Date?? = nil,
        location: SleepLocation?? = nil,
        method: SleepMethod?? = nil,
        cues: [SleepCue]? = nil,
        contexts: [SleepContext]? = nil,
        notes: String?? = nil,
        now: Date = Date()
    ) throws {
        guard let index = dataset.events.firstIndex(where: { $0.id == id }) else {
            throw SleepServiceError.eventNotFound
        }
        var event = dataset.events[index]
        if let startedAt {
            guard startedAt <= now.addingTimeInterval(60) else { throw SleepServiceError.startInFuture }
            event.startedAt = startedAt
        }
        if let endedAt {
            if let endedAt, endedAt < event.startedAt { throw SleepServiceError.endBeforeStart }
            event.endedAt = endedAt
        }
        if let location { event.sleepLocation = location }
        if let method { event.sleepMethod = method }
        if let cues { event.sleepCuesObserved = cues }
        if let contexts { event.contexts = contexts }
        if let notes { event.notes = notes }
        event.updatedAt = now

        dataset.events[index] = event
        try recomputeAndPersist()
    }

    /// A parent override wins permanently: automatic re-classification will not
    /// overwrite it.
    public func setType(_ type: SleepType, forEventId id: UUID, now: Date = Date()) throws {
        guard let index = dataset.events.firstIndex(where: { $0.id == id }) else {
            throw SleepServiceError.eventNotFound
        }
        dataset.events[index].type = type
        dataset.events[index].classificationSource = .manual
        dataset.events[index].classificationReason = "Set by parent"
        dataset.events[index].updatedAt = now
        try recomputeAndPersist()
    }

    public func deleteSleep(id: UUID) throws {
        guard dataset.events.contains(where: { $0.id == id }) else {
            throw SleepServiceError.eventNotFound
        }
        dataset.events.removeAll { $0.id == id }
        try recomputeAndPersist()
    }

    // MARK: - Days

    public func isDayUnusual(_ day: SleepDay) -> Bool {
        analytics.unusualDays(events: dataset.events, dayFlags: dataset.dayFlags).contains(day)
    }

    public func dayFlag(for day: SleepDay) -> DayFlag? {
        dataset.dayFlags.first { $0.day == day }
    }

    /// Marking a day unusual filters it out of personal history. It never
    /// adjusts a wake-window calculation.
    public func markDay(_ day: SleepDay, contexts: [SleepContext] = [.unusualDay], note: String? = nil) throws {
        dataset.dayFlags.removeAll { $0.day == day }
        if !contexts.isEmpty {
            dataset.dayFlags.append(DayFlag(babyId: dataset.profile.id, day: day, contexts: contexts, note: note))
        }
        try persist()
    }

    public func clearDayFlag(_ day: SleepDay) throws {
        dataset.dayFlags.removeAll { $0.day == day }
        try persist()
    }

    /// Lets a parent say "she woke at 06:40" on a day with nothing tracked yet,
    /// so the first nap can still be predicted.
    public func setDayStartWake(_ wokeAt: Date, for day: SleepDay? = nil, now: Date = Date()) throws {
        let targetDay = day ?? calendar.day(for: now)
        dataset.settings.setDayStartWake(wokeAt, for: targetDay)
        try persist()
    }

    public func dayStartWake(for day: SleepDay? = nil, now: Date = Date()) -> Date? {
        dataset.settings.dayStartWake(for: day ?? calendar.day(for: now))
    }

    public func setDayStartHour(_ hour: Int) throws {
        dataset.settings.dayStartHour = hour.clamped(to: 0...12)
        try recomputeAndPersist()
    }

    // MARK: - Profile

    public func updateProfile(_ transform: (inout BabyProfile) -> Void, now: Date = Date()) throws {
        var profile = dataset.profile
        transform(&profile)
        profile.updatedAt = now
        dataset.profile = profile
        try recomputeAndPersist()
    }

    // MARK: - Derived reads

    public func sleepProfile(asOf now: Date = Date()) -> BabySleepProfile {
        SleepProfileBuilder(analytics: analytics).build(
            babyId: dataset.profile.id,
            events: dataset.events,
            dayFlags: dataset.dayFlags,
            asOf: now,
            wakeWindowFilter: SleepHistoryFilter(
                lookbackDays: predictionConfig.lookbackDays,
                excludedContexts: predictionConfig.excludedContexts
            )
        )
    }

    public func prediction(asOf now: Date = Date()) -> SleepPrediction? {
        predictionEngine.predictNextSleep(
            PredictionInput(
                now: now,
                ageMonths: ageMonths(asOf: now),
                events: dataset.events,
                dayFlags: dataset.dayFlags,
                sleepProfile: sleepProfile(asOf: now),
                dayStartWake: dayStartWake(now: now),
                config: predictionConfig
            )
        )
    }

    /// Records what was actually shown to the parent, for later scoring of the
    /// engine. Predictions are never mixed in with observations.
    public func recordShownPrediction(_ prediction: SleepPrediction, now: Date = Date()) throws {
        let record = SleepPredictionRecord(
            babyId: dataset.profile.id,
            generatedAt: now,
            predictionVersion: predictionEngine.version,
            prediction: prediction
        )
        // One record per wake period is enough; replace as the estimate refines.
        dataset.predictions.removeAll {
            $0.basedOnSleepEventId == record.basedOnSleepEventId && $0.predictionVersion == record.predictionVersion
        }
        dataset.predictions.append(record)
        dataset.predictions = dataset.predictions.suffix(500)
        try persist()
    }

    public func totals(asOf now: Date = Date()) -> SleepTotals {
        let analytics = analytics
        let day = analytics.calendar.day(for: now)
        let summary = analytics.summary(for: day, events: dataset.events, dayFlags: dataset.dayFlags)
        return SleepTotals(
            day: day,
            daytimeSleepMinutes: summary.daytimeSleepMinutes,
            nightSleepMinutes: summary.nightSleepMinutes,
            totalSleep24hMinutes: analytics.totalSleep24hMinutes(asOf: now, events: dataset.events),
            recommendedRange: TotalSleepPriors.range(forAgeMonths: ageMonths(asOf: now))
        )
    }

    public func recentSummaries(days: Int = 14, asOf now: Date = Date()) -> [DailySleepSummary] {
        analytics.recentSummaries(days: days, asOf: now, events: dataset.events, dayFlags: dataset.dayFlags)
    }

    public func allSummaries() -> [DailySleepSummary] {
        analytics.allSummaries(events: dataset.events, dayFlags: dataset.dayFlags)
    }

    public func events(on day: SleepDay) -> [SleepEvent] {
        let analytics = analytics
        return dataset.events
            .filter { analytics.attributedDay(for: $0) == day || analytics.calendar.day(for: $0.startedAt) == day }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func trends(asOf now: Date = Date()) -> [SleepTrendSignal] {
        SleepTrendDetector(analytics: analytics, configuration: trendConfiguration)
            .detect(events: dataset.events, dayFlags: dataset.dayFlags, asOf: now)
    }

    public func cueStats() -> [SleepCueStat] {
        CueAnalytics(analytics: analytics).stats(events: dataset.events)
    }

    public func awakeMinutes(asOf now: Date = Date()) -> Int? {
        analytics.awakeMinutes(asOf: now, events: dataset.events)
    }

    public func deleteAllData() throws {
        try repository.deleteAll()
    }

    // MARK: - Internals

    private func classify(
        startedAt: Date,
        endedAt: Date?,
        excluding eventId: UUID,
        asOf now: Date
    ) -> SleepClassificationResult {
        let calendar = calendar
        let day = calendar.day(for: startedAt)
        let sameDay = dataset.events.filter {
            $0.id != eventId && $0.isCompleted && calendar.day(for: $0.startedAt) == day
        }
        return classifier.classify(
            SleepClassificationInput(
                startedAt: startedAt,
                endedAt: endedAt,
                ageMonths: ageMonths(asOf: now),
                sameDayEvents: sameDay,
                sleepProfile: sleepProfile(asOf: now),
                calendar: calendar
            )
        )
    }

    /// Structural derived fields are rebuilt from scratch after every change,
    /// because inserting or editing one sleep renumbers the naps around it.
    private func recomputeAndPersist() throws {
        dataset.events = SleepDerivation.recomputeDerivedFields(
            events: dataset.events,
            calendar: calendar,
            config: derivationConfig
        )
        try persist()
    }

    private func persist() throws {
        try repository.save(dataset)
    }
}
