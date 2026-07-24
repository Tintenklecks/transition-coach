import SwiftData
import SwiftUI

/// The routine the Today tab should show, plus the calendar day whose schedule
/// applies to it. The day matters: a routine can be selected because its *next*
/// window is tomorrow, and rendering it against today would show a phantom
/// "hours overdue" state for a morning that is long past.
struct ActiveRoutineSelection: Equatable {
    let routine: Routine
    let day: Date
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @State private var sessionStore = RoutineSessionStore()

    private var activeSelection: ActiveRoutineSelection? {
        // Establish observation so completing the final step immediately causes
        // the next routine to be selected.
        _ = sessionStore.completedStepIDs

        let now = Date()
        let calendar = Calendar.current
        let windows = routines.filter(\.isEnabled).map { routine in
            (routine: routine, window: nextWindow(for: routine, now: now, calendar: calendar))
        }
        guard let best = windows.min(by: { $0.window.start < $1.window.start }) else { return nil }
        return ActiveRoutineSelection(routine: best.routine, day: best.window.day)
    }

    /// The next relevant window for a routine: which day it runs on, and when its
    /// first step starts on that day.
    ///
    /// Today's window only counts until it is complete or its target has passed.
    /// Outside that compact window the Today tab should select the genuinely next
    /// routine and render its calm, neutral waiting state.
    private func nextWindow(
        for routine: Routine,
        now: Date,
        calendar: Calendar
    ) -> (day: Date, start: Date) {
        let isSkippedToday = routine.skippedDates.contains(where: { calendar.isDateInToday($0) })
        if !isSkippedToday {
            let schedule = ScheduleCalculator.schedule(for: routine.plan, on: now)
            let completedIDs = sessionStore.completedStepIDs(
                for: routine.id,
                date: now,
                calendar: calendar
            )
            if schedule.windowPhase(at: now, completedStepIDs: completedIDs) != .finished {
                return (now, schedule.startDate)
            }
        }
        let nextDay = routine.nextNonSkippedDate(after: now)
        return (nextDay, ScheduleCalculator.schedule(for: routine.plan, on: nextDay).startDate)
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max.fill") {
                TodayView(selection: activeSelection, sessionStore: sessionStore)
            }

            Tab("Routines", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    RoutineListView(sessionStore: sessionStore)
                }
            }
        }
        .tint(Signal.accent)
        .overlay(alignment: .bottomTrailing) {
            VersionBadge()
                .padding(.trailing, 12)
                .padding(.bottom, 30)
        }
        .task {
            guard routines.isEmpty else { return }
            modelContext.insert(Routine.morningExample())
            try? modelContext.save()
        }
    }
}

/// Tiny build stamp beside the tab bar, so any screenshot says which build it
/// came from.
private struct VersionBadge: View {
    private var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary.opacity(0.45))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, RoutineStep.self], inMemory: true)
}
