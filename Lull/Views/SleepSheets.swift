import SwiftUI
import LullCore

/// Shown right after the parent stops the timer: what just happened, and what
/// is probably next.
struct SleepSummarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let result: SleepStopResult

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(SleepCopy.eventTitle(result.event))
                        .font(.title3.weight(.semibold))
                    Text(DurationFormatting.compact(result.event.durationMinutes ?? 0))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                }

                if let window = result.event.wakeWindowBeforeMinutes {
                    labelled("Previous wake window", value: DurationFormatting.compact(window))
                }

                if let prediction = result.prediction {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next sleep likely · \(SleepCopy.nextSleepTitle(prediction))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        Text(model.formattedClock(prediction.predictedStartAt))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Based on \(SleepCopy.basedOn(prediction.dataSource))")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
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
                // Sheet hosts size `.background` correctly; ZStack would fight NavigationStack chrome.
                AtmosphereBackground(mood: .idle)
            }
            .foregroundStyle(.white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit") { SleepDetailView(eventId: result.event.id) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func labelled(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
    }
}

/// Start a sleep that began a little while ago, with optional context.
struct StartSleepSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    @State private var cues: Set<SleepCue> = []
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

                Section("Sleepy cues you noticed") {
                    CuePicker(selection: $cues)
                }
            }
            .navigationTitle("Start sleep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        model.startSleep(at: startedAt, cues: Array(cues), location: location)
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

struct CuePicker: View {
    @Binding var selection: Set<SleepCue>

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(SleepCue.allCases, id: \.self) { cue in
                Button {
                    if selection.contains(cue) {
                        selection.remove(cue)
                    } else {
                        selection.insert(cue)
                    }
                } label: {
                    Text(SleepCopy.cueLabel(cue))
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            selection.contains(cue) ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
