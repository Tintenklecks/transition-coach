import Foundation
import Observation

@MainActor
@Observable
final class RoutineSessionStore {
    private(set) var completedStepIDs: Set<UUID> = []

    private let defaults: UserDefaults
    private var storageKey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func prepare(for routineID: UUID, date: Date, calendar: Calendar = .current) {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let key = "routine-progress-\(routineID.uuidString)-\(dayComponents.year ?? 0)-\(dayComponents.month ?? 0)-\(dayComponents.day ?? 0)"
        guard storageKey != key else { return }

        storageKey = key
        let savedIDs = defaults.stringArray(forKey: key) ?? []
        completedStepIDs = Set(savedIDs.compactMap(UUID.init(uuidString:)))
    }

    func complete(_ stepID: UUID) {
        completedStepIDs.insert(stepID)
        save()
    }

    func undo(_ stepID: UUID) {
        completedStepIDs.remove(stepID)
        save()
    }

    func reset() {
        completedStepIDs = []
        save()
    }

    private func save() {
        guard let storageKey else { return }
        defaults.set(completedStepIDs.map(\.uuidString).sorted(), forKey: storageKey)
    }
}
