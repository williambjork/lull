import SwiftUI
import UIKit
import LullCore

/// Hold, then drag vertically to scrub the active sleep's start time in place
/// (no sheet / DatePicker). Uses UIKit long-press so the recognizer keeps
/// tracking after the hold — SwiftUI `LongPress.sequenced(before: Drag)` often
/// never delivers the drag on device.
struct ActiveStartScrubOverlay: UIViewRepresentable {
    var holdDuration: Double = ScrubMapping.holdDuration
    var onBegan: () -> Void
    var onChanged: (_ translationHeight: CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = PassThroughView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        press.minimumPressDuration = holdDuration
        // Allow a full vertical scrub without cancelling the hold.
        press.allowableMovement = 10_000
        press.cancelsTouchesInView = false
        view.addGestureRecognizer(press)
        context.coordinator.recognizer = press
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.recognizer?.minimumPressDuration = holdDuration
    }

    final class Coordinator: NSObject {
        var onBegan: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: () -> Void
        weak var recognizer: UILongPressGestureRecognizer?
        private var originY: CGFloat?

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handle(_ gr: UILongPressGestureRecognizer) {
            let y = gr.location(in: gr.view).y
            switch gr.state {
            case .began:
                originY = y
                onBegan()
            case .changed:
                guard let originY else { return }
                onChanged(y - originY)
            case .ended, .cancelled, .failed:
                originY = nil
                onEnded()
            default:
                break
            }
        }
    }
}

/// Transparent hit target that still receives touches for the overlay recognizer.
private final class PassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        bounds.contains(point) ? self : nil
    }
}

// MARK: - Shared scrub session (one instance for Started + Asleep for)

@MainActor
@Observable
final class ActiveStartScrubSession {
    var draftStartedAt: Date?
    var isAdjusting = false
    /// Continuous minute delta from the hold origin (for wheel scroll between snaps).
    var exactMinuteDelta: Double = 0

    private var baseStartedAt: Date?
    private var lastHapticMinute: Int?

    /// Fractional remainder after the snapped minute (−0.5…0.5) for smooth wheel offset.
    var wheelFractionalOffset: Double {
        exactMinuteDelta - Double(Int(exactMinuteDelta.rounded()))
    }

