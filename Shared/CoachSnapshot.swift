import Foundation

/// A fully resolved routine plus its progress, flattened for transport.
///
/// The watch never plans anything: it receives absolute start/end dates from the
/// phone and only compares them against the clock. Editing routines, skipping
/// days and every other setting stays on iPhone/iPad.
struct CoachSnapshot: Codable, Equatable, Sendable {
    struct Step: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let durationMinutes: Int
        let symbolName: String?
        let start: Date
        let end: Date
        let isCompleted: Bool
    }

    let routineID: UUID
    let routineName: String
    /// The day this schedule was planned for — today, or the routine's next run.
    let day: Date
    let targetDate: Date
    let bufferMinutes: Int
    let steps: [Step]

    /// The clock is only meaningful for a while after the target. Past this the
    /// watch is holding a stale plan and says so instead of turning red.
    var expiresAt: Date {
        targetDate.addingTimeInterval(3600)
    }

    var completedCount: Int {
        steps.filter(\.isCompleted).count
    }

    var activeStep: Step? {
        steps.first { !$0.isCompleted }
    }

    /// Same four-state rule the phone uses, evaluated against the snapshot's
    /// absolute dates.
    func urgency(at date: Date) -> RoutineUrgency {
        guard let activeStep else { return .completed }
        if date < activeStep.start { return .preparation }
        if date <= activeStep.end { return .transition }
        let delay = date.timeIntervalSince(activeStep.end)
        return delay > Double(bufferMinutes * 60) ? .critical : .overdue
    }
}

enum SignalClock {
    /// M:SS, promoting to H:MM:SS past the hour so a long overrun never renders
    /// as an unreadable minute count like "828:19".
    static func text(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        guard hours > 0 else {
            return String(format: "%d:%02d", minutes, seconds % 60)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
    }
}

extension CoachSnapshot {
    /// Builds the snapshot the watch mirrors from the phone's live schedule.
    init(schedule: RoutineSchedule, day: Date, completedStepIDs: Set<UUID>) {
        self.init(
            routineID: schedule.plan.id,
            routineName: schedule.plan.name,
            day: day,
            targetDate: schedule.targetDate,
            bufferMinutes: schedule.plan.bufferMinutes,
            steps: schedule.steps.map { item in
                Step(
                    id: item.id,
                    title: item.step.title,
                    durationMinutes: item.step.durationMinutes,
                    symbolName: item.step.symbolName,
                    start: item.startDate,
                    end: item.endDate,
                    isCompleted: completedStepIDs.contains(item.id)
                )
            }
        )
    }
}
