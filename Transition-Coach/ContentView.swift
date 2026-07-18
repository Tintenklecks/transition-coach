import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @State private var sessionStore = RoutineSessionStore()

    private var activeRoutine: Routine? {
        routines.first(where: \.isEnabled) ?? routines.first
    }

    var body: some View {
        TabView {
            Tab("Heute", systemImage: "sun.max.fill") {
                NavigationStack {
                    TodayView(routine: activeRoutine, sessionStore: sessionStore)
                }
            }

            Tab("Routinen", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    RoutineListView()
                }
            }
        }
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
