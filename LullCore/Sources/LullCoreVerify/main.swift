import Foundation
import LullCore

let expect = Expect()
let sleepDayCalendar = SleepDayCalendar(timeZone: testTimeZone, dayStartHour: 5)
let analytics = SleepAnalytics(calendar: sleepDayCalendar)

// MARK: - Age

expect.suite("Age is derived, never stored") {
    let profile = makeProfile(dateOfBirth: makeDate(2026, 1, 1, 8, 0))
    let ages = AgeCalculator.ages(for: profile, at: makeDate(2026, 5, 16, 12, 0))

    expect.equal(ages.chronological.days, 135, "age in days")
    expect.equal(ages.chronological.weeks, 19, "age in weeks")
    expect.equal(ages.chronological.months, 4, "whole months")
    expect.check(
        ages.chronological.monthsExact > 4.4 && ages.chronological.monthsExact < 4.6,
        "fractional months land near 4.5 (got \(String(format: "%.2f", ages.chronological.monthsExact)))"
    )
    expect.check(ages.corrected == nil, "no corrected age for a term baby")
    expect.check(!ages.usesCorrectedAge, "term baby uses chronological age")
}

expect.suite("Corrected age for premature babies") {
    // Born 8 weeks early, so the due date was 8 weeks after birth.
    let profile = makeProfile(
        dateOfBirth: makeDate(2026, 1, 1),
        premature: true,
        gestationalAgeWeeks: 32,
        correctedAgeEnabled: true
    )
    let now = makeDate(2026, 5, 16)
    let ages = AgeCalculator.ages(for: profile, at: now)

    expect.check(ages.usesCorrectedAge, "engine is told to use corrected age")
    expect.equal(ages.corrected?.days, 79, "corrected age counts from the due date")
    expect.equal(ages.chronological.days - (ages.corrected?.days ?? 0), 56, "difference is exactly 8 weeks")
    expect.equal(ages.effective.days, ages.corrected?.days, "effective age is the corrected one")

    var disabled = profile
    disabled.correctedAgeEnabled = false
    let disabledAges = AgeCalculator.ages(for: disabled, at: now)
    expect.equal(disabledAges.effective.days, disabledAges.chronological.days, "opting out falls back to chronological")

    // Before the due date, corrected age is zero rather than negative.
    let early = AgeCalculator.ages(for: profile, at: makeDate(2026, 2, 1))
    expect.equal(early.corrected?.days, 0, "corrected age never goes negative")
}

// MARK: - Priors

expect.suite("Wake-window priors interpolate across published gaps") {
    let twoMonths = WakeWindowPriors.prior(forAgeMonths: 2)
    expect.equal(twoMonths.range.minMinutes, 60, "2 months uses the 1–3 month band minimum")
    expect.equal(twoMonths.range.maxMinutes, 120, "2 months uses the 1–3 month band maximum")

    // 4.5 months sits in the published gap between the 3–4 and 5–7 bands.
    let fourAndAHalf = WakeWindowPriors.prior(forAgeMonths: 4.5)
    expect.check(
        fourAndAHalf.range.minMinutes > 75 && fourAndAHalf.range.minMinutes < 120,
        "4.5 months interpolates the minimum (got \(fourAndAHalf.range.minMinutes))"
    )
    expect.check(
        fourAndAHalf.range.maxMinutes > 150 && fourAndAHalf.range.maxMinutes < 240,
        "4.5 months interpolates the maximum (got \(fourAndAHalf.range.maxMinutes))"
    )
    expect.check(
        WakeWindowPriors.prior(forAgeMonths: 4.0).range.maxMinutes
            < fourAndAHalf.range.maxMinutes,
        "priors increase monotonically with age"
    )

    let newborn = WakeWindowPriors.prior(forAgeMonths: 0.1)
    expect.equal(newborn.range.minMinutes, 30, "newborns clamp to the youngest band")
    expect.equal(newborn.range.maxMinutes, 60, "newborns clamp to the youngest band maximum")
    expect.check(!newborn.isExtrapolated, "inside published bands is not extrapolation")

    let toddler = WakeWindowPriors.prior(forAgeMonths: 18)
    expect.check(toddler.isExtrapolated, "18 months is past the published bands")
    expect.check(toddler.emphasizeNapStructure, "toddlers emphasise nap structure over wake windows")
    expect.close(toddler.reliability, 0.65, tolerance: 0.02, "prior reliability decays through toddlerhood")
    expect.equal(toddler.range.maxMinutes, 360, "no invented toddler precision: the last band is held")
    expect.close(WakeWindowPriors.prior(forAgeMonths: 11).reliability, 1.0, "priors are fully trusted under 12 months")
}

expect.suite("Total sleep priors") {
    let newborn = TotalSleepPriors.range(forAgeMonths: 1.5)
    expect.equal(newborn.minMinutes, 14 * 60, "0–3 months: 14 hours minimum")
    expect.equal(newborn.maxMinutes, 17 * 60, "0–3 months: 17 hours maximum")

    let infant = TotalSleepPriors.range(forAgeMonths: 8)
    expect.equal(infant.minMinutes, 12 * 60, "4–12 months: 12 hours minimum")

    let between = TotalSleepPriors.range(forAgeMonths: 3.5)
    expect.check(
        between.minMinutes > 12 * 60 && between.minMinutes < 14 * 60,
        "the 3–4 month gap is interpolated (got \(between.minMinutes) minutes)"
    )

    let toddler = TotalSleepPriors.range(forAgeMonths: 18)
    expect.equal(toddler.minMinutes, 11 * 60, "1–2 years: 11 hours minimum")
    expect.equal(toddler.maxMinutes, 14 * 60, "1–2 years: 14 hours maximum")
}

