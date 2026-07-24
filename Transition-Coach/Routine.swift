import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    var targetTime: Date = Date()
    var bufferMinutes: Int = 5
    var isEnabled: Bool = true
    var notificationsEnabled: Bool = false
    var skippedDates: [Date] = []
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \RoutineStep.routine)
    var steps: [RoutineStep] = []

    init(
        name: String,
        targetTime: Date,
        bufferMinutes: Int = 5,
        isEnabled: Bool = true,
        notificationsEnabled: Bool = false,
        steps: [RoutineStep] = []
    ) {
        self.name = name
        self.targetTime = targetTime
        self.bufferMinutes = bufferMinutes
        self.isEnabled = isEnabled
        self.notificationsEnabled = notificationsEnabled
        self.steps = steps
    }

    var sortedSteps: [RoutineStep] {
        steps.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    /// Moves a step to the position currently occupied by another step.
    /// Used by the editor's drag handle and kept here so every reorder leaves
    /// the persisted sort values contiguous.
    func moveStep(from sourceID: UUID, to destinationID: UUID) {
        var reordered = sortedSteps
        guard
            sourceID != destinationID,
            let sourceIndex = reordered.firstIndex(where: { $0.id == sourceID }),
            let destinationIndex = reordered.firstIndex(where: { $0.id == destinationID })
        else { return }

        let source = reordered.remove(at: sourceIndex)
        reordered.insert(source, at: destinationIndex)

        for (index, step) in reordered.enumerated() {
            step.sortOrder = index
        }
    }

    /// Next date on or after `date + 1 day` that hasn't been skipped.
    func nextNonSkippedDate(after date: Date, calendar: Calendar = .current) -> Date {
        var candidate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        while skippedDates.contains(where: { calendar.isDate($0, inSameDayAs: candidate) }) {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    /// Marks `date` as skipped and prunes dates that are already in the past.
    func skipDate(_ date: Date, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: date)
        guard !skippedDates.contains(where: { calendar.isDate($0, inSameDayAs: dayStart) }) else { return }
        skippedDates.append(dayStart)
        let today = calendar.startOfDay(for: Date())
        skippedDates = skippedDates.filter { $0 >= today }
    }

    var plan: RoutinePlan {
        RoutinePlan(
            id: id,
            name: name,
            targetTime: targetTime,
            bufferMinutes: bufferMinutes,
            steps: sortedSteps.map(\.definition)
        )
    }
}

@Model
final class RoutineStep {
    static let defaultSymbolName = "checkmark.circle"

    var id: UUID = UUID()
    var title: String = ""
    var durationMinutes: Int = 5
    var sortOrder: Int = 0
    var symbolName: String = RoutineStep.defaultSymbolName
    var requiresConfirmation: Bool = true
    var createdAt: Date = Date()
    var routine: Routine?

    init(
        title: String,
        durationMinutes: Int,
        sortOrder: Int,
        symbolName: String = RoutineStep.defaultSymbolName,
        requiresConfirmation: Bool = true
    ) {
        self.title = title
        self.durationMinutes = durationMinutes
        self.sortOrder = sortOrder
        self.symbolName = symbolName
        self.requiresConfirmation = requiresConfirmation
    }

    var definition: RoutineStepDefinition {
        RoutineStepDefinition(
            id: id,
            title: title,
            durationMinutes: durationMinutes,
            symbolName: symbolName,
            requiresConfirmation: requiresConfirmation
        )
    }
}

extension Routine {
    static func morningExample(calendar: Calendar = .current) -> Routine {
        let now = Date()
        let targetTime = calendar.date(
            bySettingHour: 8,
            minute: 45,
            second: 0,
            of: now
        ) ?? now

        return Routine(
            name: "Work start",
            targetTime: targetTime,
            bufferMinutes: 5,
            steps: [
                RoutineStep(title: "Leave the computer", durationMinutes: 2, sortOrder: 0, symbolName: "laptopcomputer"),
                RoutineStep(title: "Bathroom", durationMinutes: 15, sortOrder: 1, symbolName: "drop.fill"),
                RoutineStep(title: "Get dressed", durationMinutes: 8, sortOrder: 2, symbolName: "tshirt.fill"),
                RoutineStep(title: "Bag", durationMinutes: 3, sortOrder: 3, symbolName: "bag.fill"),
                RoutineStep(title: "Shoes", durationMinutes: 2, sortOrder: 4, symbolName: "shoe.fill"),
                RoutineStep(title: "Commute", durationMinutes: 20, sortOrder: 5, symbolName: "car.fill")
            ]
        )
    }
}
