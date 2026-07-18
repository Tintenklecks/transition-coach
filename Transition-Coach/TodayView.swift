import SwiftUI

struct TodayView: View {
    let routine: Routine?
    @Bindable var sessionStore: RoutineSessionStore

    var body: some View {
        Group {
            if let routine {
                RoutineTodayContent(routine: routine, sessionStore: sessionStore)
            } else {
                ContentUnavailableView(
                    "Noch keine Routine",
                    systemImage: "sunrise.fill",
                    description: Text("Lege deine erste Routine an, damit der Coach dich durch den Morgen begleiten kann.")
                )
            }
        }
        .navigationTitle("Heute")
    }
}

private struct RoutineTodayContent: View {
    let routine: Routine
    @Bindable var sessionStore: RoutineSessionStore
    @State private var isChangingNotifications = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let schedule = ScheduleCalculator.schedule(for: routine.plan, on: context.date)
            let completedIDs = sessionStore.completedStepIDs
            let activeStep = schedule.activeStep(completedStepIDs: completedIDs)
            let urgency = schedule.urgency(at: context.date, completedStepIDs: completedIDs)

            ScrollView {
                VStack(spacing: 18) {
                    header(schedule: schedule)
                    CoachCard(
                        schedule: schedule,
                        activeStep: activeStep,
                        urgency: urgency,
                        now: context.date,
                        completedCount: completedIDs.count
                    ) {
                        if let activeStep {
                            withAnimation(.snappy) {
                                sessionStore.complete(activeStep.id)
                            }
                        }
                    }

                    if !routine.notificationsEnabled {
                        notificationsCard
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Dein Weg zum Ziel")
                                .font(.headline)
                            Spacer()
                            if !completedIDs.isEmpty {
                                Button("Zurücksetzen") {
                                    withAnimation { sessionStore.reset() }
                                }
                                .font(.subheadline)
                            }
                        }

                        ForEach(schedule.steps) { item in
                            TimelineStepRow(
                                item: item,
                                isActive: item.id == activeStep?.id,
                                isCompleted: completedIDs.contains(item.id)
                            ) {
                                withAnimation(.snappy) {
                                    if completedIDs.contains(item.id) {
                                        sessionStore.undo(item.id)
                                    } else {
                                        sessionStore.complete(item.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial, in: .rect(cornerRadius: 22))
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color.secondary.opacity(0.07))
            .task(id: routine.id) {
                sessionStore.prepare(for: routine.id, date: context.date)
            }
        }
    }

    private func header(schedule: RoutineSchedule) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Guten Morgen")
                    .font(.title.bold())
                Text(routine.name)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(schedule.targetDate, format: .dateTime.hour().minute())
                    .font(.title2.bold().monospacedDigit())
                Text("Zielzeit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notificationsCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(.blue.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text("Übergänge nicht verpassen")
                    .font(.headline)
                Text("Erhalte zu jedem Schritt einen Hinweis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Aktivieren") {
                isChangingNotifications = true
                Task {
                    _ = await NotificationScheduler.enable(for: routine)
                    isChangingNotifications = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(isChangingNotifications)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
    }
}

private struct CoachCard: View {
    let schedule: RoutineSchedule
    let activeStep: ScheduledStep?
    let urgency: RoutineUrgency
    let now: Date
    let completedCount: Int
    let completeAction: () -> Void

    private var color: Color {
        switch urgency {
        case .preparation: .blue
        case .transition: .yellow
        case .overdue: .orange
        case .critical: .red
        case .completed: .green
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label(urgency.title, systemImage: urgency == .completed ? "checkmark.seal.fill" : "circle.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(min(completedCount, schedule.steps.count))/\(schedule.steps.count)")
                    .font(.subheadline.monospacedDigit())
            }

            if let activeStep {
                Image(systemName: activeStep.step.symbolName)
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text(activeStep.step.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(timeMessage(for: activeStep))
                        .font(.title3.monospacedDigit())
                        .contentTransition(.numericText())
                }

                Button(action: completeAction) {
                    Label("Schritt erledigt", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .foregroundStyle(color)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54))
                Text("Du bist bereit")
                    .font(.largeTitle.bold())
                Text("Mit \(schedule.plan.bufferMinutes) Minuten Puffer bis zum Ziel.")
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(urgency == .transition ? .black : .white)
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 330)
        .background(
            LinearGradient(
                colors: [color, color.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 28)
        )
        .shadow(color: color.opacity(0.2), radius: 18, y: 8)
        .animation(.easeInOut, value: urgency)
    }

    private func timeMessage(for item: ScheduledStep) -> String {
        if now < item.startDate {
            return "Start in \(duration(from: now, to: item.startDate))"
        }
        if now <= item.endDate {
            return "Noch \(duration(from: now, to: item.endDate))"
        }
        return "Seit \(duration(from: item.endDate, to: now)) fällig"
    }

    private func duration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TimelineStepRow: View {
    let item: ScheduledStep
    let isActive: Bool
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : item.step.symbolName)
                    .font(.title3)
                    .foregroundStyle(isCompleted ? .green : isActive ? .orange : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.step.title)
                        .fontWeight(isActive ? .semibold : .regular)
                        .strikethrough(isCompleted)
                    Text("\(item.startDate.formatted(date: .omitted, time: .shortened)) · \(item.step.durationMinutes) Min.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Text("JETZT")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.15), in: .capsule)
                        .foregroundStyle(.orange)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isCompleted ? "Als nicht erledigt markieren" : "Als erledigt markieren")
    }
}