// MARK: - Duration and wake windows

expect.suite("Duration is always calculated") {
    let babyId = UUID()
    var event = SleepEvent(
        babyId: babyId,
        startedAt: makeDate(2026, 5, 16, 11, 4),
        endedAt: makeDate(2026, 5, 16, 12, 16)
    )
    expect.equal(event.durationMinutes, 72, "duration comes from start and end")

    // Moving the start moves the duration: there is no stored field to disagree with.
    event.startedAt = makeDate(2026, 5, 16, 11, 0)
    expect.equal(event.durationMinutes, 76, "editing the start recalculates the duration")

    let active = SleepEvent(babyId: babyId, startedAt: makeDate(2026, 5, 16, 11, 4))
    expect.check(active.durationMinutes == nil, "an active timer has no duration yet")
    expect.check(active.isActive, "an event without an end is active")
    expect.equal(active.elapsedMinutes(asOf: makeDate(2026, 5, 16, 12, 16)), 72, "elapsed time is available while running")

    let withPutDown = SleepEvent(
        babyId: babyId,
        startedAt: makeDate(2026, 5, 16, 11, 4),
        endedAt: makeDate(2026, 5, 16, 12, 16),
        putDownAt: makeDate(2026, 5, 16, 10, 49)
    )
    expect.equal(withPutDown.sleepLatencyMinutes, 15, "sleep latency is available when put-down time is recorded")
    expect.equal(withPutDown.durationMinutes, 72, "latency does not leak into the duration")
}

expect.suite("Nap indexing and wake windows follow the day's structure") {
    // The example day: 07:00 wake, three naps, 19:30 bedtime.
    let babyId = UUID()
    let day = makeDate(2026, 5, 16)
    let previousNight = SleepEvent(
        babyId: babyId,
        startedAt: addingDays(-1, to: settingTime(day, hour: 19, minute: 30)),
        endedAt: settingTime(day, hour: 7, minute: 0),
        type: .night,
        classificationSource: .manual
    )
    func nap(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) -> SleepEvent {
        SleepEvent(
            babyId: babyId,
            startedAt: settingTime(day, hour: startHour, minute: startMinute),
            endedAt: settingTime(day, hour: endHour, minute: endMinute),
            type: .nap,
            classificationSource: .manual
        )
    }
    let bedtime = SleepEvent(
        babyId: babyId,
        startedAt: settingTime(day, hour: 19, minute: 30),
        endedAt: settingTime(addingDays(1, to: day), hour: 7, minute: 0),
        type: .night,
        classificationSource: .manual
    )

    let events = SleepDerivation.recomputeDerivedFields(
        events: [previousNight, nap(9, 0, 10, 10), nap(12, 30, 13, 20), nap(15, 45, 16, 15), bedtime],
        calendar: sleepDayCalendar
    )
    let naps = events.filter { $0.type == .nap }.sorted { $0.startedAt < $1.startedAt }

    expect.equal(naps.map(\.napIndex), [1, 2, 3], "naps are numbered in order within the sleep day")
    expect.equal(naps.map(\.durationMinutes), [70, 50, 30], "nap durations")
    expect.equal(naps.map(\.wakeWindowBeforeMinutes), [120, 140, 145], "wake windows measure sleep-end to sleep-start")

    let night = events.first { $0.id == bedtime.id }
    expect.check(night?.napIndex == nil, "night sleep gets no nap index")
    expect.equal(night?.wakeWindowBeforeMinutes, 195, "the pre-bedtime wake window is measured the same way")

    // Retroactively inserting a nap renumbers the ones after it.
    let inserted = SleepDerivation.recomputeDerivedFields(
        events: events + [nap(11, 0, 11, 30)],
        calendar: sleepDayCalendar
    )
    let renumbered = inserted
        .filter { $0.type == .nap }
        .sorted { $0.startedAt < $1.startedAt }
        .map(\.napIndex)
    expect.equal(renumbered, [1, 2, 3, 4], "inserting a nap renumbers the rest of the day")

    // A night sleep is not a wake window: an implausible gap is dropped.
    let afterLongGap = SleepDerivation.wakeWindowMinutes(
        from: makeDate(2026, 5, 14, 7, 0),
        to: makeDate(2026, 5, 16, 9, 0)
    )
    expect.check(afterLongGap == nil, "a two-day gap is treated as missing data, not a wake window")
}

// MARK: - Classification

