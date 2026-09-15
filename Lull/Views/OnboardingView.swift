import SwiftUI
import LullCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var name = ""
    @State private var dateOfBirth = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    LullBrandMark(style: .badge, size: 96)
                    Text("Lull")
                        .font(.largeTitle.bold())
                    Text("Track sleep, and get a sense of when your baby is likely to be ready for the next one.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 40)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Lull")

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

                Text(SleepCopy.disclaimer)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)

                Button {
                    model.createProfile(
                        name: name,
                        dateOfBirth: dateOfBirth
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
        .background { AtmosphereBackground(mood: .idle) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}
