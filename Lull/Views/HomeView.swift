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
            AtmosphereBackground(mood: model.atmosphereMood)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)

                Spacer(minLength: 12)

                Group {
                    if model.isSleeping {
                        sleepingCard
                    } else {
                        awakeCard
                    }
                }

                if !model.trends.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(model.trends) { signal in
                            TrendBanner(signal: signal)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                Spacer(minLength: 12)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(alignment: .center, spacing: 12) {
            BabyAvatarButton(size: 44, showsEditBadge: false)

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
    // Content-sized card: prediction → Start Sleep → awake-for + add

    private var awakeCard: some View {
        VStack(spacing: 28) {
            if let prediction = model.prediction {
                PredictionBlock(prediction: prediction)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tell Nana when your baby woke up and it can estimate the next sleep.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Set today's wake time") { showingWakeTimeSheet = true }
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            primarySleepButton(
                title: "Start Sleep",
                tint: Theme.awakeAccent,
                action: { model.startSleep() }
            )

            awakeBottomBand
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var awakeBottomBand: some View {
        HStack(alignment: .center, spacing: 16) {
            awakeForBlock

            Spacer(minLength: 8)

            addSleepIconButton
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var awakeForBlock: some View {
        if let awake = model.awakeMinutes {
            VStack(alignment: .leading, spacing: 6) {
                Text("Awake for")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(DurationFormatting.compact(awake))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No sleep tracked yet today")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Opens `StartSleepSheet` — backdate start or add details (same as the old text link).
    private var addSleepIconButton: some View {
        Button {
            showingStartSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.awakeAccent)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.14), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fell asleep earlier, or add details")
    }

    // MARK: - Sleeping
    // Content-sized card: Stop Sleep → live timer → adjust/cancel

    private var sleepingCard: some View {
        VStack(spacing: 24) {
            primarySleepButton(
                title: "Stop Sleep",
                tint: Theme.asleepAccent,
                action: { model.stopSleep() }
            )

            VStack(spacing: 8) {
                Text(DurationFormatting.timer(seconds: model.activeElapsedSeconds ?? 0))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                if let active = model.activeSleep {
                    Text("Started \(model.formattedClock(active.startedAt))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            HStack(spacing: 24) {
                Button("Adjust start time") { showingAdjustStart = true }
                Button("Cancel this sleep", role: .destructive) { model.cancelActiveSleep() }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func primarySleepButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        PillowMorphButton(title: title, tint: tint, action: action)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Prediction

struct PredictionBlock: View {
    @Environment(AppModel.self) private var model
    let prediction: SleepPrediction

    private var isInWindow: Bool {
        prediction.isInWindow(asOf: model.now)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(SleepCopy.predictionHeadline)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)

            Text(model.formattedClock(prediction.predictedStartAt))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.top, 6)

            if isInWindow {
                Text("In the likely window now.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.awakeAccent)
                    .padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
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
