import SwiftUI
import LullCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        LullBrandMark(style: .badge, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nana")
                                .font(.title3.weight(.semibold))
                            Text("Baby sleep, gently tracked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.clear)
                }

                if let service = model.service {
                    Section("Baby") {
                        HStack(spacing: 16) {
                            BabyAvatarButton(size: 64, showsEditBadge: true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.babyName)
                                    .font(.headline)
                                Text(model.hasCustomBabyAvatar ? "Tap to change or remove photo" : "Tap to add a photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                        TextField("Name", text: Binding(
                            get: { service.profile.name },
                            set: { name in model.updateProfile { $0.name = name } }
                        ))
                        DatePicker(
                            "Date of birth",
                            selection: Binding(
                                get: { service.profile.dateOfBirth },
                                set: { date in model.updateProfile { $0.dateOfBirth = date } }
                            ),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        if let ages = model.ages {
                            HStack {
                                Text("Age")
                                Spacer()
                                Text("\(SleepCopy.ageDescription(ages.chronological)) · \(ages.chronological.days) days")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Day") {
                        Picker("New day starts at", selection: Binding(
                            get: { service.dataset.settings.dayStartHour },
                            set: { model.setDayStartHour($0) }
                        )) {
                            ForEach(2...8, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        Text("Used to group naps and totals. A night waking after this hour starts a new day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("How estimates work") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nana starts from broad age-based ranges and shifts towards your baby's own pattern as you track more sleeps.")
                            Text("Under \(model.service?.predictionConfig.minSamplesForPersonal ?? 5) similar days it uses age ranges only; after \(model.service?.predictionConfig.strongHistorySampleCount ?? 10) it leans mostly on your baby.")
                            Text("Estimates are always a window, because there isn't a single correct minute.")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Delete all data", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }

                Section {
                    Text(SleepCopy.disclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all sleep data?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { model.deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the baby profile and every tracked sleep from this device.")
            }
        }
    }
}
