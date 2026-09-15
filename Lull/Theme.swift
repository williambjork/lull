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
    /// First-ship palette restored; only a tiny visibility nudge on wash / blob / grain.
    static let atmosphereIdleTop = Color(red: 0.13, green: 0.10, blue: 0.16)
    static let atmosphereIdleTopDrift = Color(red: 0.15, green: 0.11, blue: 0.18)
    static let atmosphereAsleepTop = Color(red: 0.06, green: 0.08, blue: 0.20)
    static let atmosphereAsleepTopDrift = Color(red: 0.07, green: 0.10, blue: 0.24)
    static let atmosphereNightTop = Color(red: 0.04, green: 0.05, blue: 0.14)
    static let atmosphereNightTopDrift = Color(red: 0.05, green: 0.06, blue: 0.18)

    /// Original 0.028 + tiny bump.
    static let atmosphereGrainOpacity: Double = 0.032

    static func atmosphereGradient(mood: AtmosphereMood, phase: Double) -> LinearGradient {
        let (a, b) = atmosphereTopPair(mood: mood)
        let t = softWave(phase)
        let top = blend(a, b, t: t)
        // Original used a.opacity(0.35) + t*0.25; nudged slightly for wash contrast.
        let bottom = blend(background, a.opacity(0.40), t: t * 0.28)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func atmosphereBlobColor(mood: AtmosphereMood, phase: Double) -> Color {
        let t = softWave(phase + 0.25)
        switch mood {
        case .idle:
            // Original 0.22 / 0.14 — tiny bump.
            return blend(awakeAccent.opacity(0.26), awakeAccent.opacity(0.16), t: t)
        case .asleep:
            return blend(asleepAccent.opacity(0.24), asleepAccent.opacity(0.14), t: t)
        case .night:
            return blend(
                Color(red: 0.35, green: 0.45, blue: 0.85).opacity(0.19),
                asleepAccent.opacity(0.12),
                t: t
            )
        }
    }

    static func atmosphereBlobOpacity(mood: AtmosphereMood) -> Double {
        // Original 0.55 / 0.50 / 0.42 — tiny bump.
        switch mood {
        case .idle: 0.60
        case .asleep: 0.54
        case .night: 0.46
        }
    }

    static func atmosphereBlobScale(mood: AtmosphereMood) -> CGFloat {
        switch mood {
        case .idle: 0.72
        case .asleep: 0.78
        case .night: 0.85
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
