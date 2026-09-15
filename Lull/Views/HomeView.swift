import SwiftUI
import LullCore

/// The one screen that answers the only question a tired parent has:
/// "when will my baby probably be ready to sleep again?"
struct HomeView: View {
    @Environment(AppModel.self) private var model

    @State private var showingStartSheet = false
    @State private var showingAdjustStart = false
    @State private var showingWakeTimeSheet = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient(isSleeping: model.isSleeping).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    if model.isSleeping {
                        sleepingCard
                    } else {
                        awakeCard
                    }

                    ForEach(model.trends) { signal in
                        TrendBanner(signal: signal)
                    }

                    if let totals = model.totals {
                        TotalsCard(totals: totals)
                    }

                    RecentSleepsCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showingStartSheet) {
            StartSleepSheet()
        }
        .sheet(isPresented: $showingAdjustStart) {
            if let active = model.activeSleep {
                AdjustStartSheet(event: active)
            }
        }
        .sheet(isPresented: $showingWakeTimeSheet) {
            WakeTimeSheet()
        }
        .sheet(
            isPresented: Binding(
                get: { model.lastStopResult != nil },
                set: { if !$0 { model.lastStopResult = nil } }
            )
        ) {
            if let result = model.lastStopResult {
                SleepSummarySheet(result: result)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.babyName)
                .font(.title3.weight(.semibold))
            Spacer()
            if let ages = model.ages {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(SleepCopy.ageDescription(ages.effective))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if ages.usesCorrectedAge {
                        Text("corrected age")
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Awake

    private var awakeCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SleepCopy.awakeLabel)
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Theme.awakeAccent)

                if let awake = model.awakeMinutes {
                    Text("Awake for")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Text(DurationFormatting.compact(awake))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                } else {
                    Text("No sleep tracked yet today")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let prediction = model.prediction {
                PredictionBlock(prediction: prediction)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tell Lull when your baby woke up and it can estimate the next sleep.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Set today's wake time") { showingWakeTimeSheet = true }
                        .font(.subheadline.weight(.medium))
                }
            }

            VStack(spacing: 10) {
                Button {
                    model.startSleep()
                } label: {
                    Text("Start Sleep")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.awakeAccent, in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(Color.black.opacity(0.85))
                }

                Button("Fell asleep earlier, or add details") { showingStartSheet = true }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(padding: 24)
    }

    // MARK: - Sleeping

    private var sleepingCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SleepCopy.sleepingLabel)
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Theme.asleepAccent)

                Text(DurationFormatting.compact(model.activeElapsedMinutes ?? 0))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                if let active = model.activeSleep {
                    Text("Started \(model.formattedClock(active.startedAt))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            VStack(spacing: 10) {
                Button {
                    model.stopSleep()
                } label: {
                    Text("Stop Sleep")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.asleepAccent, in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(Color.black.opacity(0.85))
                }

                HStack(spacing: 18) {
                    Button("Adjust start time") { showingAdjustStart = true }
                    Button("Cancel this sleep", role: .destructive) { model.cancelActiveSleep() }
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(padding: 24)
    }
}

// MARK: - Prediction

struct PredictionBlock: View {
    @Environment(AppModel.self) private var model
    let prediction: SleepPrediction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(headline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                TagLabel(text: prediction.confidence.shortLabel, tint: prediction.confidence.tint)
            }

            Text(model.formattedRange(prediction))
                .font(.system(size: 34, weight: .semibold, design: .rounded))

            Text("Based on \(SleepCopy.basedOn(prediction.dataSource))")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            if prediction.hasPassed(asOf: model.now) {
                Text("That window has passed — plenty of babies drift later some days.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            } else if prediction.isInWindow(asOf: model.now) {
                Text("In the likely window now.")
                    .font(.caption)
                    .foregroundStyle(Theme.awakeAccent)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var headline: String {
        let title = SleepCopy.nextSleepTitle(prediction)
        return "\(SleepCopy.predictionHeadline) · \(title)"
    }
}

// MARK: - Totals

struct TotalsCard: View {
    let totals: SleepTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)

            Text(DurationFormatting.compact(totals.todayTotalMinutes))
                .font(.system(size: 30, weight: .semibold, design: .rounded))

            HStack(spacing: 28) {
                statistic("Night", minutes: totals.nightSleepMinutes)
                statistic("Naps", minutes: totals.daytimeSleepMinutes)
                statistic("Last 24h", minutes: totals.totalSleep24hMinutes)
            }

            Text(SleepCopy.totalSleepContext(totals))
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
        .card()
    }

    private func statistic(_ label: String, minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
            Text(DurationFormatting.compact(minutes))
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - Trend banner

struct TrendBanner: View {
    let signal: SleepTrendSignal
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(signal.headline, systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(isExpanded ? "Hide" : "Why?") { isExpanded.toggle() }
                    .font(.caption)
            }
            Text(signal.detail)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(signal.evidence, id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
        .card(padding: 16)
    }
}

// MARK: - Recent sleeps

struct RecentSleepsCard: View {
    @Environment(AppModel.self) private var model

    private var recent: [SleepEvent] {
        guard let today = model.today else { return [] }
        let days = [today, model.service?.calendar.adding(days: -1, to: today)].compactMap { $0 }
        return days
            .flatMap { model.events(on: $0) }
            .filter(\.isCompleted)
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent sleeps")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)

                ForEach(recent) { event in
                    SleepRow(event: event)
                }
            }
            .card()
        }
    }
}

struct SleepRow: View {
    @Environment(AppModel.self) private var model
    let event: SleepEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(SleepCopy.eventTitle(event))
                    .font(.callout.weight(.medium))
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatting.compact(event.durationMinutes ?? 0))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                if let window = event.wakeWindowBeforeMinutes {
                    Text("awake \(DurationFormatting.compact(window)) before")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }

    private var timeRange: String {
        guard let endedAt = event.endedAt else {
            return "from \(model.formattedClock(event.startedAt))"
        }
        return "\(model.formattedClock(event.startedAt)) – \(model.formattedClock(endedAt))"
    }
}