expect.suite("Nap versus night uses time of day and context") {
    let classifier = HeuristicSleepClassifier()
    let day = makeDate(2026, 5, 16)

    func classify(
        startHour: Int,
        startMinute: Int = 0,
        durationMinutes: Int?,
        sameDay: [SleepEvent] = [],
        profile: BabySleepProfile? = nil
    ) -> SleepClassificationResult {
        let start = settingTime(day, hour: startHour, minute: startMinute)
        return classifier.classify(
            SleepClassificationInput(
                startedAt: start,
                endedAt: durationMinutes.map { start.addingTimeInterval(minutes($0)) },
                ageMonths: 6,
                sameDayEvents: sameDay,
                sleepProfile: profile,
                calendar: sleepDayCalendar
            )
        )
    }

    expect.equal(classify(startHour: 20, durationMinutes: 660).type, .night, "a long sleep from 20:00 is night sleep")
    expect.equal(classify(startHour: 10, durationMinutes: 30).type, .nap, "a 30-minute sleep at 10:00 is a nap")
    expect.equal(classify(startHour: 9, durationMinutes: 70).type, .nap, "a morning sleep is a nap")
    expect.equal(classify(startHour: 2, durationMinutes: 40).type, .night, "a 02:00 waking is night sleep")
    expect.equal(
        classify(startHour: 19, startMinute: 30, durationMinutes: 30).type,
        .nap,
        "a brief evening sleep is still a catnap"
    )
    expect.equal(
        classify(startHour: 20, durationMinutes: nil).type,
        .night,
        "an evening timer with no end yet is provisionally night sleep"
    )

    // 17:30 is genuinely ambiguous, so the baby's own pattern decides.
    let shortLateNap = classify(startHour: 17, startMinute: 30, durationMinutes: 35)
    expect.equal(shortLateNap.type, .nap, "a short 17:30 sleep is a late nap")
    expect.check(shortLateNap.isAmbiguous, "the classifier admits when the call is close")

    let longLateSleep = classify(startHour: 17, startMinute: 30, durationMinutes: 300)
    expect.equal(longLateSleep.type, .night, "a long 17:30 sleep is bedtime")

    var earlyBedtimeBaby = BabySleepProfile.empty(babyId: UUID(), lookbackDays: 14)
    earlyBedtimeBaby.daysWithData = 10
    earlyBedtimeBaby.medianBedtimeMinutesFromMidnight = 17 * 60 + 45
    expect.equal(
        classify(startHour: 17, startMinute: 30, durationMinutes: nil, profile: earlyBedtimeBaby).type,
        .night,
        "for a baby with a 17:45 bedtime, 17:30 reads as bedtime"
    )

    // Once night sleep has started, a later waking is still night sleep.
    let bedtimeEvent = SleepEvent(
        babyId: UUID(),
        startedAt: settingTime(day, hour: 19, minute: 30),
        endedAt: settingTime(day, hour: 23, minute: 30),
        type: .night,
        classificationSource: .manual
    )
    expect.equal(
        classify(startHour: 23, startMinute: 45, durationMinutes: 200, sameDay: [bedtimeEvent]).type,
        .night,
        "a waking after bedtime is night sleep"
    )
}

// MARK: - Totals

expect.suite("Daily totals and rolling 24-hour sleep") {
    let babyId = UUID()
    let today = makeDate(2026, 5, 16)
    let specs = [
        DaySpec(naps: [(wakeWindow: 120, duration: 70), (wakeWindow: 140, duration: 50), (wakeWindow: 145, duration: 30)], bedtimeWakeWindow: 195),
        DaySpec(naps: [(wakeWindow: 120, duration: 70), (wakeWindow: 140, duration: 50), (wakeWindow: 145, duration: 30)], bedtimeWakeWindow: 195)
    ]
    let events = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-1, to: today),
        specs: specs,
        calendar: sleepDayCalendar
    )

    let noon = settingTime(today, hour: 12, minute: 0)
    let summary = analytics.summary(for: sleepDayCalendar.day(for: noon), events: events, dayFlags: [])
    expect.equal(summary.napCount, 3, "three naps today")
    expect.equal(summary.daytimeSleepMinutes, 150, "daytime sleep is the sum of today's naps")
    expect.equal(summary.nightSleepMinutes, 690, "last night's sleep counts towards today")
    expect.equal(summary.totalSleepMinutes, 840, "today's total is night plus naps")
    expect.check(summary.morningWakeAt != nil, "the morning wake time is available")
    expect.check(summary.bedtimeAt != nil, "tonight's bedtime is available")
    expect.equal(
        summary.wakeWindowsMinutes,
        [120, 140, 145, 195],
        "the day's wake windows are its own three naps plus bedtime"
    )

    // Rolling window, clipped precisely rather than bucketed by day.
    let rolling = analytics.totalSleep24hMinutes(asOf: noon, events: events)
    expect.check(rolling > 0 && rolling < 24 * 60, "rolling 24h total is plausible (got \(rolling))")

    // An active timer must not enter historical maths.
    let withActive = events + [SleepEvent(babyId: babyId, startedAt: settingTime(today, hour: 12, minute: 30))]
    expect.equal(
        analytics.totalSleep24hMinutes(asOf: settingTime(today, hour: 13, minute: 0), events: withActive),
        analytics.totalSleep24hMinutes(asOf: settingTime(today, hour: 13, minute: 0), events: events),
        "an in-progress sleep is excluded until it ends"
    )

    // At 08:30 the only sleep so far is last night, which ended at 07:00.
    let breakfastTime = settingTime(today, hour: 8, minute: 30)
    let eventsSoFar = events.filter { ($0.endedAt ?? .distantFuture) <= breakfastTime }
    expect.equal(
        analytics.awakeMinutes(asOf: breakfastTime, events: eventsSoFar),
        90,
        "awake time counts from the last wake"
    )
}

// MARK: - Derived sleep profile

