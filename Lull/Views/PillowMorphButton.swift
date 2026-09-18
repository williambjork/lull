import SwiftUI

/// Flat round CTA whose silhouette slowly softens like clay / pillow.
/// Same accent fill and centered label as a plain circle; only the edge warps.
struct PillowMorphButton: View {
    let title: String
    let tint: Color
    /// Visual diameter of the resting circle (morph expands slightly inside the frame).
    var size: CGFloat = 220
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Frame includes room so outward lobes are not clipped.
    private var viewportSize: CGFloat {
        size * CGFloat(1 + PillowMorph.maxOutset) + PillowMorph.viewportPad
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                morphingDisc
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.black.opacity(0.85))
            }
            .frame(width: viewportSize, height: viewportSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var morphingDisc: some View {
        if reduceMotion {
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { graphics, canvasSize in
                    let path = PillowMorph.path(
                        in: canvasSize,
                        restingDiameter: size,
                        at: timeline.date
                    )
                    graphics.fill(path, with: .color(tint))
                }
            }
        }
    }
}

// MARK: - Morph math

private enum PillowMorph {
    /// Sleepy loop length — within the 8–12s plan range.
    static let period: TimeInterval = 10

    /// Edge amplitudes as a fraction of radius (~0.02–0.035).
    static let a1: Double = 0.030
    static let a2: Double = 0.022

    /// Worst-case radial growth as a fraction of resting radius.
    static var maxOutset: Double { a1 + a2 }

    /// Extra points beyond the math max so antialiasing isn’t clipped.
    static let viewportPad: CGFloat = 4

    static let sampleCount = 72

    /// Continuous φ so `0.7·φ` never hitch at wrap (integer-harmonic lesson).
    static func phaseAngle(at date: Date) -> Double {
        2 * .pi * date.timeIntervalSinceReferenceDate / period
    }

    static func radiusFactor(theta: Double, phi: Double) -> Double {
        1
            + a1 * sin(2 * theta + phi)
            + a2 * sin(3 * theta - 0.7 * phi)
    }

    static func path(in size: CGSize, restingDiameter: CGFloat, at date: Date) -> Path {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseRadius = Double(restingDiameter / 2)
        let phi = phaseAngle(at: date)

        var path = Path()
        for i in 0..<sampleCount {
            let theta = 2 * .pi * Double(i) / Double(sampleCount)
            let r = baseRadius * radiusFactor(theta: theta, phi: phi)
            let point = CGPoint(
                x: center.x + CGFloat(r * cos(theta)),
                y: center.y + CGFloat(r * sin(theta))
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
