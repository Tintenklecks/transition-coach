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
    /// Today's window only counts while the routine is still actionable — before
    /// its target, or past it if the user actually started tracking it, and never
    /// more than an hour past target. Otherwise the routine has moved on to its
    /// next non-skipped day, and it must be *displayed* on that day too.
    private func nextWindow(
        for routine: Routine,
        now: Date,
        calendar: Calendar
    ) -> (day: Date, start: Date) {
        let isSkippedToday = routine.skippedDates.contains(where: { calendar.isDateInToday($0) })
        if !isSkippedToday {
            let schedule = ScheduleCalculator.schedule(for: routine.plan, on: now)
            // Hard 1-hour cap: once more than 1 hour past target, always move to tomorrow.
            // Within the window, only treat as "today's" if we're before the target OR the
            // user actually started tracking it — so skipping an earlier routine never pulls
            // in a completely unrelated past-due routine.
            if now <= schedule.targetDate.addingTimeInterval(3600) {
                let hasStarted = sessionStore.hasProgress(for: routine.id, date: now)
                if now <= schedule.targetDate || hasStarted {
                    return (now, schedule.startDate)
                }
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
            .foregroundStyle(.white.opacity(0.35))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, RoutineStep.self], inMemory: true)
}
