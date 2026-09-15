import SwiftUI
import UIKit
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
        atmosphereGradient(mood: isSleeping ? .asleep : .idle, phase: 0)
    }

    // MARK: - Atmosphere tokens

    /// Top-stop colors for `AtmosphereBackground` (base stays `background`).
    /// Mid strength: darker mauve/blue base kept, glow/contrast dialed below the loud pass.
    static let atmosphereIdleTop = Color(red: 0.21, green: 0.135, blue: 0.22)
    static let atmosphereIdleTopDrift = Color(red: 0.29, green: 0.175, blue: 0.29)
    static let atmosphereAsleepTop = Color(red: 0.09, green: 0.14, blue: 0.32)
    static let atmosphereAsleepTopDrift = Color(red: 0.14, green: 0.205, blue: 0.42)
    static let atmosphereNightTop = Color(red: 0.055, green: 0.09, blue: 0.25)
    static let atmosphereNightTopDrift = Color(red: 0.09, green: 0.14, blue: 0.355)

    static let atmosphereGrainOpacity: Double = 0.058

    static func atmosphereGradient(mood: AtmosphereMood, phase: Double) -> LinearGradient {
        let (a, b) = atmosphereTopPair(mood: mood)
        let t = softWave(phase)
        let top = blend(a, b, t: t)
        // Lift the lower stop so the vertical wash isn’t flat navy — quieter than the loud pass.
        let liftedBottom = blend(background, a, t: 0.25)
        let bottom = blend(liftedBottom, b, t: t * 0.36)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func atmosphereBlobColor(mood: AtmosphereMood, phase: Double) -> Color {
        let t = softWave(phase + 0.25)
        switch mood {
        case .idle:
            return blend(
                Color(red: 0.98, green: 0.76, blue: 0.42, opacity: 0.46),
                Color(red: 0.98, green: 0.70, blue: 0.50, opacity: 0.30),
                t: t
            )
        case .asleep:
            return blend(
                Color(red: 0.55, green: 0.68, blue: 0.99, opacity: 0.44),
                Color(red: 0.44, green: 0.56, blue: 0.95, opacity: 0.28),
                t: t
            )
        case .night:
            return blend(
                Color(red: 0.36, green: 0.46, blue: 0.92, opacity: 0.40),
                Color(red: 0.45, green: 0.55, blue: 0.96, opacity: 0.24),
                t: t
            )
        }
    }

    static func atmosphereBlobOpacity(mood: AtmosphereMood) -> Double {
        switch mood {
        case .idle: 0.80
        case .asleep: 0.74
        case .night: 0.66
        }
    }

    static func atmosphereBlobScale(mood: AtmosphereMood) -> CGFloat {
        switch mood {
        case .idle: 0.76
        case .asleep: 0.82
        case .night: 0.90
        }
    }

    private static func atmosphereTopPair(mood: AtmosphereMood) -> (Color, Color) {
        switch mood {
        case .idle: (atmosphereIdleTop, atmosphereIdleTopDrift)
        case .asleep: (atmosphereAsleepTop, atmosphereAsleepTopDrift)
        case .night: (atmosphereNightTop, atmosphereNightTopDrift)
        }
    }

    private static func softWave(_ phase: Double) -> Double {
        0.5 + 0.5 * sin(phase * .pi * 2)
    }

    private static func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        let u = max(0, min(1, t))
        return a.mix(with: b, by: u)
    }
}

private extension Color {
    /// Cheap RGB mix — good enough for near-navy atmosphere stops.
    func mix(with other: Color, by t: Double) -> Color {
        let u = max(0, min(1, t))
        #if canImport(UIKit)
        let left = UIColor(self)
        let right = UIColor(other)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        left.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        right.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return Color(
            red: Double(lr + (rr - lr) * u),
            green: Double(lg + (rg - lg) * u),
            blue: Double(lb + (rb - lb) * u),
            opacity: Double(la + (ra - la) * u)
        )
        #else
        return u < 0.5 ? self : other
        #endif
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