expect.suite("Personal baseline is derived from raw events") {
    let babyId = UUID()
    let today = makeDate(2026, 5, 16)
    let spec = DaySpec(
        naps: [(wakeWindow: 120, duration: 70), (wakeWindow: 140, duration: 50), (wakeWindow: 150, duration: 40)],
        bedtimeWakeWindow: 190
    )
    let events = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-10, to: today),
        specs: Array(repeating: spec, count: 11),
        calendar: sleepDayCalendar
    )
    let builder = SleepProfileBuilder(analytics: analytics)
    let profile = builder.build(
        babyId: babyId,
        events: events,
        dayFlags: [],
        asOf: settingTime(today, hour: 12, minute: 0)
    )

    expect.equal(profile.medianWakeWindowByNap[1], 120, "median wake window before nap 1")
    expect.equal(profile.medianWakeWindowByNap[2], 140, "median wake window before nap 2")
    expect.equal(profile.medianWakeWindowByNap[3], 150, "median wake window before nap 3")
    expect.equal(profile.medianNapDurationByNap[2], 50, "median duration of nap 2")
    expect.equal(profile.medianWakeWindowBeforeNightMinutes, 190, "median wake window before bedtime")
    expect.equal(profile.medianNapsPerDay, 3, "median naps per day")
    expect.check((profile.sampleCountsByNap[2] ?? 0) >= 5, "sample counts are reported per nap")
    expect.check(profile.medianNapDurationMinutes != nil, "median nap duration is available")
    expect.check(profile.medianNightSleepMinutes != nil, "median night sleep is available")
    expect.check(profile.medianBedtimeMinutesFromMidnight != nil, "habitual bedtime is available")
}

// MARK: - Prediction

expect.suite("Prediction with no history uses the age prior only") {
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let babyId = profile.id
    let today = makeDate(2026, 5, 16)
    let engine = HeuristicSleepPredictionEngine(calendar: sleepDayCalendar)

    // One completed night sleep, so we know when the baby woke, and nothing else.
    let night = SleepEvent(
        babyId: babyId,
        startedAt: addingDays(-1, to: settingTime(today, hour: 19, minute: 30)),
        endedAt: settingTime(today, hour: 7, minute: 0),
        type: .night,
        classificationSource: .manual
    )
    let events = SleepDerivation.recomputeDerivedFields(events: [night], calendar: sleepDayCalendar)
    let ageMonths = AgeCalculator.effectiveAgeMonths(for: profile, at: today)
    let prior = WakeWindowPriors.prior(forAgeMonths: ageMonths)

    let prediction = engine.predictNextSleep(
        PredictionInput(
            now: settingTime(today, hour: 7, minute: 30),
            ageMonths: ageMonths,
            events: events,
            dayFlags: [],
            sleepProfile: BabySleepProfile.empty(babyId: babyId, lookbackDays: 14)
        )
    )

    guard let prediction else {
        expect.check(false, "a prediction is produced from the age prior alone")
        exit(expect.report())
    }

    expect.equal(prediction.dataSource, .agePrior, "with no history the data source is the age prior")
    expect.equal(prediction.confidence, .low, "the age prior alone is low confidence")
    expect.equal(prediction.sampleSize, 0, "no comparable observations yet")
    expect.equal(prediction.targetWakeWindowMinutes, prior.range.midpointMinutes, "target is the middle of the age range")
    expect.equal(prediction.expectedType, .nap, "the next sleep after the morning wake is a nap")
    expect.equal(prediction.expectedNapIndex, 1, "it is nap 1")
    expect.equal(
        prediction.predictedStartAt,
        settingTime(today, hour: 7, minute: 0).addingTimeInterval(minutes(prior.range.midpointMinutes)),
        "the prediction counts from the wake time"
    )
    expect.equal(
        Int(prediction.latestStartAt.timeIntervalSince(prediction.earliestStartAt) / 60),
        30,
        "the answer is a 30-minute window, never a single minute"
    )
    expect.check(
        prediction.earliestStartAt < prediction.predictedStartAt
            && prediction.predictedStartAt < prediction.latestStartAt,
        "the target sits in the middle of the range"
    )
}

expect.suite("Prediction blends personal history with the age prior") {
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let babyId = profile.id
    let today = makeDate(2026, 5, 16)
    let engine = HeuristicSleepPredictionEngine(calendar: sleepDayCalendar)
    let config = PredictionConfig.default

    // Five recent days with a consistent 140-minute window before nap 2.
    let nap2Windows = [137, 142, 145, 139, 151]
    let history = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-5, to: today),
        specs: nap2Windows.map { window in
            DaySpec(naps: [(wakeWindow: 120, duration: 70), (wakeWindow: window, duration: 50)], bedtimeWakeWindow: 200)
        } + [
            // Today so far: nap 1 done, nap 2 still to come.
            DaySpec(naps: [(wakeWindow: 120, duration: 70)], includeNight: false)
        ],
        calendar: sleepDayCalendar
    )

    let ageMonths = AgeCalculator.effectiveAgeMonths(for: profile, at: today)
    let prior = WakeWindowPriors.prior(forAgeMonths: ageMonths)
    let builder = SleepProfileBuilder(analytics: analytics)
    let now = settingTime(today, hour: 10, minute: 30)
    let sleepProfile = builder.build(babyId: babyId, events: history, dayFlags: [], asOf: now)

    guard let prediction = engine.predictNextSleep(
        PredictionInput(now: now, ageMonths: ageMonths, events: history, dayFlags: [], sleepProfile: sleepProfile)
    ) else {
        expect.check(false, "a prediction is produced")
        exit(expect.report())
    }

    let personalMedian = Statistics.median(nap2Windows)!
    let expectedTarget = Int(
        (config.personalWeightSomeHistory * personalMedian
            + (1 - config.personalWeightSomeHistory) * Double(prior.range.midpointMinutes)).rounded()
    )

    expect.equal(prediction.expectedNapIndex, 2, "the engine knows this is the transition after nap 1")
    expect.equal(prediction.sampleSize, 5, "five comparable observations")
    expect.equal(prediction.dataSource, .combined, "5–9 observations blend personal history with the prior")
    expect.equal(prediction.confidence, .medium, "some history means medium confidence")
    expect.equal(prediction.personalMedianMinutes, Int(personalMedian), "the personal target is the median, not the mean")
    expect.equal(prediction.targetWakeWindowMinutes, expectedTarget, "70% personal, 30% age prior")
    expect.check(
        prediction.targetWakeWindowMinutes < prior.range.midpointMinutes,
        "this baby's shorter windows pull the estimate below the age prior"
    )
}

