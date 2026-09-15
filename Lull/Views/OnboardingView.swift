import SwiftUI
import LullCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var name = ""
    @State private var dateOfBirth = Date()
    @State private var wasPremature = false
    @State private var gestationalAgeWeeks = 34
    @State private var correctedAgeEnabled = true

    var body: some View {
        ZStack {
            Theme.backgroundGradient(isSleeping: false).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lull")
                            .font(.largeTitle.bold())
                        Text("Track sleep, and get a sense of when your baby is likely to be ready for the next one.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name (optional)")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                            TextField("Baby's name", text: $name)
                                .textFieldStyle(.plain)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                        DatePicker(
                            "Date of birth",
                            selection: $dateOfBirth,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .font(.subheadline)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Born prematurely", isOn: $wasPremature)
                            .font(.subheadline)

                        if wasPremature {
                            Stepper(
                                "Gestational age: \(gestationalAgeWeeks) weeks",
                                value: $gestationalAgeWeeks,
                                in: 22...37
                            )
                            .font(.subheadline)

                            Toggle("Use corrected age", isOn: $correctedAgeEnabled)
                                .font(.subheadline)

                            Text("Corrected age counts from the due date instead of the birth date. Estimates use it when it's on.")
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    .card()

                    Text(SleepCopy.disclaimer)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)

                    Button {
                        model.createProfile(
                            name: name,
                            dateOfBirth: dateOfBirth,
                            wasPremature: wasPremature,
                            gestationalAgeWeeks: gestationalAgeWeeks,
                            correctedAgeEnabled: correctedAgeEnabled
                        )
                    } label: {
                        Text("Start tracking")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.awakeAccent, in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(Color.black.opacity(0.85))
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .foregroundStyle(.white)
    }
}
