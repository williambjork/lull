import SwiftUI
import UIKit
import LullCore

/// Bottom-slot elapsed timer (with seconds). Hold, then drag vertically to scrub
/// the active sleep's start time in place (no sheet / DatePicker).
struct ScrubbableActiveSleepTime: View {
    @Environment(AppModel.self) private var model

    @Binding var draftStartedAt: Date?
    @Binding var isAdjusting: Bool

    @State private var baseStartedAt: Date?
    @State private var lastHapticMinute: Int?

    var body: some View {
        let startedAt = draftStartedAt ?? model.activeSleep?.startedAt ?? model.now
        let elapsedSeconds = max(0, Int(model.now.timeIntervalSince(startedAt)))

        VStack(alignment: .leading, spacing: 6) {
            Text("Asleep for")
                .font(.subheadline)
                .foregroundStyle(isAdjusting ? Theme.asleepAccent.opacity(0.9) : Theme.secondaryText)
            Text(DurationFormatting.timer(seconds: elapsedSeconds))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isAdjusting ? Theme.asleepAccent : .white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(scrubGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep timer")
        .accessibilityValue("\(DurationFormatting.timer(seconds: elapsedSeconds)), started \(model.formattedClock(startedAt))")
        .accessibilityHint("Touch and hold, then drag up or down to adjust the start time")
    }

    private var scrubGesture: some Gesture {
        LongPressGesture(minimumDuration: ScrubMapping.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    beginAdjustIfNeeded()
                case .second(true, let drag):
                    beginAdjustIfNeeded()
                    guard let drag, let base = baseStartedAt else { return }
                    applyDrag(drag.translation.height, from: base)
                default:
                    break
                }
            }
            .onEnded { _ in
                commitAdjust()
            }
    }

    private func beginAdjustIfNeeded() {
        guard !isAdjusting, let active = model.activeSleep else { return }
        isAdjusting = true
        baseStartedAt = active.startedAt
        draftStartedAt = active.startedAt
        lastHapticMinute = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applyDrag(_ translationHeight: CGFloat, from base: Date) {
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

    private func commitAdjust() {
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

// MARK: - Drag → minutes

enum ScrubMapping {
    static let holdDuration: Double = 0.35
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
