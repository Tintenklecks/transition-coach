import Foundation

struct RoutineStepDefinition: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let durationMinutes: Int
    let symbolName: String
    let requiresConfirmation: Bool
}

struct RoutinePlan: Equatable, Sendable {
    let id: UUID
    let name: String
    let targetTime: Date
    let bufferMinutes: Int
    let steps: [RoutineStepDefinition]
}

struct ScheduledStep: Identifiable, Equatable, Sendable {
    let step: RoutineStepDefinition
    let startDate: Date
    let endDate: Date

    var id: UUID { step.id }
}

struct RoutineSchedule: Equatable, Sendable {
    let plan: RoutinePlan
    let targetDate: Date
    let steps: [ScheduledStep]

    var startDate: Date { steps.first?.startDate ?? targetDate }
    var plannedFinishDate: Date {
        Calendar.current.date(byAdding: .minute, value: -plan.bufferMinutes, to: targetDate) ?? targetDate
    }

    func activeStep(completedStepIDs: Set<UUID>) -> ScheduledStep? {
        steps.first { !completedStepIDs.contains($0.id) }
    }

    func urgency(at date: Date, completedStepIDs: Set<UUID>) -> RoutineUrgency {
        guard let activeStep = activeStep(completedStepIDs: completedStepIDs) else {
            return .completed
        }
        if date < activeStep.startDate { return .preparation }
        if date <= activeStep.endDate { return .transition }

        // A delay can consume the configured buffer before the target is truly at risk.
        let delaySeconds = date.timeIntervalSince(activeStep.endDate)
        return delaySeconds > Double(plan.bufferMinutes * 60) ? .critical : .overdue
    }
}

enum RoutineUrgency: Equatable, Sendable {
    case preparation
    case transition
    case overdue
    case critical
    case completed

    var title: String {
        switch self {
        case .preparation: "Gleich geht es los"
        case .transition: "Jetzt wechseln"
        case .overdue: "Zeit für den nächsten Schritt"
        case .critical: "Dein Ziel wird knapp"
        case .completed: "Routine geschafft"
        }
    }
}

enum ScheduleCalculator {
    static func schedule(
        for plan: RoutinePlan,
        on day: Date,
        calendar: Calendar = .current
    ) -> RoutineSchedule {
        let targetComponents = calendar.dateComponents([.hour, .minute], from: plan.targetTime)
        let dayStart = calendar.startOfDay(for: day)
        let targetDate = calendar.date(
            bySettingHour: targetComponents.hour ?? 0,
            minute: targetComponents.minute ?? 0,
            second: 0,
            of: dayStart
        ) ?? dayStart

        var cursor = calendar.date(
            byAdding: .minute,
            value: -plan.bufferMinutes,
            to: targetDate
        ) ?? targetDate
        var reversedSchedule: [ScheduledStep] = []

        for step in plan.steps.reversed() {
            let start = calendar.date(
                byAdding: .minute,
                value: -max(1, step.durationMinutes),
                to: cursor
            ) ?? cursor
            reversedSchedule.append(ScheduledStep(step: step, startDate: start, endDate: cursor))
            cursor = start
        }

        return RoutineSchedule(
            plan: plan,
            targetDate: targetDate,
            steps: reversedSchedule.reversed()
        )
    }
}
