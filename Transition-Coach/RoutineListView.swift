import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.createdAt) private var routines: [Routine]

    var body: some View {
        List {
            ForEach(routines) { routine in
                NavigationLink {
                    RoutineEditorView(routine: routine)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: routine.isEnabled ? "sunrise.fill" : "sunrise")
                            .foregroundStyle(routine.isEnabled ? .orange : .secondary)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(routine.name)
                                .font(.headline)
                            Text("Ziel \(routine.targetTime.formatted(date: .omitted, time: .shortened)) · \(routine.steps.count) Schritte")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Routinen")
        .overlay {
            if routines.isEmpty {
                ContentUnavailableView("Keine Routinen", systemImage: "list.bullet.rectangle")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addRoutine) {
                    Label("Routine hinzufügen", systemImage: "plus")
                }
            }
        }
    }

    private func addRoutine() {
        let routine = Routine(
            name: "Neue Routine",
            targetTime: Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date(),
            steps: [RoutineStep(title: "Erster Schritt", durationMinutes: 5, sortOrder: 0, symbolName: "figure.walk")]
        )
        modelContext.insert(routine)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let routine = routines[index]
            Task { await NotificationScheduler.disable(for: routine) }
            modelContext.delete(routine)
        }
    }
}

struct RoutineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var routine: Routine
    @State private var notificationError = false

    var body: some View {
        Form {
            Section("Ziel") {
                TextField("Name", text: $routine.name)
                DatePicker("Zielzeit", selection: $routine.targetTime, displayedComponents: .hourAndMinute)
                Stepper("Sicherheitspuffer: \(routine.bufferMinutes) Min.", value: $routine.bufferMinutes, in: 0...30)
                Toggle("Routine aktiv", isOn: $routine.isEnabled)
            }

            Section {
                Toggle("Übergangs-Hinweise", isOn: notificationBinding)
            } footer: {
                Text("Der Coach erinnert täglich zum Start jedes Schritts. Die Zeiten werden aus Zielzeit, Puffer und Schrittdauern berechnet.")
            }

            Section("Schritte") {
                ForEach(routine.sortedSteps) { step in
                    RoutineStepEditorRow(step: step)
                }
                .onDelete(perform: deleteSteps)
                .onMove(perform: moveSteps)

                Button(action: addStep) {
                    Label("Schritt hinzufügen", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle(routine.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
#endif
        .alert("Hinweise nicht aktiviert", isPresented: $notificationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte erlaube Mitteilungen in den Systemeinstellungen, damit der Coach dich erinnern kann.")
        }
        .onDisappear {
            normalizeSortOrder()
            try? modelContext.save()
            Task { await NotificationScheduler.reschedule(routine) }
        }
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { routine.notificationsEnabled },
            set: { enabled in
                if enabled {
                    Task {
                        let granted = await NotificationScheduler.enable(for: routine)
                        notificationError = !granted
                    }
                } else {
                    Task { await NotificationScheduler.disable(for: routine) }
                }
            }
        )
    }

    private func addStep() {
        let step = RoutineStep(
            title: "Neuer Schritt",
            durationMinutes: 5,
            sortOrder: routine.steps.count,
            symbolName: "checkmark.circle"
        )
        routine.steps.append(step)
    }

    private func deleteSteps(at offsets: IndexSet) {
        let sorted = routine.sortedSteps
        for index in offsets {
            modelContext.delete(sorted[index])
        }
        normalizeSortOrder()
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        var sorted = routine.sortedSteps
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, step) in sorted.enumerated() {
            step.sortOrder = index
        }
    }

    private func normalizeSortOrder() {
        for (index, step) in routine.sortedSteps.enumerated() {
            step.sortOrder = index
        }
    }
}

private struct RoutineStepEditorRow: View {
    @Bindable var step: RoutineStep

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step.symbolName)
                .foregroundStyle(.orange)
                .frame(width: 28)
            TextField("Schritt", text: $step.title)
            Stepper("\(step.durationMinutes) Min.", value: $step.durationMinutes, in: 1...120)
                .fixedSize()
        }
    }
}
