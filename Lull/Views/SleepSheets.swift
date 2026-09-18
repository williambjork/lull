import SwiftUI
import LullCore

/// Shown right after the parent stops the timer: how long that sleep was, and
/// roughly when the baby may be ready again.
struct SleepSummarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let result: SleepStopResult

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(SleepCopy.durationLabel(for: result.event))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Text(DurationFormatting.compact(result.event.durationMinutes ?? 0))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                if let prediction = result.prediction {
                    Text(
                        SleepCopy.readyAgain(
                            name: model.babyName,
                            minutesUntilReady: prediction.targetWakeWindowMinutes,
                            nextType: prediction.expectedType
                        )
                    )
                    .font(.title3.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.awakeAccent, in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(Color.black.opacity(0.85))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                AtmosphereBackground(mood: .idle)
            }
            .foregroundStyle(.white)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Start a sleep that began a little while ago.
struct StartSleepSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    @State private var location: SleepLocation?

    var body: some View {
        NavigationStack {
            Form {
                Section("Fell asleep at") {
                    DatePicker("Time", selection: $startedAt, in: ...Date(), displayedComponents: [.hourAndMinute])
                    Text("Start the timer from when your baby actually fell asleep, not when you put them down.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Where") {
                    Picker("Location", selection: $location) {
                        Text("Not set").tag(SleepLocation?.none)
                        ForEach(SleepLocation.allCases, id: \.self) { option in
                            Text(SleepCopy.locationLabel(option)).tag(SleepLocation?.some(option))
                        }
                    }
                }
            }
            .navigationTitle("Start sleep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        model.startSleep(at: startedAt, location: location)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Correcting the start time of a running timer. The duration is never edited
/// directly — it always follows from the start and end times.
struct AdjustStartSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: SleepEvent

    @State private var startedAt: Date

    init(event: SleepEvent) {
        self.event = event
        _startedAt = State(initialValue: event.startedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fell asleep at") {
                    DatePicker("Time", selection: $startedAt, in: ...Date(), displayedComponents: [.hourAndMinute])
                }
                Section {
                    Text("Duration is always calculated from the start and wake times, so correcting the start is all you need.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Adjust start")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.adjustActiveStart(to: startedAt)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Lets a parent anchor the day when nothing has been tracked yet.
struct WakeTimeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var wokeAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Woke up this morning at") {
                    DatePicker("Time", selection: $wokeAt, in: ...Date(), displayedComponents: [.hourAndMinute])
                }
                Section {
                    Text("Used only to estimate the first sleep of the day until you start tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Wake time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.setDayStartWake(wokeAt)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
