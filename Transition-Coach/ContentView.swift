import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @State private var sessionStore = RoutineSessionStore()

    private var activeRoutine: Routine? {
        let now = Date()
        let calendar = Calendar.current
        let enabled = routines.filter(\.isEnabled)
        guard !enabled.isEmpty else { return nil }
        return enabled.min {
            nextWindowStart(for: $0, now: now, calendar: calendar)
            < nextWindowStart(for: $1, now: now, calendar: calendar)
        }
    }

    /// The date at which a routine's next relevant window begins.
    ///
    /// If the routine hasn't finished today (within 1 hour of its target) and
    /// isn't skipped, the window is today's scheduled start. Otherwise it falls
    /// back to the first step's start time on the next non-skipped day. Comparing
    /// this across routines picks whichever one the user should see next.
    private func nextWindowStart(for routine: Routine, now: Date, calendar: Calendar) -> Date {
        let isSkippedToday = routine.skippedDates.contains(where: { calendar.isDateInToday($0) })
        if !isSkippedToday {
            let schedule = ScheduleCalculator.schedule(for: routine.plan, on: now)
            if now <= schedule.targetDate.addingTimeInterval(3600) {
                return schedule.startDate
            }
        }
        let nextDay = routine.nextNonSkippedDate(after: now)
        return ScheduleCalculator.schedule(for: routine.plan, on: nextDay).startDate
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max.fill") {
                TodayView(routine: activeRoutine, sessionStore: sessionStore)
            }

            Tab("Routines", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    RoutineListView(sessionStore: sessionStore)
                }
            }
        }
        .tint(Signal.accent)
        .task {
            guard routines.isEmpty else { return }
            modelContext.insert(Routine.morningExample())
            try? modelContext.save()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, RoutineStep.self], inMemory: true)
}
