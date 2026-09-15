import SwiftUI
import LullCore

/// A deliberately quiet palette: this app gets used at 03:00 in a dark room.
enum Theme {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.12)
    static let card = Color.white.opacity(0.07)
    static let cardBorder = Color.white.opacity(0.10)

    static let awakeAccent = Color(red: 0.98, green: 0.76, blue: 0.42)
    static let asleepAccent = Color(red: 0.55, green: 0.66, blue: 0.98)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)

    static func accent(isSleeping: Bool) -> Color {
        isSleeping ? asleepAccent : awakeAccent
    }

    static func backgroundGradient(isSleeping: Bool) -> LinearGradient {
        LinearGradient(
            colors: isSleeping
                ? [Color(red: 0.06, green: 0.08, blue: 0.20), background]
                : [Color(red: 0.13, green: 0.10, blue: 0.16), background],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Card container used by every screen.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// Small pill used for confidence and context tags.
struct TagLabel: View {
    let text: String
    var tint: Color = Theme.secondaryText

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

extension PredictionConfidence {
    var tint: Color {
        switch self {
        case .low: Theme.tertiaryText
        case .medium: Theme.awakeAccent
        case .high: Color(red: 0.55, green: 0.85, blue: 0.62)
        }
    }

    var shortLabel: String {
        switch self {
        case .low: "Rough estimate"
        case .medium: "Getting there"
        case .high: "Steady pattern"
        }
    }
}