expect.suite("Stronger history shifts weight further towards the baby") {
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let babyId = profile.id
    let today = makeDate(2026, 5, 16)
    let engine = HeuristicSleepPredictionEngine(calendar: sleepDayCalendar)
    let config = PredictionConfig.default

    let windows = [137, 142, 145, 139, 151, 140, 143, 138, 144, 141, 142]
    let history = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-11, to: today),
        specs: windows.map { window in
            DaySpec(naps: [(wakeWindow: 120, duration: 70), (wakeWindow: window, duration: 50)], bedtimeWakeWindow: 200)
        } + [DaySpec(naps: [(wakeWindow: 120, duration: 70)], includeNight: false)],
        calendar: sleepDayCalendar
    )
    let ageMonths = AgeCalculator.effectiveAgeMonths(for: profile, at: today)
    let prior = WakeWindowPriors.prior(forAgeMonths: ageMonths)
    let now = settingTime(today, hour: 10, minute: 30)
    let sleepProfile = SleepProfileBuilder(analytics: analytics)
        .build(babyId: babyId, events: history, dayFlags: [], asOf: now)

    guard let prediction = engine.predictNextSleep(
        PredictionInput(now: now, ageMonths: ageMonths, events: history, dayFlags: [], sleepProfile: sleepProfile)
    ) else {
        expect.check(false, "a prediction is produced")
        exit(expect.report())
    }

    // Only the last 14 days count, and only nap-2 transitions.
    expect.check(prediction.sampleSize >= config.strongHistorySampleCount, "at least ten comparable observations (got \(prediction.sampleSize))")
    expect.equal(prediction.confidence, .high, "a steady pattern with plenty of data earns high confidence")
    let personalMedian = prediction.personalMedianMinutes.map(Double.init)!
    let expectedTarget = Int(
        (config.personalWeightStrongHistory * personalMedian
            + (1 - config.personalWeightStrongHistory) * Double(prior.range.midpointMinutes)).rounded()
    )
    expect.equal(prediction.targetWakeWindowMinutes, expectedTarget, "80% personal, 20% age prior")
}

expect.suite("Personal history is robust and filtered") {
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let babyId = profile.id
    let today = makeDate(2026, 5, 16)
    let engine = HeuristicSleepPredictionEngine(calendar: sleepDayCalendar)

    // One chaotic day among five ordinary ones.
    let windows = [137, 142, 145, 139, 151, 400]
    let history = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-6, to: today),
        specs: windows.map { window in
            DaySpec(naps: [(wakeWindow: 120, duration: 70), (wakeWindow: window, duration: 50)], bedtimeWakeWindow: 200)
        } + [DaySpec(naps: [(wakeWindow: 120, duration: 70)], includeNight: false)],
        calendar: sleepDayCalendar
    )
    let ageMonths = AgeCalculator.effectiveAgeMonths(for: profile, at: today)
    let now = settingTime(today, hour: 10, minute: 30)
    let builder = SleepProfileBuilder(analytics: analytics)

    func predict(dayFlags: [DayFlag]) -> SleepPrediction? {
        engine.predictNextSleep(
            PredictionInput(
                now: now,
                ageMonths: ageMonths,
                events: history,
                dayFlags: dayFlags,
                sleepProfile: builder.build(babyId: babyId, events: history, dayFlags: dayFlags, asOf: now)
            )
        )
    }

    guard let withOutlier = predict(dayFlags: []) else {
        expect.check(false, "a prediction is produced")
        exit(expect.report())
    }
    let mean = Statistics.mean(windows)!
    expect.equal(withOutlier.personalMedianMinutes, 144, "the median absorbs the outlier day")
    expect.check(
        Double(withOutlier.personalMedianMinutes ?? 0) < mean - 40,
        "a mean would have been dragged to \(Int(mean)) minutes"
    )

    // Marking the odd day unusual removes it from personal history entirely.
    let outlierDay = sleepDayCalendar.day(for: settingTime(addingDays(-1, to: today), hour: 12, minute: 0))
    guard let filtered = predict(dayFlags: [DayFlag(babyId: babyId, day: outlierDay, contexts: [.unusualDay])]) else {
        expect.check(false, "a prediction is produced with the day marked")
        exit(expect.report())
    }
    expect.equal(filtered.sampleSize, withOutlier.sampleSize - 1, "a day marked unusual drops out of history")
    expect.equal(filtered.personalMedianMinutes, 142, "the remaining ordinary days set the median")
}

