import SwiftUI
import LullCore

/// Context, not a report card. Everything here is framed as "what your baby
/// tends to do" next to "what's typical for this age".
struct InsightsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if let prior = model.agePrior {
                    Section("Typical for this age") {
                        row(
                            "Awake between sleeps",
                            DurationFormatting.approximateHourRange(
                                minMinutes: prior.range.minMinutes,
                                maxMinutes: prior.range.maxMinutes
                            )
                        )
                        if let profile = model.sleepProfile, let median = profile.medianWakeWindowMinutes {
                            row("Your baby usually", DurationFormatting.approximate(median))
                        }
                        Text(priorCaveat(prior))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let profile = model.sleepProfile, profile.hasAnyData {
                    Section("Your baby's pattern") {
                        ForEach(profile.medianWakeWindowByNap.keys.sorted(), id: \.self) { napIndex in
                            if let window = profile.medianWakeWindowByNap[napIndex] {
                                row(
                                    "Awake before nap \(napIndex)",
                                    DurationFormatting.approximate(window),
                                    detail: sampleCaption(profile.sampleCountsByNap[napIndex] ?? 0)
                                )
                            }
                        }
                        ForEach(profile.medianNapDurationByNap.keys.sorted(), id: \.self) { napIndex in
                            if let duration = profile.medianNapDurationByNap[napIndex] {
                                row("Nap \(napIndex) usually lasts", DurationFormatting.approximate(duration))
                            }
                        }
                        if let night = profile.medianWakeWindowBeforeNightMinutes {
                            row("Awake before bedtime", DurationFormatting.approximate(night))
                        }
                        if let nightSleep = profile.medianNightSleepMinutes {
                            row("Night sleep", DurationFormatting.approximate(nightSleep))
                        }
                        if let naps = profile.medianNapsPerDay {
                            row("Naps per day", naps == naps.rounded() ? "\(Int(naps))" : String(format: "%.1f", naps))
                        }
                        if let bedtime = profile.medianBedtimeMinutesFromMidnight, let service = model.service,
                           let today = model.today {
                            row(
                                "Usual bedtime",
                                model.formattedClock(service.calendar.date(minutesFromMidnight: bedtime, on: today))
                            )
                        }
                        Text("Based on the last \(profile.lookbackDays) days, ignoring days you marked unusual.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your baby's pattern") {
                        Text("A few days of tracking and Nana will start using your baby's own rhythm instead of age-based ranges.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !model.trends.isEmpty {
                    Section("Worth noticing") {
                        ForEach(model.trends) { signal in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(signal.headline)
                                    .font(.subheadline.weight(.medium))
                                Text(signal.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                ForEach(signal.evidence, id: \.self) { item in
                                    Text("• \(item)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                let cues = model.cueStats()
                if !cues.isEmpty {
                    Section("Sleepy cues you record most") {
                        ForEach(cues) { stat in
                            row(
                                SleepCopy.cueLabel(stat.cue),
                                "\(stat.occurrences) sleeps",
                                detail: stat.medianSleepDurationMinutes.map {
                                    "usually sleeps \(DurationFormatting.compact($0))"
                                }
                            )
                        }
                        Text("Early days: this is descriptive only, not a prediction.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(SleepCopy.disclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Patterns")
        }
    }

    private func row(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sampleCaption(_ count: Int) -> String {
        count == 1 ? "1 similar day" : "\(count) similar days"
    }

    private func priorCaveat(_ prior: AgeWakeWindowPrior) -> String {
        if prior.emphasizeNapStructure {
            return "Wake-window guidance thins out after a year. From here, nap structure and total sleep tell you more."
        }
        return "Wake-window ranges are practical rules of thumb rather than validated rules, so treat them as a guide."
    }
}