    func begin(model: AppModel) {
        guard !isAdjusting, let active = model.activeSleep else { return }
        isAdjusting = true
        baseStartedAt = active.startedAt
        draftStartedAt = active.startedAt
        exactMinuteDelta = 0
        lastHapticMinute = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func applyDrag(_ translationHeight: CGFloat, model: AppModel) {
        guard isAdjusting, let base = baseStartedAt else { return }
        let exact = ScrubMapping.exactMinuteDelta(translationHeight: translationHeight)
        exactMinuteDelta = exact
        let deltaMinutes = Int(exact.rounded())
        let proposed = base.addingTimeInterval(TimeInterval(-deltaMinutes * 60))
        let clamped = min(proposed, model.now)
        let earliest = model.now.addingTimeInterval(-ScrubMapping.maxLookback)
        draftStartedAt = max(clamped, earliest)

        if lastHapticMinute != deltaMinutes {
            lastHapticMinute = deltaMinutes
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func commit(model: AppModel) {
        defer {
            isAdjusting = false
            baseStartedAt = nil
            lastHapticMinute = nil
            draftStartedAt = nil
            exactMinuteDelta = 0
        }
        guard let draft = draftStartedAt,
              let active = model.activeSleep,
              abs(draft.timeIntervalSince(active.startedAt)) >= 60
        else { return }
        model.adjustActiveStart(to: draft)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

extension View {
    /// Full-bleed hold→scrub→commit overlay. Safe to apply on multiple sibling
    /// time labels that share one `ActiveStartScrubSession`.
    func activeStartScrub(session: ActiveStartScrubSession, model: AppModel) -> some View {
        self
            .contentShape(Rectangle())
            .overlay {
                ActiveStartScrubOverlay(
                    onBegan: { session.begin(model: model) },
                    onChanged: { session.applyDrag($0, model: model) },
                    onEnded: { session.commit(model: model) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
    }
}

// MARK: - Ghost clock wheel (first hold-scrub look)

/// In-place clock column: crisp center time, faded ±2 neighbors above/below,
/// soft gradient mask at the edges. Driven by UIKit hold-drag minute scrub.
struct StartTimeScrubWheel: View {
    let center: Date
    /// Continuous residual after snap (−0.5…0.5); positive → column shifts down
    /// (earlier times from above move toward center).
    var fractionalOffset: Double = 0
    var format: (Date) -> String

    private let neighborCount = 2
    private let rowHeight: CGFloat = 40

    var body: some View {
        let rows = (-neighborCount...neighborCount).map { $0 }

        ZStack {
            ForEach(rows, id: \.self) { offset in
                let date = center.addingTimeInterval(TimeInterval(-offset * 60))
                let distance = abs(offset)
                Text(format(date))
                    .font(.system(
                        size: distance == 0 ? 40 : 32,
                        weight: distance == 0 ? .semibold : .regular,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(color(for: distance))
                    .opacity(opacity(for: distance))
                    .scaleEffect(distance == 0 ? 1 : 0.92)
                    .frame(height: rowHeight)
                    // Earlier (positive offset) sits above; later below.
                    // fractionalOffset shifts the column during inter-minute drag.
                    .offset(y: CGFloat(-offset) * rowHeight + CGFloat(fractionalOffset) * rowHeight)
                    .zIndex(distance == 0 ? 1 : 0)
            }
        }
        .frame(height: rowHeight * CGFloat(neighborCount * 2 + 1))
        .frame(maxWidth: .infinity)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.14),
                    .init(color: .black, location: 0.32),
                    .init(color: .black, location: 0.68),
                    .init(color: .black.opacity(0.55), location: 0.86),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    private func opacity(for distance: Int) -> Double {
        switch distance {
        case 0: 1
        case 1: 0.38
        default: 0.16
        }
    }

    private func color(for distance: Int) -> Color {
        distance == 0 ? Theme.asleepAccent : Color.white.opacity(0.85)
    }
}

/// Bottom-slot elapsed timer (with seconds). Hold + vertical drag scrubs start.
struct ScrubbableActiveSleepTime: View {
    @Environment(AppModel.self) private var model
    var session: ActiveStartScrubSession

    var body: some View {
        let startedAt = session.draftStartedAt ?? model.activeSleep?.startedAt ?? model.now
        let elapsedSeconds = max(0, Int(model.now.timeIntervalSince(startedAt)))

        VStack(alignment: .leading, spacing: 6) {
            Text("Asleep for")
                .font(.subheadline)
                .foregroundStyle(session.isAdjusting ? Theme.asleepAccent.opacity(0.9) : Theme.secondaryText)
            Text(DurationFormatting.timer(seconds: elapsedSeconds))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(session.isAdjusting ? Theme.asleepAccent : .white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .activeStartScrub(session: session, model: model)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep timer")
        .accessibilityValue("\(DurationFormatting.timer(seconds: elapsedSeconds)), started \(model.formattedClock(startedAt))")
        .accessibilityHint("Touch and hold, then drag up or down to adjust the start time")
    }
}

// MARK: - Drag → minutes

enum ScrubMapping {
    static let holdDuration: Double = 0.28
    /// Cap how far back a scrub can push the start.
    static let maxLookback: TimeInterval = 18 * 3600

    /// Fine band: 12 pt = 1 minute (first ±80 pt of travel).
    static let fineBandPoints: CGFloat = 80
    static let pointsPerMinute: CGFloat = 12
    /// Coarse band beyond that: 8 pt = 5 minutes (hours without a long drag).
    static let pointsPerFiveMinutes: CGFloat = 8

    /// Drag **up** (negative height) → earlier start / longer elapsed.
    /// Drag **down** → later start / shorter elapsed.
    static func minuteDelta(translationHeight: CGFloat) -> Int {
        Int(exactMinuteDelta(translationHeight: translationHeight).rounded())
    }

    /// Continuous minute delta for wheel scroll between snapped values.
    static func exactMinuteDelta(translationHeight: CGFloat) -> Double {
        let y = -translationHeight
        let sign: Double = y >= 0 ? 1 : -1
        let distance = abs(Double(y))
        let fine = min(distance, Double(fineBandPoints)) / Double(pointsPerMinute)
        let coarse = max(0, distance - Double(fineBandPoints)) / Double(pointsPerFiveMinutes) * 5
        return sign * (fine + coarse)
    }
}