expect.suite("Bedtime is predicted as the next sleep after the last nap") {
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let babyId = profile.id
    let today = makeDate(2026, 5, 16)
    let engine = HeuristicSleepPredictionEngine(calendar: sleepDayCalendar)

    let spec = DaySpec(
        naps: [(wakeWindow: 120, duration: 70), (wakeWindow: 140, duration: 50), (wakeWindow: 150, duration: 40)],
        bedtimeWakeWindow: 190
    )
    // Ten full days of history, then today with all three naps done and bedtime still ahead.
    let events = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-10, to: today),
        specs: Array(repeating: spec, count: 10) + [
            DaySpec(
                naps: [(wakeWindow: 120, duration: 70), (wakeWindow: 140, duration: 50), (wakeWindow: 150, duration: 40)],
                includeNight: false
            )
        ],
        calendar: sleepDayCalendar
    )

    let lastNapEnd = events.lastCompleted?.endedAt
    let now = lastNapEnd!.addingTimeInterval(minutes(30))
    let ageMonths = AgeCalculator.effectiveAgeMonths(for: profile, at: now)
    let sleepProfile = SleepProfileBuilder(analytics: analytics)
        .build(babyId: babyId, events: events, dayFlags: [], asOf: now)

    guard let prediction = engine.predictNextSleep(
        PredictionInput(now: now, ageMonths: ageMonths, events: events, dayFlags: [], sleepProfile: sleepProfile)
    ) else {
        expect.check(false, "a bedtime prediction is produced")
        exit(expect.report())
    }

    expect.equal(prediction.expectedType, .night, "after the last nap the next sleep is bedtime")
    expect.check(prediction.expectedNapIndex == nil, "bedtime has no nap index")
    expect.check(prediction.sampleSize >= 5, "bedtime uses bedtime history (got \(prediction.sampleSize) samples)")
    let bedtimeHour = sleepDayCalendar.localHour(of: prediction.predictedStartAt)
    expect.check(bedtimeHour >= 18 && bedtimeHour <= 20, "predicted bedtime is in the evening (got hour \(bedtimeHour))")
}

expect.suite("Toddler predictions lean on the baby, not invented priors") {
    let profile = makeProfile(dateOfBirth: makeDate(2024, 11, 16))
    let babyId = profile.id
    let today = makeDate(2026, 5, 16)
    let engine = HeuristicSleepPredictionEngine(calendar: sleepDayCalendar)

    // A one-nap toddler whose own wake windows run to five and a half hours.
    let spec = DaySpec(naps: [(wakeWindow: 330, duration: 90)], bedtimeWakeWindow: 300)
    let events = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-12, to: today),
        specs: Array(repeating: spec, count: 12) + [DaySpec(naps: [], includeNight: false)],
        calendar: sleepDayCalendar
    )
    let ageMonths = AgeCalculator.effectiveAgeMonths(for: profile, at: today)
    expect.check(ageMonths > 17, "this is an 18-month-old (got \(String(format: "%.1f", ageMonths)))")

    let now = settingTime(today, hour: 8, minute: 0)
    let sleepProfile = SleepProfileBuilder(analytics: analytics)
        .build(babyId: babyId, events: events, dayFlags: [], asOf: now)

    guard let prediction = engine.predictNextSleep(
        PredictionInput(now: now, ageMonths: ageMonths, events: events, dayFlags: [], sleepProfile: sleepProfile)
    ) else {
        expect.check(false, "a toddler prediction is produced")
        exit(expect.report())
    }

    let prior = WakeWindowPriors.prior(forAgeMonths: ageMonths)
    expect.check(prior.isExtrapolated, "the age prior is extrapolated at this age")
    expect.equal(prediction.personalMedianMinutes, 330, "the toddler's own median wake window")

    let baseWeight = PredictionConfig.default.personalWeightStrongHistory
    let boostedWeight = baseWeight + (1 - prior.reliability) * (1 - baseWeight)
    let expectedTarget = Int(
        (boostedWeight * 330 + (1 - boostedWeight) * Double(prior.targetMinutes)).rounded()
    )
    let targetWithFullyTrustedPrior = baseWeight * 330 + (1 - baseWeight) * Double(prior.targetMinutes)

    expect.equal(prediction.targetWakeWindowMinutes, expectedTarget, "the weakened prior is folded in explicitly")
    expect.check(
        Double(prediction.targetWakeWindowMinutes) > targetWithFullyTrustedPrior,
        "past the published bands the prior is down-weighted (got \(prediction.targetWakeWindowMinutes))"
    )
    expect.check(
        prediction.targetWakeWindowMinutes > prior.targetMinutes,
        "the toddler's own pattern dominates the invented middle of the prior"
    )
}

expect.suite("Nothing is predicted while the baby is asleep") {
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let today = makeDate(2026, 5, 16)
    let engine = HeuristicSleepPredictionEngine(calendar: sleepDayCalendar)
    let events = [
        SleepEvent(
            babyId: profile.id,
            startedAt: addingDays(-1, to: settingTime(today, hour: 19, minute: 30)),
            endedAt: settingTime(today, hour: 7, minute: 0),
            type: .night,
            classificationSource: .manual
        ),
        SleepEvent(babyId: profile.id, startedAt: settingTime(today, hour: 9, minute: 0))
    ]
    let prediction = engine.predictNextSleep(
        PredictionInput(
            now: settingTime(today, hour: 9, minute: 30),
            ageMonths: 6,
            events: events,
            dayFlags: [],
            sleepProfile: BabySleepProfile.empty(babyId: profile.id, lookbackDays: 14)
        )
    )
    expect.check(prediction == nil, "a running timer means there is nothing to predict yet")

    // With nothing tracked at all, a parent-supplied wake time still works.
    let fallback = engine.predictNextSleep(
        PredictionInput(
            now: settingTime(today, hour: 8, minute: 0),
            ageMonths: 6,
            events: [],
            dayFlags: [],
            sleepProfile: BabySleepProfile.empty(babyId: profile.id, lookbackDays: 14),
            dayStartWake: settingTime(today, hour: 6, minute: 40)
        )
    )
    expect.check(fallback != nil, "the morning wake time is enough to predict the first nap")
    expect.equal(fallback?.basedOnWakeStartAt, settingTime(today, hour: 6, minute: 40), "it counts from that wake time")
    expect.check(fallback?.basedOnSleepEventId == nil, "no sleep event is credited for it")
}

