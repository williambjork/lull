import SwiftUI
import LullCore

/// Soft ambient mood for full-bleed backgrounds. Maps to runtime UI state
/// (awake vs active sleep), with night reserved for an active night sleep.
enum AtmosphereMood: Equatable, Sendable {
    /// Awake / idle — warm mauve drift toward navy.
    case idle
    /// Active sleep that isn’t classified as night (typically a nap).
    case asleep
    /// Active night sleep — cooler, deeper blues.
    case night

    /// Prefer `isSleeping` over provisional type thrash; night only when active + `.night`.
    static func from(isSleeping: Bool, sleepType: SleepType?) -> AtmosphereMood {
        guard isSleeping else { return .idle }
        return sleepType == .night ? .night : .asleep
    }
}

/// Calm atmosphere: slow gradient drift, one soft light blob, faint grain.
/// Prefer wrapping content in a `ZStack` with this as the back layer so the
/// full-bleed wash always gets a real size (`.background { }` can under-size
/// `GeometryReader` layers on some hosts).
struct AtmosphereBackground: View {
    var mood: AtmosphereMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Solid base so TabView / sheet chrome never shows through as flat black.
            Theme.background
            if reduceMotion {
                staticAtmosphere
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                    driftingAtmosphere(at: context.date)
                }
            }
            grainOverlay(seed: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    private var staticAtmosphere: some View {
        ZStack {
            Theme.atmosphereGradient(mood: mood, phase: 0)
            softBlob(offset: AtmosphereMotion.blobOffset(mood: mood, phase: 0), phase: 0)
        }
    }

    private func driftingAtmosphere(at date: Date) -> some View {
        let phase = AtmosphereMotion.phase(at: date, mood: mood)
        return ZStack {
            Theme.atmosphereGradient(mood: mood, phase: phase)
            softBlob(
                offset: AtmosphereMotion.blobOffset(mood: mood, phase: phase),
                phase: phase
            )
        }
    }

    private func softBlob(offset: CGSize, phase: Double) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * Theme.atmosphereBlobScale(mood: mood)
            Ellipse()
                .fill(Theme.atmosphereBlobColor(mood: mood, phase: phase))
                .frame(width: size * 1.35, height: size)
                .blur(radius: size * 0.42)
                .opacity(Theme.atmosphereBlobOpacity(mood: mood))
                .position(
                    x: geo.size.width * 0.5 + offset.width * geo.size.width * 0.18,
                    y: geo.size.height * 0.32 + offset.height * geo.size.height * 0.14
                )
        }
    }

    private func grainOverlay(seed: Int) -> some View {
        Canvas { context, size in
            let step: CGFloat = 3
            let opacity = Theme.atmosphereGrainOpacity
            guard opacity > 0 else { return }

            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let hash = AtmosphereMotion.grainHash(x: Int(x), y: Int(y), seed: seed)
                    if hash % 7 == 0 {
                        let brightness = 0.55 + Double(hash % 40) / 100
                        context.fill(
                            Path(CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                            with: .color(Color.white.opacity(opacity * brightness))
                        )
                    }
                    x += step
                }
                y += step
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

// MARK: - Motion helpers

private enum AtmosphereMotion {
    /// First-ship periods. Motion uses integer harmonics of this phase so wrap is seamless.
    static func phase(at date: Date, mood: AtmosphereMood) -> Double {
        let period: TimeInterval = switch mood {
        case .idle: 42
        case .asleep: 56
        case .night: 68
        }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    /// 1-periodic offset (sin/cos of `2π·phase` only). Original amp + tiny bump;
    /// replaces the old `sin(angle * 0.85)` hitch at cycle restart.
    static func blobOffset(mood: AtmosphereMood, phase: Double) -> CGSize {
        let angle = phase * .pi * 2
        let amp: Double = switch mood {
        case .idle: 1.08
        case .asleep: 0.80
        case .night: 0.58
        }
        return CGSize(
            width: cos(angle) * amp,
            height: sin(angle + 0.6) * amp * 0.9
        )
    }

    static func grainHash(x: Int, y: Int, seed: Int) -> Int {
        var h = x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return abs(h)
    }
}
