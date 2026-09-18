import SwiftUI
import LullCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAddSleep = false

    private var summaries: [DailySleepSummary] {
        let recorded = model.allSummaries()
        guard let today = model.today else { return recorded }
        // Always show today, even before anything has been tracked.
        if recorded.first?.day == today { return recorded }
        let todaySummary = model.summaries(days: 1).first
        return [todaySummary].compactMap { $0 } + recorded
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(summaries) { summary in
                    Section {
                        let events = model.events(on: summary.day).filter(\.isCompleted)
                        if events.isEmpty {
                            Text("Nothing tracked")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(events) { event in
                            NavigationLink {
                                SleepDetailView(eventId: event.id)
                            } label: {
                                SleepRow(event: event)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                model.deleteSleep(id: events[index].id)
                            }
                        }
                    } header: {
                        DayHeader(summary: summary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddSleep = true } label: {
                        Label("Add sleep", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSleep) {
                AddSleepView()
            }
        }
    }
}

struct DayHeader: View {
    @Environment(AppModel.self) private var model
    let summary: DailySleepSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    Toggle("Unusual day", isOn: Binding(
                        get: { summary.isUnusual },
                        set: { model.setDayUnusual($0, day: summary.day) }
                    ))
                } label: {
                    Image(systemName: summary.isUnusual ? "flag.fill" : "flag")
                        .font(.footnote)
                }
            }

            HStack(spacing: 14) {
                Text("Total \(DurationFormatting.compact(summary.totalSleepMinutes))")
                Text("Night \(DurationFormatting.compact(summary.nightSleepMinutes))")
                Text("Naps \(DurationFormatting.compact(summary.daytimeSleepMinutes))")
                if summary.napCount > 0 {
                    Text("\(summary.napCount) nap\(summary.napCount == 1 ? "" : "s")")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if summary.isUnusual {
                Text("Left out of your baby's pattern")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private var title: String {
        guard let service = model.service else { return summary.day.description }
        let date = service.calendar.start(of: summary.day)
        let formatter = DateFormatter()
        formatter.timeZone = model.timeZone
        formatter.dateFormat = "EEEE d MMM"
        if summary.day == model.today { return "Today" }
        if let yesterday = model.today.map({ service.calendar.adding(days: -1, to: $0) }), summary.day == yesterday {
            return "Yesterday"
        }
        return formatter.string(from: date)
    }
}

/// Editing an existing sleep. Start and wake times are editable; duration is
/// shown but never editable.
struct SleepDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let eventId: UUID

    @State private var startedAt = Date()
    @State private var endedAt = Date()
    @State private var location: SleepLocation?
    @State private var method: SleepMethod?
    @State private var notes = ""
    @State private var loaded = false

    private var event: SleepEvent? {
        model.service?.events.first { $0.id == eventId }
    }

    var body: some View {
        Form {
            if let event {
                Section("Times") {
                    DatePicker("Fell asleep", selection: $startedAt, in: ...Date())
                    if event.isCompleted {
                        DatePicker("Woke up", selection: $endedAt, in: startedAt...Date())
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(DurationFormatting.compact(
                            max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
                        ))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    if let window = event.wakeWindowBeforeMinutes {
                        HStack {
                            Text("Awake before")
                            Spacer()
                            Text(DurationFormatting.compact(window))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Type") {
                    Picker("Sleep type", selection: Binding(
                        get: { event.type },
                        set: { model.setType($0, for: eventId) }
                    )) {
                        Text("Nap").tag(SleepType.nap)
                        Text("Night sleep").tag(SleepType.night)
                    }
                    .pickerStyle(.segmented)

                    if let reason = event.classificationReason {
                        Text(event.classificationSource == .manual ? "Set by you" : reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Context") {
                    Picker("Where", selection: $location) {
                        Text("Not set").tag(SleepLocation?.none)
                        ForEach(SleepLocation.allCases, id: \.self) { option in
                            Text(SleepCopy.locationLabel(option)).tag(SleepLocation?.some(option))
                        }
                    }
                    Picker("Fell asleep by", selection: $method) {
                        Text("Not set").tag(SleepMethod?.none)
                        ForEach(SleepMethod.allCases, id: \.self) { option in
                            Text(SleepCopy.methodLabel(option)).tag(SleepMethod?.some(option))
                        }
                    }
                }

                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                }

                Section {
                    Button("Delete this sleep", role: .destructive) {
                        model.deleteSleep(id: eventId)
                        dismiss()
                    }
                }
            } else {
                Text("This sleep is no longer available.")
            }
        }
        .navigationTitle(event.map { SleepCopy.eventTitle($0) } ?? "Sleep")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let event else { return }
        startedAt = event.startedAt
        endedAt = event.endedAt ?? Date()
        location = event.sleepLocation
        method = event.sleepMethod
        notes = event.notes ?? ""
        loaded = true
    }

    private func save() {
        guard let event else { return }
        model.updateSleep(
            id: eventId,
            startedAt: startedAt,
            endedAt: event.isCompleted ? endedAt : nil,
            location: location,
            method: method,
            notes: notes.isEmpty ? nil : notes
        )
    }
}

struct AddSleepView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date().addingTimeInterval(-3600)
    @State private var endedAt = Date()
    @State private var typeSelection: SleepType?
    @State private var location: SleepLocation?
    @State private var method: SleepMethod?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Times") {
                    DatePicker("Fell asleep", selection: $startedAt, in: ...Date())
                    DatePicker("Woke up", selection: $endedAt, in: startedAt...Date())
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(DurationFormatting.compact(max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Type") {
                    Picker("Sleep type", selection: $typeSelection) {
                        Text("Decide for me").tag(SleepType?.none)
                        Text("Nap").tag(SleepType?.some(.nap))
                        Text("Night").tag(SleepType?.some(.night))
                    }
                }

                Section("Context") {
                    Picker("Where", selection: $location) {
                        Text("Not set").tag(SleepLocation?.none)
                        ForEach(SleepLocation.allCases, id: \.self) { option in
                            Text(SleepCopy.locationLabel(option)).tag(SleepLocation?.some(option))
                        }
                    }
                    Picker("Fell asleep by", selection: $method) {
                        Text("Not set").tag(SleepMethod?.none)
                        ForEach(SleepMethod.allCases, id: \.self) { option in
                            Text(SleepCopy.methodLabel(option)).tag(SleepMethod?.some(option))
                        }
                    }
                }

                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add sleep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addPastSleep(
                            startedAt: startedAt,
                            endedAt: endedAt,
                            type: typeSelection,
                            location: location,
                            method: method,
                            notes: notes.isEmpty ? nil : notes
                        )
                        dismiss()
                    }
                    .disabled(endedAt < startedAt)
                }
            }
        }
    }
}
