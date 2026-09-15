import Foundation
import Observation
import UIKit
import LullCore

/// Owns the service, the ticking clock, and the small amount of derived state
/// the screens read. All domain logic lives in `LullCore`.
@MainActor
@Observable
final class AppModel {

    private(set) var service: SleepService?
    private(set) var loadError: String?

    /// Advances every second so running timers read as live.
    private(set) var now = Date()

    // Derived values, refreshed on mutation and once a minute rather than on
    // every tick — recomputing medians 60 times a minute would be silly.
    private(set) var prediction: SleepPrediction?
    private(set) var totals: SleepTotals?
    private(set) var trends: [SleepTrendSignal] = []
    private(set) var sleepProfile: BabySleepProfile?

    /// Parent-chosen baby photo, or nil to use the bundled placeholder art.
    private(set) var babyAvatarImage: UIImage?
    private(set) var hasCustomBabyAvatar = false

    /// Drives the post-sleep summary sheet.
    var lastStopResult: SleepStopResult?
    var errorMessage: String?

    private let repository: any SleepRepository
    private var ticker: Task<Void, Never>?
    private var lastRefreshMinute: Date?

    init(repository: (any SleepRepository)? = nil) {
        if let repository {
            self.repository = repository
        } else {
            do {
                self.repository = try FileSleepRepository.inApplicationSupport()
            } catch {
                // Falling back to memory keeps the app usable; the parent is told.
                self.repository = InMemorySleepRepository()
                self.loadError = "Couldn't open local storage, so this session won't be saved."
            }
        }

        do {
            service = try SleepService.loadExisting(repository: self.repository)
        } catch {
            loadError = "Couldn't read saved sleep data."
        }
        reloadBabyAvatar()
        refreshDerived()
        startTicking()
    }

    var hasProfile: Bool { service != nil }
    var activeSleep: SleepEvent? { service?.activeSleep }
    var isSleeping: Bool { activeSleep != nil }

    var babyName: String {
        let name = service?.profile.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Your baby" : name
    }

    var timeZone: TimeZone { service?.profile.timezone ?? .current }

    var ages: BabyAges? { service?.ages(asOf: now) }

    var awakeMinutes: Int? { service?.awakeMinutes(asOf: now) }

    /// Elapsed minutes of the running timer.
    var activeElapsedMinutes: Int? { activeSleep?.elapsedMinutes(asOf: now) }

    // MARK: - Onboarding