// MARK: - Trends

expect.suite("Nap transitions are suggested, never declared") {
    let babyId = UUID()
    let today = makeDate(2026, 5, 16)
    let threeNapDay = DaySpec(
        naps: [(wakeWindow: 120, duration: 60), (wakeWindow: 130, duration: 60), (wakeWindow: 140, duration: 40)],
        bedtimeWakeWindow: 180
    )
    let twoNapDay = DaySpec(
        naps: [(wakeWindow: 180, duration: 90), (wakeWindow: 200, duration: 90)],
        bedtimeWakeWindow: 220
    )
    let events = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-15, to: today),
        specs: Array(repeating: threeNapDay, count: 10) + Array(repeating: twoNapDay, count: 5) + [threeNapDay],
        calendar: sleepDayCalendar
    )
    let detector = SleepTrendDetector(analytics: analytics)
    let signals = detector.detect(events: events, dayFlags: [], asOf: settingTime(today, hour: 12, minute: 0))

    expect.equal(signals.count, 1, "the shift from three naps to two is noticed")
    if let signal = signals.first {
        expect.equal(signal.kind, .possibleNapTransition, "it is reported as a possible nap transition")
        expect.check(
            signal.detail.contains("may be moving toward fewer naps"),
            "the wording stays tentative: \"\(signal.detail)\""
        )
        expect.check(signal.confidence != .high, "a trend hint is never presented as certain")
        expect.check(!signal.evidence.isEmpty, "the parent can see what prompted it")
    }

    // A steady baby gets no nudge.
    let steady = buildHistory(
        babyId: babyId,
        oldestDay: addingDays(-15, to: today),
        specs: Array(repeating: threeNapDay, count: 16),
        calendar: sleepDayCalendar
    )
    expect.check(
        detector.detect(events: steady, dayFlags: [], asOf: settingTime(today, hour: 12, minute: 0)).isEmpty,
        "a stable pattern produces no trend noise"
    )
}

// MARK: - Service

expect.suite("Start/stop flow keeps raw events and derived data consistent") {
    let repository = InMemorySleepRepository()
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let today = makeDate(2026, 5, 16)

    let service = try SleepService.create(profile: profile, repository: repository)
    try service.setDayStartHour(5)

    // Last night, so there is a wake time to count from.
    try service.addCompletedSleep(
        startedAt: addingDays(-1, to: settingTime(today, hour: 19, minute: 30)),
        endedAt: settingTime(today, hour: 7, minute: 0),
        now: settingTime(today, hour: 7, minute: 1),
        type: .night
    )

    let napStart = settingTime(today, hour: 9, minute: 4)
    try service.startSleep(at: napStart, now: napStart)
    expect.check(service.activeSleep != nil, "the timer is running")
    expect.throwsError("starting a second timer is refused") {
        try service.startSleep(at: napStart.addingTimeInterval(minutes(5)), now: napStart.addingTimeInterval(minutes(5)))
    }
    expect.check(
        service.prediction(asOf: napStart.addingTimeInterval(minutes(10))) == nil,
        "no prediction is offered while the baby sleeps"
    )

    let wakeTime = settingTime(today, hour: 10, minute: 16)
    let result = try service.stopSleep(at: wakeTime, now: wakeTime)
    expect.equal(result.event.durationMinutes, 72, "the duration is calculated on stop")
    expect.equal(result.event.type, .nap, "a 09:04 sleep is classified as a nap")
    expect.equal(result.event.napIndex, 1, "it is nap 1 of the day")
    expect.equal(result.event.wakeWindowBeforeMinutes, 124, "the preceding wake window is stored")
    expect.check(result.prediction != nil, "stopping produces the next-sleep estimate")
    expect.check(service.activeSleep == nil, "the timer has stopped")

    // Forgetting to start the timer is a correction to the start time, not the duration.
    let secondStart = settingTime(today, hour: 12, minute: 40)
    try service.startSleep(at: secondStart, now: secondStart)
    try service.adjustActiveStart(to: settingTime(today, hour: 12, minute: 30), now: secondStart)
    expect.equal(service.activeSleep?.startedAt, settingTime(today, hour: 12, minute: 30), "the start time moved")
    let secondStop = try service.stopSleep(
        at: settingTime(today, hour: 13, minute: 20),
        now: settingTime(today, hour: 13, minute: 20)
    )
    expect.equal(secondStop.event.durationMinutes, 50, "the duration follows the corrected start")
    expect.equal(secondStop.event.napIndex, 2, "it is nap 2")

    // Last night's sleep belongs to today's list, and only to today's.
    let todayKey = service.calendar.day(for: settingTime(today, hour: 12, minute: 0))
    let yesterdayKey = service.calendar.adding(days: -1, to: todayKey)
    expect.equal(service.events(on: todayKey).count, 3, "today shows its naps plus the night it woke from")
    expect.check(
        service.events(on: yesterdayKey).isEmpty,
        "the same night sleep is not listed again under yesterday"
    )

    let totals = service.totals(asOf: settingTime(today, hour: 14, minute: 0))
    expect.equal(totals.daytimeSleepMinutes, 122, "today's nap total")
    expect.equal(totals.nightSleepMinutes, 690, "last night's total")
    expect.check(totals.recommendedRange.minMinutes > 0, "age context is available alongside the totals")

    // A parent override sticks.
    try service.setType(.night, forEventId: secondStop.event.id)
    let overridden = service.events.first { $0.id == secondStop.event.id }
    expect.equal(overridden?.type, .night, "the parent's label is applied")
    expect.equal(overridden?.classificationSource, .manual, "and marked as theirs")
    expect.check(overridden?.napIndex == nil, "a night sleep loses its nap index")
    try service.setType(.nap, forEventId: secondStop.event.id)

    // Predictions are logged separately from observations.
    if let prediction = service.prediction(asOf: settingTime(today, hour: 14, minute: 0)) {
        try service.recordShownPrediction(prediction, now: settingTime(today, hour: 14, minute: 0))
    }
    expect.equal(service.dataset.predictions.count, 1, "the shown prediction is recorded")
    expect.equal(service.dataset.events.count, 3, "predictions never become observations")
    expect.check(
        service.dataset.predictions.first?.predictionVersion == service.predictionEngine.version,
        "the record names the engine version that produced it"
    )

    // Everything survives a round trip through storage.
    let reloaded = try SleepService.loadExisting(repository: repository)
    expect.equal(reloaded?.events.count, 3, "events are persisted")
    expect.equal(reloaded?.dataset.predictions.count, 1, "the prediction log is persisted")
    expect.equal(reloaded?.profile.id, profile.id, "the baby profile is persisted")

    expect.throwsError("a wake time before the sleep start is refused") {
        try service.addCompletedSleep(
            startedAt: settingTime(today, hour: 15, minute: 0),
            endedAt: settingTime(today, hour: 14, minute: 0),
            now: settingTime(today, hour: 16, minute: 0)
        )
    }
    expect.throwsError("a sleep starting in the future is refused") {
        try service.startSleep(
            at: settingTime(today, hour: 18, minute: 0),
            now: settingTime(today, hour: 16, minute: 0)
        )
    }
}

