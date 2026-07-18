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
    var id: UUID = UUID()
    var title: String = ""
    var durationMinutes: Int = 5
    var sortOrder: Int = 0
    var symbolName: String = "checkmark.circle"
    var requiresConfirmation: Bool = true
    var createdAt: Date = Date()
    var routine: Routine?

    init(
        title: String,
        durationMinutes: Int,
        sortOrder: Int,
        symbolName: String,
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
            name: "Arbeitsbeginn",
            targetTime: targetTime,
            bufferMinutes: 5,
            steps: [
                RoutineStep(title: "Computer verlassen", durationMinutes: 2, sortOrder: 0, symbolName: "laptopcomputer"),
                RoutineStep(title: "Ins Bad gehen", durationMinutes: 10, sortOrder: 1, symbolName: "drop.fill"),
                RoutineStep(title: "Anziehen", durationMinutes: 8, sortOrder: 2, symbolName: "tshirt.fill"),
                RoutineStep(title: "Tasche mitnehmen", durationMinutes: 3, sortOrder: 3, symbolName: "bag.fill"),
                RoutineStep(title: "Schuhe anziehen", durationMinutes: 2, sortOrder: 4, symbolName: "shoe.fill"),
                RoutineStep(title: "Zur Arbeit fahren", durationMinutes: 20, sortOrder: 5, symbolName: "car.fill")
            ]
        )
    }
}
