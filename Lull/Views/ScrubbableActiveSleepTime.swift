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

    private var baseStartedAt: Date?
    private var lastHapticMinute: Int?

    func begin(model: AppModel) {
        guard !isAdjusting, let active = model.activeSleep else { return }
        isAdjusting = true
        baseStartedAt = active.startedAt
        draftStartedAt = active.startedAt
        lastHapticMinute = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func applyDrag(_ translationHeight: CGFloat, model: AppModel) {
        guard isAdjusting, let base = baseStartedAt else { return }
        let deltaMinutes = ScrubMapping.minuteDelta(translationHeight: translationHeight)
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
        let y = -translationHeight
        let sign: CGFloat = y >= 0 ? 1 : -1
        let distance = abs(y)
        let fine = min(distance, fineBandPoints) / pointsPerMinute
        let coarse = max(0, distance - fineBandPoints) / pointsPerFiveMinutes * 5
        return Int((sign * (fine + coarse)).rounded())
    }
}
