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

/// Calm atmosphere: slow gradient drift, one soft light blob, floating motes, faint grain.
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
                grainOverlay(seed: 0)
                // Upward-flow motes are motion — hide when Reduce Motion is on.
            } else {
                // One TimelineView: atmosphere + motes (fixed pool, single Canvas).
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    ZStack {
                        driftingAtmosphere(at: context.date)
                        grainOverlay(seed: 0)
                        moteField(at: context.date)
                    }
                }
            }
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

    /// Soft fairy-forest motes: fixed pool, bottom → top recycle, one Canvas.
    private func moteField(at date: Date) -> some View {
        Canvas { context, size in
            let t = date.timeIntervalSinceReferenceDate
            for slot in AtmosphereMotes.pool {
                let point = AtmosphereMotes.position(slot, time: t, in: size)
                let r = slot.radius
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(AtmosphereMotes.color(slot, mood: mood))
                )
            }
        }
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

// MARK: - Floating motes (fixed pool, upward flow)

/// Fixed-size particle pool. Positions are pure functions of time — exiting the
/// top wraps to the bottom (recycle) with no allocations or growing arrays.
private enum AtmosphereMotes {
    /// Soft count — quieter than the visibility-debug 56.
    static let poolSize = 28

    struct Slot: Sendable {
        let index: Int
        /// Horizontal rest (0…1).
        let x: Double
        /// Screen-heights per second (slow rise).
        let speed: Double
        /// Phase offset in [0, 1) along the vertical loop.
        let phase: Double
        let radius: CGFloat
        let opacity: Double
        let swayAmp: CGFloat
        let swayPeriod: TimeInterval
        let swayPhase: Double
    }

    static let pool: [Slot] = (0..<poolSize).map(makeSlot)

    private static func makeSlot(_ index: Int) -> Slot {
        let h = AtmosphereMotion.grainHash(x: index * 17, y: index * 91, seed: 4_201)
        let h2 = AtmosphereMotion.grainHash(x: index * 3, y: index * 51, seed: 9_001)
        let x = Double(h % 1000) / 1000
        // Full-screen rise in ~28–55s.
        let riseSeconds = 28.0 + Double(h % 28)
        let speed = 1.0 / riseSeconds
        let phase = Double(h2 % 1000) / 1000
        let sizeBucket = h % 10
        let radius: CGFloat = switch sizeBucket {
        case 0, 1, 2: 0.9
        case 3, 4, 5: 1.4
        case 6, 7: 2.0
        case 8: 2.5
        default: 3.0
        }
        // Softer than the visibility bump (~0.22–0.42).
        let opacity = 0.11 + Double(h % 10) / 100
        let swayAmp = 4 + CGFloat(h % 8)
        let swayPeriod = 9.0 + Double(h2 % 11)
        return Slot(
            index: index,
            x: x,
            speed: speed,
            phase: phase,
            radius: radius,
            opacity: opacity,
            swayAmp: swayAmp,
            swayPeriod: swayPeriod,
            swayPhase: Double(h % 628) / 100
        )
    }

    /// Progress 0 = just entered at bottom; 1 = leaving top — then wraps (recycle).
    static func position(_ slot: Slot, time t: TimeInterval, in size: CGSize) -> CGPoint {
        let travel = size.height + slot.radius * 2
        var progress = slot.phase + t * slot.speed
        progress -= progress.rounded(.down) // fract → [0, 1)
        let y = size.height + slot.radius - CGFloat(progress) * travel
        let sway = sin(t * 2 * .pi / slot.swayPeriod + slot.swayPhase) * slot.swayAmp
        let x = CGFloat(slot.x) * size.width + sway
        return CGPoint(x: x, y: y)
    }

    static func color(_ slot: Slot, mood: AtmosphereMood) -> Color {
        switch mood {
        case .idle:
            Color(red: 1.0, green: 0.97, blue: 0.90).opacity(slot.opacity)
        case .asleep:
            Color(red: 0.88, green: 0.92, blue: 1.0).opacity(slot.opacity * 0.92)
        case .night:
            Color(red: 0.78, green: 0.85, blue: 1.0).opacity(slot.opacity * 0.80)
        }
    }
}
