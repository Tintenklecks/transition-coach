import SwiftData
import SwiftUI

// MARK: - Routines list

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    let sessionStore: RoutineSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Routines")
                    .font(SignalFont.grotesk(26, .bold))
                    .displayTracking(26)
                    .foregroundStyle(Signal.textPrimary)

                Text("Each routine back-plans its steps from the time you need to be ready.")
                    .font(SignalFont.grotesk(14))
                    .foregroundStyle(Signal.textSecondary)
                    .padding(.top, 4)

                if routines.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    SignalCard {
                        ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                            NavigationLink {
                                RoutineEditorView(routine: routine)
                            } label: {
                                RoutineRow(routine: routine)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(routine.isEnabled ? "Pause routine" : "Resume routine") {
                                    routine.isEnabled.toggle()
                                    if routine.notificationsEnabled {
                                        Task { await NotificationScheduler.reschedule(routine) }
                                    }
                                }
                                Button("Delete", role: .destructive) { delete(routine) }
                            }

                            if index < routines.count - 1 {
                                SignalHairline()
                            }
                        }
                    }
                    .padding(.top, 22)
                }

                Button(action: addRoutine) {
                    Text("+ New routine")
                        .font(SignalFont.grotesk(15, .semibold))
                        .foregroundStyle(Signal.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                .foregroundStyle(Signal.inactive)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                if hasAnythingToReset {
                    Button(action: resetAll) {
                        HStack {
                            Text("Reset all")
                                .font(SignalFont.grotesk(15, .semibold))
                                .foregroundStyle(Signal.textSecondary)
                            Spacer()
                            Text("reactivate paused · clear skips")
                                .font(SignalFont.grotesk(12))
                                .foregroundStyle(Signal.textSecondary.opacity(0.6))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Signal.surface, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        // Clears the floating tab bar so the last control stays reachable.
        .contentMargins(.bottom, 72, for: .scrollContent)
        .background(Signal.background.ignoresSafeArea())
        .hidingNavigationBar()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No routines yet")
                .font(SignalFont.grotesk(19, .bold))
                .foregroundStyle(Signal.textPrimary)
            Text("Add one for the transition you keep losing time on.")
                .font(SignalFont.grotesk(14))
                .foregroundStyle(Signal.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func addRoutine() {
        let routine = Routine(
            name: "New routine",
            targetTime: Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date(),
            steps: [RoutineStep(title: "First step", durationMinutes: 5, sortOrder: 0, symbolName: "figure.walk")]
        )
        modelContext.insert(routine)
    }

    private var hasAnythingToReset: Bool {
        routines.contains { !$0.isEnabled || !$0.skippedDates.isEmpty }
    }

    private func resetAll() {
        let now = Date()
        for routine in routines {
            routine.isEnabled = true
            routine.skippedDates = []
            sessionStore.resetToday(for: routine.id, date: now)
            if routine.notificationsEnabled {
                Task { await NotificationScheduler.reschedule(routine) }
            }
        }
        try? modelContext.save()
    }

    private func delete(_ routine: Routine) {
        Task { await NotificationScheduler.disable(for: routine) }
        modelContext.delete(routine)
    }
}

private struct RoutineRow: View {
    let routine: Routine

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(routine.isEnabled ? Signal.background : Signal.textSecondary)
                .frame(width: 30, height: 30)
                .background(routine.isEnabled ? Signal.accent : Signal.hairline, in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(SignalFont.grotesk(16, .medium))
                    .foregroundStyle(Signal.textPrimary)
                HStack(spacing: 6) {
                    if !routine.isEnabled {
                        Text("Paused")
                            .font(SignalFont.grotesk(11, .semibold))
                            .foregroundStyle(Signal.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Signal.hairline, in: .capsule)
                    }
                    Text("\(routine.steps.count) steps")
                        .font(SignalFont.grotesk(13))
                        .foregroundStyle(Signal.textSecondary)
                }
            }

            Spacer(minLength: 8)

            Text(routine.targetTime.formatted(date: .omitted, time: .shortened))
                .font(SignalFont.mono(14, .semibold))
                .foregroundStyle(routine.isEnabled ? Signal.accent : Signal.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Signal.hairline, in: .capsule)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Signal.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

// MARK: - Routine editor (frame 5)

struct RoutineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var routine: Routine
    @State private var notificationError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Text("Goal")
                    .signalEyebrow()
                    .padding(.top, 22)

                goalCard
                    .padding(.top, 10)

                nudgeCard
                    .padding(.top, 24)

                Text("The coach nudges you at the start of every step, back-planned from your target time and step durations.")
                    .font(SignalFont.grotesk(13))
                    .foregroundStyle(Signal.textSecondary)
                    .lineSpacing(3)
                    .padding(.top, 10)

                HStack {
                    Text("Steps")
                        .signalEyebrow()
                    Spacer()
                    Text("\(routine.steps.count) total")
                        .font(SignalFont.grotesk(13, .semibold))
                        .foregroundStyle(Signal.accent)
                }
                .padding(.top, 26)

                stepsCard
                    .padding(.top, 10)

                Button(action: addStep) {
                    Text("+ Add step")
                        .font(SignalFont.grotesk(15, .semibold))
                        .foregroundStyle(Signal.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                .foregroundStyle(Signal.inactive)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        // Clears the floating tab bar so "Add step" stays reachable.
        .contentMargins(.bottom, 72, for: .scrollContent)
        .background(Signal.background.ignoresSafeArea())
        .hidingNavigationBar()
        .alert("Notifications are off", isPresented: $notificationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow notifications in Settings so the coach can nudge you at each step.")
        }
        .onDisappear {
            normalizeSortOrder()
            try? modelContext.save()
            Task { await NotificationScheduler.reschedule(routine) }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Signal.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Signal.surface, in: .circle)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            TextField("Routine name", text: $routine.name)
                .font(SignalFont.grotesk(19, .bold))
                .foregroundStyle(Signal.textPrimary)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)

            Spacer(minLength: 12)

            Button { dismiss() } label: {
                Text("Done")
                    .font(SignalFont.grotesk(14, .bold))
                    .foregroundStyle(Signal.background)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Signal.accent, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private var goalCard: some View {
        SignalCard {
            HStack {
                Text("Target time")
                    .font(SignalFont.grotesk(16, .medium))
                    .foregroundStyle(Signal.textPrimary)
                Spacer()
                DatePicker("", selection: $routine.targetTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .tint(Signal.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            SignalHairline()

            HStack {
                Text("Safety buffer")
                    .font(SignalFont.grotesk(16, .medium))
                    .foregroundStyle(Signal.textPrimary)
                Spacer()
                SignalStepper(
                    value: $routine.bufferMinutes,
                    range: 0...30,
                    unit: "min",
                    diameter: 30,
                    valueWidth: 44
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            SignalHairline()

            Toggle("Routine active", isOn: $routine.isEnabled)
                .toggleStyle(SignalToggleStyle())
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
    }

    private var nudgeCard: some View {
        SignalCard {
            Toggle("Transition nudges", isOn: notificationBinding)
                .toggleStyle(SignalToggleStyle())
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
    }

    private var stepsCard: some View {
        SignalCard {
            let steps = routine.sortedSteps
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                RoutineStepEditorRow(step: step) { deleteStep(step) }

                if index < steps.count - 1 {
                    SignalHairline()
                }
            }
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
            title: "New step",
            durationMinutes: 5,
            sortOrder: routine.steps.count,
            symbolName: "checkmark.circle"
        )
        routine.steps.append(step)
    }

    private func deleteStep(_ step: RoutineStep) {
        modelContext.delete(step)
        normalizeSortOrder()
    }

    private func normalizeSortOrder() {
        for (index, step) in routine.sortedSteps.enumerated() {
            step.sortOrder = index
        }
    }
}

private struct RoutineStepEditorRow: View {
    @Bindable var step: RoutineStep
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: step.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(Signal.textPrimary)
                .frame(width: 24)

            TextField("Step", text: $step.title)
                .font(SignalFont.grotesk(16, .medium))
                .foregroundStyle(Signal.textPrimary)
                .textFieldStyle(.plain)

            SignalStepper(
                value: $step.durationMinutes,
                range: 1...120,
                unit: "min",
                diameter: 26,
                valueWidth: 38
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contextMenu {
            Button("Delete step", role: .destructive, action: deleteAction)
        }
    }
}
