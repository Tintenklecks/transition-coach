import Foundation
import Testing
@testable import Transition_Coach

struct Transition_CoachTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func scheduleIsCalculatedBackwardsFromTarget() throws {
        let target = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 8, minute: 45)))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18)))
        let plan = RoutinePlan(
            id: UUID(),
            name: "Arbeitsbeginn",
            targetTime: target,
            bufferMinutes: 5,
            steps: [
                RoutineStepDefinition(id: UUID(), title: "Bad", durationMinutes: 10, symbolName: "drop", requiresConfirmation: true),
                RoutineStepDefinition(id: UUID(), title: "Fahrt", durationMinutes: 20, symbolName: "car", requiresConfirmation: true)
            ]
        )

        let schedule = ScheduleCalculator.schedule(for: plan, on: day, calendar: calendar)

        #expect(calendar.component(.hour, from: schedule.startDate) == 8)
        #expect(calendar.component(.minute, from: schedule.startDate) == 10)
        #expect(calendar.component(.hour, from: schedule.steps[1].startDate) == 8)
        #expect(calendar.component(.minute, from: schedule.steps[1].startDate) == 20)
        #expect(calendar.component(.hour, from: schedule.plannedFinishDate) == 8)
        #expect(calendar.component(.minute, from: schedule.plannedFinishDate) == 40)
    }

    @Test func completedStepsAdvanceTheActiveStep() throws {
        let target = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9)))
        let firstID = UUID()
        let secondID = UUID()
        let plan = RoutinePlan(
            id: UUID(),
            name: "Ziel",
            targetTime: target,
            bufferMinutes: 0,
            steps: [
                RoutineStepDefinition(id: firstID, title: "Eins", durationMinutes: 5, symbolName: "1.circle", requiresConfirmation: true),
                RoutineStepDefinition(id: secondID, title: "Zwei", durationMinutes: 5, symbolName: "2.circle", requiresConfirmation: true)
            ]
        )

        let schedule = ScheduleCalculator.schedule(for: plan, on: target, calendar: calendar)

        #expect(schedule.activeStep(completedStepIDs: [])?.id == firstID)
        #expect(schedule.activeStep(completedStepIDs: [firstID])?.id == secondID)
        #expect(schedule.activeStep(completedStepIDs: [firstID, secondID]) == nil)
    }

    @Test func bufferAbsorbsSmallDelayBeforeTargetBecomesCritical() throws {
        let target = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9)))
        let stepID = UUID()
        let plan = RoutinePlan(
            id: UUID(),
            name: "Ziel",
            targetTime: target,
            bufferMinutes: 5,
            steps: [
                RoutineStepDefinition(id: stepID, title: "Fahrt", durationMinutes: 20, symbolName: "car", requiresConfirmation: true)
            ]
        )
        let schedule = ScheduleCalculator.schedule(for: plan, on: target, calendar: calendar)
        let twoMinutesLate = try #require(calendar.date(byAdding: .minute, value: 2, to: schedule.steps[0].endDate))
        let sixMinutesLate = try #require(calendar.date(byAdding: .minute, value: 6, to: schedule.steps[0].endDate))

        if case .overdue = schedule.urgency(at: twoMinutesLate, completedStepIDs: []) {
            // Expected: the configured buffer still protects the target.
        } else {
            Issue.record("A two-minute delay should still be absorbed by the buffer")
        }

        if case .critical = schedule.urgency(at: sixMinutesLate, completedStepIDs: []) {
            // Expected: the delay is now larger than the buffer.
        } else {
            Issue.record("A delay beyond the buffer should make the target critical")
        }
    }

    @Test func routineStepsCanBeReorderedAndKeepContiguousSortValues() {
        let first = RoutineStep(title: "First", durationMinutes: 1, sortOrder: 0)
        let second = RoutineStep(title: "Second", durationMinutes: 1, sortOrder: 1)
        let third = RoutineStep(title: "Third", durationMinutes: 1, sortOrder: 2)
        let routine = Routine(name: "Test", targetTime: Date(), steps: [first, second, third])

        routine.moveStep(from: third.id, to: first.id)

        #expect(routine.sortedSteps.map(\.id) == [third.id, first.id, second.id])
        #expect(routine.sortedSteps.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func routineIconIsIndependentFromFirstStepIcon() {
        let firstStep = RoutineStep(
            title: "Drive",
            durationMinutes: 10,
            sortOrder: 0,
            symbolName: "car.fill"
        )
        let routine = Routine(
            name: "Work",
            symbolName: "briefcase.fill",
            targetTime: Date(),
            steps: [firstStep]
        )
        let schedule = ScheduleCalculator.schedule(for: routine.plan, on: Date(), calendar: calendar)
        let snapshot = CoachSnapshot(schedule: schedule, day: Date(), completedStepIDs: [])

        #expect(routine.plan.symbolName == "briefcase.fill")
        #expect(routine.plan.steps.first?.symbolName == "car.fill")
        #expect(snapshot.routineSymbolName == "briefcase.fill")
        #expect(snapshot.steps.first?.symbolName == "car.fill")
    }

    @Test func routineWindowIsNeutralBeforeStartAndFinishedAfterTarget() throws {
        let target = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 18, hour: 9
        )))
        let stepID = UUID()
        let plan = RoutinePlan(
            id: UUID(),
            name: "Morning",
            targetTime: target,
            bufferMinutes: 5,
            steps: [
                RoutineStepDefinition(
                    id: stepID,
                    title: "Drive",
                    durationMinutes: 20,
                    symbolName: "car.fill",
                    requiresConfirmation: true
                )
            ]
        )
        let schedule = ScheduleCalculator.schedule(for: plan, on: target, calendar: calendar)
        let beforeStart = try #require(calendar.date(byAdding: .minute, value: -1, to: schedule.startDate))
        let duringRoutine = try #require(calendar.date(byAdding: .minute, value: 1, to: schedule.startDate))
        let afterTarget = try #require(calendar.date(byAdding: .second, value: 1, to: schedule.targetDate))

        #expect(schedule.windowPhase(at: beforeStart, completedStepIDs: []) == .upcoming)
        #expect(schedule.windowPhase(at: duringRoutine, completedStepIDs: []) == .active)
        #expect(schedule.windowPhase(at: duringRoutine, completedStepIDs: [stepID]) == .finished)
        #expect(schedule.windowPhase(at: afterTarget, completedStepIDs: []) == .finished)
    }
}
