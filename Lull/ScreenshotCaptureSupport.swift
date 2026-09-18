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

        let dob = Calendar.current.date(byAdding: .month, value: -4, to: Date()) ?? Date()
        model.createProfile(
            name: "Astrid",
            dateOfBirth: dob
        )

        let now = Date()
        func ago(hours: Double, minutes: Double = 0) -> Date {
            now.addingTimeInterval(-(hours * 3600 + minutes * 60))
        }

        // Recent history so Home / History / Patterns are populated at any time of day.
        model.addPastSleep(
            startedAt: ago(hours: 30),
            endedAt: ago(hours: 28, minutes: 45),
            type: .nap,
            location: .crib,
            method: .independent,
            notes: nil
        )
        model.addPastSleep(
            startedAt: ago(hours: 26),
            endedAt: ago(hours: 24, minutes: 40),
            type: .nap,
            location: .stroller,
            method: .other,
            notes: nil
        )
        model.addPastSleep(
            startedAt: ago(hours: 20),
            endedAt: ago(hours: 8),
            type: .night,
            location: .crib,
            method: .feeding,
            notes: nil
        )
        model.addPastSleep(
            startedAt: ago(hours: 3, minutes: 30),
            endedAt: ago(hours: 2, minutes: 10),
            type: .nap,
            location: .crib,
            method: .rocking,
            notes: nil
        )
    }
}