expect.suite("Marking a day unusual only filters, never adjusts") {
    let repository = InMemorySleepRepository()
    let profile = makeProfile(dateOfBirth: makeDate(2025, 11, 16))
    let today = makeDate(2026, 5, 16)
    let service = try SleepService.create(profile: profile, repository: repository)

    let day = service.calendar.day(for: addingDays(-1, to: today))
    try service.markDay(day, contexts: [.unusualDay, .travel], note: "Flight")
    expect.check(service.isDayUnusual(day), "the day is marked")
    expect.equal(service.dayFlag(for: day)?.contexts.count, 2, "both context tags are kept")

    try service.clearDayFlag(day)
    expect.check(!service.isDayUnusual(day), "the mark can be removed")

    // Context tags on an event never change a calculation.
    let event = try service.addCompletedSleep(
        startedAt: settingTime(today, hour: 9, minute: 0),
        endedAt: settingTime(today, hour: 10, minute: 0),
        now: settingTime(today, hour: 10, minute: 1),
        contexts: [.teething]
    )
    expect.equal(event.durationMinutes, 60, "a teething tag does not alter the duration")
}

expect.suite("Formatting keeps the tone right") {
    expect.equal(DurationFormatting.compact(102), "1h 42m", "compact duration")
    expect.equal(DurationFormatting.compact(58), "58m", "sub-hour duration")
    expect.equal(DurationFormatting.compact(822), "13h 42m", "long duration")
    expect.equal(DurationFormatting.approximate(140), "~2h 20m", "approximate duration")
    expect.equal(
        DurationFormatting.approximateHourRange(minMinutes: 120, maxMinutes: 240),
        "~2–4 hours",
        "broad age guidance"
    )

    let range = TimeFormatting.clockRange(
        from: makeDate(2026, 5, 16, 12, 45),
        to: makeDate(2026, 5, 16, 13, 15),
        timeZone: testTimeZone,
        locale: Locale(identifier: "en_US")
    )
    // Recent OS versions use a narrow no-break space before AM/PM.
    let normalizedRange = range.replacingOccurrences(of: "\u{202F}", with: " ")
    expect.equal(normalizedRange, "12:45–1:15 PM", "the prediction reads as a window")

    expect.equal(SleepCopy.basedOn(.personalHistory), "your baby's recent pattern", "personal-history attribution")
    expect.equal(SleepCopy.basedOn(.agePrior), "typical ranges for this age", "age-prior attribution")
    expect.equal(SleepCopy.typicalForAge(WakeWindowRange(minMinutes: 120, maxMinutes: 240)),
                 "Typical for this age: ~2–4 hours awake", "age context line")
    expect.equal(SleepCopy.thisBabyUsually(140), "Your baby usually: ~2h 20m", "personal comparison line")

    let authoritative = ["should", "must", "needs", "required"]
    let copy = [
        SleepCopy.predictionHeadline,
        SleepCopy.basedOn(.combined),
        SleepCopy.confidenceLabel(.low, sampleSize: 0),
        SleepCopy.confidenceLabel(.high, sampleSize: 12)
    ].joined(separator: " ").lowercased()
    expect.check(
        authoritative.allSatisfy { !copy.contains($0) },
        "prediction copy avoids medically authoritative language"
    )
}

exit(expect.report())
