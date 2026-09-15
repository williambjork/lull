import Foundation
import LullCore

/// Launch-argument helpers used by `scripts/capture-screenshots.sh`.
///
/// Recognized arguments:
/// - `-UIScreen <name>` — `onboarding`, `home`, `history`, `patterns`, or `settings`
/// - `-UIDemoSeed` — wipe local data and install a small demo baby + recent sleeps
enum ScreenshotCapture {
    enum Screen: String {
        case onboarding
        case home
        case history
        case patterns
        case settings
    }

    enum Tab: Hashable {
        case home, history, patterns, settings

        init?(screen: Screen) {
            switch screen {
            case .home: self = .home
            case .history: self = .history
            case .patterns: self = .patterns
            case .settings: self = .settings
            case .onboarding: return nil
            }
        }
    }

    static var requestedScreen: Screen? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-UIScreen"),
              args.index(after: index) < args.endIndex,
              let screen = Screen(rawValue: args[args.index(after: index)])
        else { return nil }
        return screen
    }

    static var shouldSeedDemoData: Bool {
        ProcessInfo.processInfo.arguments.contains("-UIDemoSeed")
    }

    static var forceOnboarding: Bool {
        requestedScreen == .onboarding
    }

    static var initialTab: Tab {
        guard let screen = requestedScreen, let tab = Tab(screen: screen) else {
            return .home
        }
        return tab
    }

    /// Replaces on-disk data with a predictable demo baby so History / Patterns
    /// are not empty during capture. Safe only when `-UIDemoSeed` is present.
    @MainActor
    static func seedDemoData(into model: AppModel) {
        guard shouldSeedDemoData else { return }

        model.deleteAllData()

        let calendar = Calendar.current
        let dob = calendar.date(byAdding: .month, value: -4, to: Date()) ?? Date()
        model.createProfile(
            name: "Astrid",
            dateOfBirth: dob,
            wasPremature: false,
            gestationalAgeWeeks: nil,
            correctedAgeEnabled: false
        )

        let now = Date()
        func stamp(_ daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        // Yesterday: two naps + night
        model.addPastSleep(
            startedAt: stamp(1, hour: 9, minute: 30),
            endedAt: stamp(1, hour: 10, minute: 45),
            type: .nap,
            location: .crib,
            method: .independent,
            cues: [.yawning],
            contexts: [],
            notes: nil
        )
        model.addPastSleep(
            startedAt: stamp(1, hour: 13, minute: 0),
            endedAt: stamp(1, hour: 14, minute: 20),
            type: .nap,
            location: .stroller,
            method: .other,
            cues: [.fussy],
            contexts: [],
            notes: nil
        )
        model.addPastSleep(
            startedAt: stamp(1, hour: 19, minute: 0),
            endedAt: stamp(0, hour: 6, minute: 30),
            type: .night,
            location: .crib,
            method: .feeding,
            cues: [],
            contexts: [],
            notes: nil
        )

        // Today: one completed morning nap so Home / History have content
        model.addPastSleep(
            startedAt: stamp(0, hour: 9, minute: 15),
            endedAt: stamp(0, hour: 10, minute: 25),
            type: .nap,
            location: .crib,
            method: .rocking,
            cues: [.eyeRubbing, .yawning],
            contexts: [],
            notes: nil
        )
    }
}
