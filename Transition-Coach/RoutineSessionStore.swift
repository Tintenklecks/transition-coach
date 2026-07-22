import Foundation
import Observation

/// One day's result for the weekly bar on the timeline screen.
enum DayOutcome: Equatable, Sendable {
    case onTime
    case late
    case noRecord
}

@MainActor
@Observable
final class RoutineSessionStore {
    private(set) var completedStepIDs: Set<UUID> = []

    /// Minutes of buffer spent today via the "+N minutes" action.
    private(set) var spentBufferMinutes: Int = 0

    private let defaults: UserDefaults
    private var storageKey: String?
    private var bufferKey: String?
    private var routineID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func prepare(for routineID: UUID, date: Date, calendar: Calendar = .current) {
        let key = Self.progressKey(routineID: routineID, date: date, calendar: calendar)
        guard storageKey != key else { return }

        self.routineID = routineID
        storageKey = key
        let bufferKey = key + "-buffer"
        self.bufferKey = bufferKey

        let savedIDs = defaults.stringArray(forKey: key) ?? []
        completedStepIDs = Set(savedIDs.compactMap(UUID.init(uuidString:)))
        spentBufferMinutes = defaults.integer(forKey: bufferKey)
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
        spentBufferMinutes = 0
        if let bufferKey { defaults.removeObject(forKey: bufferKey) }
        save()
    }

    /// Clears today's progress for a specific routine — used by Reset All.
    ///
    /// If this routine is the one currently loaded in memory, in-memory state is
    /// also wiped so the view immediately exits the completed state.
    func resetToday(for routineID: UUID, date: Date = Date(), calendar: Calendar = .current) {
        let key = Self.progressKey(routineID: routineID, date: date, calendar: calendar)
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + "-buffer")
        if storageKey == key {
            completedStepIDs = []
            spentBufferMinutes = 0
            storageKey = nil
            bufferKey = nil
            self.routineID = nil
        }
    }

    /// Spends buffer for today only. Tomorrow starts from the routine's configured buffer again.
    func spendBuffer(_ minutes: Int, limit: Int) {
        guard let bufferKey else { return }
        spentBufferMinutes = min(limit, spentBufferMinutes + minutes)
        defaults.set(spentBufferMinutes, forKey: bufferKey)
    }

    private func save() {
        guard let storageKey else { return }
        defaults.set(completedStepIDs.map(\.uuidString).sorted(), forKey: storageKey)
    }

    // MARK: - Weekly record

    /// Records how the day went, once every step is done.
    ///
    /// Idempotent per day: the first recorded outcome stands, so re-opening the
    /// finished screen later in the day cannot flip a good morning into a late one.
    func recordOutcome(onTime: Bool, date: Date, calendar: Calendar = .current) {
        guard let routineID else { return }
        let key = Self.outcomeKey(routineID: routineID, date: date, calendar: calendar)
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(onTime, forKey: key)
    }

    /// Outcomes for the current working week, Monday first, oldest to newest.
    func weekOutcomes(containing date: Date, calendar: Calendar = .current) -> [DayOutcome] {
        guard let routineID else { return Array(repeating: .noRecord, count: 5) }
        var workCalendar = calendar
        workCalendar.firstWeekday = 2 // Monday

        guard let week = workCalendar.dateInterval(of: .weekOfYear, for: date) else {
            return Array(repeating: .noRecord, count: 5)
        }

        return (0..<5).map { offset in
            guard let day = workCalendar.date(byAdding: .day, value: offset, to: week.start) else {
                return DayOutcome.noRecord
            }
            let key = Self.outcomeKey(routineID: routineID, date: day, calendar: workCalendar)
            guard let onTime = defaults.object(forKey: key) as? Bool else { return DayOutcome.noRecord }
            return onTime ? .onTime : .late
        }
    }

    // MARK: - Keys

    private static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func progressKey(routineID: UUID, date: Date, calendar: Calendar) -> String {
        "routine-progress-\(routineID.uuidString)-\(dayStamp(date, calendar: calendar))"
    }

    private static func outcomeKey(routineID: UUID, date: Date, calendar: Calendar) -> String {
        "routine-outcome-\(routineID.uuidString)-\(dayStamp(date, calendar: calendar))"
    }
}