    func createProfile(
        name: String,
        dateOfBirth: Date,
        wasPremature: Bool,
        gestationalAgeWeeks: Int?,
        correctedAgeEnabled: Bool
    ) {
        let profile = BabyProfile(
            name: name,
            dateOfBirth: dateOfBirth,
            wasPremature: wasPremature,
            gestationalAgeWeeks: wasPremature ? gestationalAgeWeeks : nil,
            correctedAgeEnabled: wasPremature && correctedAgeEnabled
        )
        do {
            service = try SleepService.create(profile: profile, repository: repository)
            now = Date()
            refreshDerived()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Timer

    func startSleep(at startedAt: Date? = nil, cues: [SleepCue] = [], location: SleepLocation? = nil) {
        perform { service in
            try service.startSleep(at: startedAt ?? Date(), location: location, cues: cues)
        }
    }

    func stopSleep() {
        perform { service in
            let result = try service.stopSleep(at: Date())
            self.lastStopResult = result
            if let prediction = result.prediction {
                try service.recordShownPrediction(prediction)
            }
        }
    }

    func adjustActiveStart(to date: Date) {
        perform { service in try service.adjustActiveStart(to: date) }
    }

    func cancelActiveSleep() {
        perform { service in try service.cancelActiveSleep() }
    }

    // MARK: - History

    func addPastSleep(
        startedAt: Date,
        endedAt: Date,
        type: SleepType?,
        location: SleepLocation?,
        method: SleepMethod?,
        cues: [SleepCue],
        contexts: [SleepContext],
        notes: String?
    ) {
        perform { service in
            try service.addCompletedSleep(
                startedAt: startedAt,
                endedAt: endedAt,
                type: type,
                location: location,
                method: method,
                cues: cues,
                contexts: contexts,
                notes: notes
            )
        }
    }

    func updateSleep(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        location: SleepLocation?,
        method: SleepMethod?,
        cues: [SleepCue],
        contexts: [SleepContext],
        notes: String?
    ) {
        perform { service in
            try service.updateSleep(
                id: id,
                startedAt: startedAt,
                endedAt: .some(endedAt),
                location: .some(location),
                method: .some(method),
                cues: cues,
                contexts: contexts,
                notes: .some(notes)
            )
        }
    }

    func setType(_ type: SleepType, for id: UUID) {
        perform { service in try service.setType(type, forEventId: id) }
    }

    func deleteSleep(id: UUID) {
        perform { service in try service.deleteSleep(id: id) }
    }

    func setDayUnusual(_ isUnusual: Bool, day: SleepDay, contexts: [SleepContext] = [.unusualDay]) {
        perform { service in
            if isUnusual {
                try service.markDay(day, contexts: contexts)
            } else {
                try service.clearDayFlag(day)
            }
        }
    }

    func setDayStartWake(_ date: Date) {
        perform { service in try service.setDayStartWake(date) }
    }

    func setDayStartHour(_ hour: Int) {
        perform { service in try service.setDayStartHour(hour) }
    }

    func updateProfile(_ transform: @escaping (inout BabyProfile) -> Void) {
        perform { service in try service.updateProfile(transform) }
    }

    func setBabyAvatar(_ image: UIImage) {
        do {
            try BabyAvatarStore.save(image)
            reloadBabyAvatar()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearBabyAvatar() {
        do {
            try BabyAvatarStore.delete()
            reloadBabyAvatar()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllData() {
        perform { service in
            try service.deleteAllData()
            try? BabyAvatarStore.delete()
            self.reloadBabyAvatar()
            self.service = nil
        }
    }

    // MARK: - Reads

    func summaries(days: Int = 14) -> [DailySleepSummary] {
        service?.recentSummaries(days: days, asOf: now) ?? []
    }

    func allSummaries() -> [DailySleepSummary] {
        service?.allSummaries() ?? []
    }

    func events(on day: SleepDay) -> [SleepEvent] {
        service?.events(on: day) ?? []
    }

    func cueStats() -> [SleepCueStat] {
        service?.cueStats() ?? []
    }

    var agePrior: AgeWakeWindowPrior? {
        guard let service else { return nil }
        return WakeWindowPriors.prior(forAgeMonths: service.ageMonths(asOf: now))
    }

    var today: SleepDay? { service?.calendar.day(for: now) }

    func isDayUnusual(_ day: SleepDay) -> Bool {
        service?.isDayUnusual(day) ?? false
    }

    func formattedClock(_ date: Date) -> String {
        TimeFormatting.clock(date, timeZone: timeZone)
    }

    func formattedRange(_ prediction: SleepPrediction) -> String {
        TimeFormatting.clockRange(
            from: prediction.earliestStartAt,
            to: prediction.latestStartAt,
            timeZone: timeZone
        )
    }

    func refreshDerived() {
        guard let service else {
            prediction = nil
            totals = nil
            trends = []
            sleepProfile = nil
            return
        }
        prediction = service.prediction(asOf: now)
        totals = service.totals(asOf: now)
        trends = service.trends(asOf: now)
        sleepProfile = service.sleepProfile(asOf: now)
        lastRefreshMinute = Calendar.current.dateInterval(of: .minute, for: now)?.start
    }

    /// Called when the app comes back to the foreground.
    func refreshAfterForeground() {
        now = Date()
        refreshDerived()
    }

    // MARK: - Internals

    private func reloadBabyAvatar() {
        babyAvatarImage = BabyAvatarStore.load()
        hasCustomBabyAvatar = BabyAvatarStore.hasCustomAvatar
    }

    private func perform(_ work: (SleepService) throws -> Void) {
        guard let service else { return }
        do {
            try work(service)
            now = Date()
            refreshDerived()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = Date()
                let minute = Calendar.current.dateInterval(of: .minute, for: self.now)?.start
                if minute != self.lastRefreshMinute {
                    self.refreshDerived()
                }
            }
        }
    }
}
