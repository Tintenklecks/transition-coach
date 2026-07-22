import SwiftUI

struct TodayView: View {
    let selection: ActiveRoutineSelection?
    @Bindable var sessionStore: RoutineSessionStore

    var body: some View {
        Group {
            if let selection {
                RoutineTodayContent(
                    routine: selection.routine,
                    day: selection.day,
                    sessionStore: sessionStore
                )
            } else {
                NoRoutineView()
            }
        }
    }
}

// MARK: - Live step screen (frames 1 & 2)

/// The whole screen becomes the current phase's color: one instruction, one
/// countdown, one action. This is the core interaction, not a status chip.
private struct RoutineTodayContent: View {
    let routine: Routine
    /// The calendar day this screen is planning for — today while the routine is
    /// still actionable, otherwise its next non-skipped day. Everything below is
    /// scheduled against this, never against "now".
    let day: Date
    @Bindable var sessionStore: RoutineSessionStore
    @State private var showsTimeline = false

    private static let extensionMinutes = 2

    private var isRenderingToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    /// "today" / "tomorrow" / "in N days" for the day being rendered.
    private var dayLabel: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: day)
        ).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }

    /// The run after the one on screen. When the screen already shows a future
    /// day, that day *is* the next run.
    private var nextRoutineDate: Date {
        isRenderingToday ? routine.nextNonSkippedDate(after: day) : day
    }

    private var isSkippedToday: Bool {
        routine.skippedDates.contains(where: { Calendar.current.isDateInToday($0) })
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let plan = routine.plan.spendingBuffer(sessionStore.spentBufferMinutes)
            let schedule = ScheduleCalculator.schedule(for: plan, on: day)
            let completedIDs = sessionStore.completedStepIDs
            let activeStep = schedule.activeStep(completedStepIDs: completedIDs)
            let urgency = schedule.urgency(at: context.date, completedStepIDs: completedIDs)
            let style = StateStyle(urgency)

            Group {
                if isSkippedToday {
                    SkippedDayScreen(
                        plan: routine.plan,
                        now: context.date,
                        nextDate: nextRoutineDate,
                        undoAction: {
                            withAnimation(.snappy) {
                                routine.skippedDates.removeAll { Calendar.current.isDateInToday($0) }
                            }
                        }
                    )
                } else {
                    LiveStepScreen(
                        schedule: schedule,
                        activeStep: activeStep,
                        urgency: urgency,
                        style: style,
                        now: context.date,
                        routineName: routine.name,
                        nextDate: nextRoutineDate,
                        dayLabel: dayLabel,
                        isToday: isRenderingToday,
                        completedCount: completedIDs.count,
                        canSpendBuffer: sessionStore.spentBufferMinutes < routine.bufferMinutes,
                        extensionMinutes: Self.extensionMinutes,
                        primaryAction: {
                            if let activeStep {
                                withAnimation(.snappy) { sessionStore.complete(activeStep.id) }
                            } else {
                                withAnimation(.snappy) { sessionStore.reset() }
                            }
                        },
                        extendAction: {
                            withAnimation(.snappy) {
                                sessionStore.spendBuffer(Self.extensionMinutes, limit: routine.bufferMinutes)
                            }
                        },
                        skipAction: {
                            withAnimation(.snappy) {
                                if urgency == .completed {
                                    routine.skipDate(routine.nextNonSkippedDate(after: day))
                                } else {
                                    routine.skipDate(day)
                                }
                            }
                        },
                        timelineAction: { showsTimeline = true }
                    )
                }
            }
            .task(id: "\(routine.id)-\(Calendar.current.startOfDay(for: day).timeIntervalSince1970)") {
                sessionStore.prepare(for: routine.id, date: day)
            }
            .onChange(of: urgency == .completed) { _, finished in
                guard finished else { return }
                sessionStore.recordOutcome(
                    onTime: context.date <= schedule.plannedFinishDate,
                    date: day
                )
            }
            .sheet(isPresented: $showsTimeline) {
                TimelineScreen(
                    routine: routine,
                    schedule: schedule,
                    activeStep: activeStep,
                    completedIDs: completedIDs,
                    outcomes: sessionStore.weekOutcomes(containing: context.date),
                    resetAction: { withAnimation(.snappy) { sessionStore.reset() } }
                )
            }
        }
    }
}

// MARK: - Skipped-day screen

private struct SkippedDayScreen: View {
    let plan: RoutinePlan
    let now: Date
    let nextDate: Date
    let undoAction: () -> Void

    var body: some View {
        let nextSchedule = ScheduleCalculator.schedule(for: plan, on: nextDate)
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: nextDate)
        ).day ?? 1
        let dayLabel = days == 1 ? "Tomorrow" : "In \(days) days"

        VStack(alignment: .leading, spacing: 0) {
            Text("Skipped today · \(now.formatted(date: .omitted, time: .shortened))")
                .signalEyebrow(color: .white.opacity(0.6), tracking: 0.14)

            Text(plan.name.uppercased())
                .font(SignalFont.grotesk(44, .bold))
                .displayTracking(44)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)

            Text("\(dayLabel) at \(nextSchedule.targetDate.formatted(date: .omitted, time: .shortened))")
                .font(SignalFont.grotesk(17, .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Spacer(minLength: 24)

            if let firstStep = nextSchedule.steps.first {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(firstStep.startDate.formatted(date: .omitted, time: .shortened))
                        .font(SignalFont.mono(56, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .layoutPriority(1)
                    Text("routine starts · \(firstStep.step.title.lowercased())")
                        .font(SignalFont.grotesk(14, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                .padding(.bottom, 22)
            }

            Button(action: undoAction) {
                Text("Undo skip")
            }
            .buttonStyle(SignalPrimaryButtonStyle(
                background: Signal.accent,
                foreground: Signal.background
            ))
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 44)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Signal.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// Background, ink and button colors for one schedule state.
///
/// Status colors are functional signals and stay untinted by the brand accent —
/// blue means "not yet", amber means "now", red means "at risk".
private struct StateStyle {
    let background: Color
    let ink: Color
    let buttonBackground: Color
    let buttonForeground: Color
    let prefersDarkChrome: Bool

    init(_ urgency: RoutineUrgency) {
        switch urgency {
        case .preparation:
            background = Signal.upcoming
            ink = .white
            buttonBackground = .white
            buttonForeground = Signal.upcoming
            prefersDarkChrome = true
        case .transition, .overdue:
            background = Signal.now
            ink = Signal.background
            buttonBackground = Signal.background
            buttonForeground = Signal.now
            prefersDarkChrome = false
        case .critical:
            background = Signal.late
            ink = .white
            buttonBackground = .white
            buttonForeground = Signal.late
            prefersDarkChrome = true
        case .completed:
            background = Signal.background
            ink = .white
            buttonBackground = Signal.accent
            buttonForeground = Signal.background
            prefersDarkChrome = true
        }
    }
}

private struct LiveStepScreen: View {
    let schedule: RoutineSchedule
    let activeStep: ScheduledStep?
    let urgency: RoutineUrgency
    let style: StateStyle
    let now: Date
    let routineName: String
    let nextDate: Date
    let dayLabel: String
    let isToday: Bool
    let completedCount: Int
    let canSpendBuffer: Bool
    let extensionMinutes: Int
    let primaryAction: () -> Void
    let extendAction: () -> Void
    let skipAction: () -> Void
    let timelineAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(eyebrow)
                    .signalEyebrow(color: style.ink.opacity(urgency == .critical ? 0.75 : 0.6), tracking: 0.14)
                Spacer(minLength: 12)
                Button(action: timelineAction) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(style.ink.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(style.ink.opacity(0.1), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show this morning's timeline")
            }

            if urgency != .completed {
                Text(routineName)
                    .signalEyebrow(color: style.ink.opacity(urgency == .critical ? 0.75 : 0.6), tracking: 0.14)
                    .padding(.top, 22)
            }

            Text(headline)
                .font(SignalFont.grotesk(44, .bold))
                .displayTracking(44)
                .foregroundStyle(style.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, urgency == .completed ? 28 : 8)

            if !supportingLine.isEmpty {
                Text(supportingLine)
                    .font(SignalFont.grotesk(17, .medium))
                    .foregroundStyle(style.ink.opacity(urgency == .critical ? 0.85 : 0.72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }

            Spacer(minLength: 24)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timerText)
                    .font(SignalFont.mono(56, .bold))
                    .foregroundStyle(style.ink)
                    .contentTransition(.numericText())
                    // A long overrun renders as H:MM:SS, which is too wide at 56pt.
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .layoutPriority(1)
                Text(timerCaption)
                    .font(SignalFont.grotesk(14, .medium))
                    .foregroundStyle(style.ink.opacity(urgency == .critical ? 0.75 : 0.6))
                    .lineLimit(2)
            }
            .padding(.bottom, 22)

            Button(action: primaryAction) {
                Text(buttonTitle)
            }
            .buttonStyle(
                SignalPrimaryButtonStyle(
                    background: style.buttonBackground,
                    foreground: style.buttonForeground
                )
            )

            secondaryLine
                .padding(.top, 14)

            if urgency != .critical, !schedule.steps.isEmpty {
                SignalStepPips(
                    total: schedule.steps.count,
                    completed: min(completedCount, schedule.steps.count),
                    ink: style.ink
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 44)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(style.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.35), value: urgency)
        .preferredColorScheme(style.prefersDarkChrome ? .dark : .light)
    }

    // MARK: Copy

    private var eyebrow: String {
        let clock = now.formatted(date: .omitted, time: .shortened)
        guard urgency == .preparation || urgency == .transition,
              let activeStep,
              let index = schedule.steps.firstIndex(where: { $0.id == activeStep.id })
        else {
            return "\(urgency.eyebrow) · \(clock)"
        }
        return "Step \(index + 1) of \(schedule.steps.count) · \(clock)"
    }

    private var nextSchedule: RoutineSchedule? {
        guard urgency == .completed else { return nil }
        return ScheduleCalculator.schedule(for: schedule.plan, on: nextDate)
    }

    private var nextDateLabel: String {
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: nextDate)).day ?? 1
        return days == 1 ? "Tomorrow" : "In \(days) days"
    }

    private var headline: String {
        if urgency == .completed {
            return routineName.uppercased()
        }
        guard let activeStep else { return urgency.title }
        return urgency == .critical ? urgency.title : activeStep.step.title
    }

    private var supportingLine: String {
        guard let activeStep else {
            if urgency == .completed, let ts = nextSchedule {
                return "\(nextDateLabel) at " + ts.targetDate.formatted(date: .omitted, time: .shortened)
            }
            return urgency.reassurance ?? "Every step is done with time to spare."
        }
        switch urgency {
        case .preparation:
            let time = activeStep.startDate.formatted(date: .omitted, time: .shortened)
            return isToday
                ? "Starts at \(time). Nothing to do yet."
                : "Starts \(dayLabel) at \(time). Nothing to do yet."
        case .transition:
            if let next = nextStep {
                return "This is the moment. \(next.step.title) starts when you finish."
            }
            return "Last step. Finish this and you're out the door on time."
        case .overdue:
            return "Still fine — your buffer is covering this. Move when you can."
        case .critical:
            // Deliberately not "\(title) should already be underway" — step names
            // are often verb phrases ("Leave the computer") and break that sentence.
            return "This step should already be underway. Departure buffer is shrinking."
        case .completed:
            return ""
        }
    }

    private var timerText: String {
        if urgency == .completed {
            if let ts = nextSchedule, let firstStep = ts.steps.first {
                return firstStep.startDate.formatted(date: .omitted, time: .shortened)
            }
            return nextDate.formatted(date: .omitted, time: .shortened)
        }
        guard let activeStep else {
            return schedule.targetDate.formatted(date: .omitted, time: .shortened)
        }
        switch urgency {
        case .preparation:
            return clock(from: now, to: activeStep.startDate)
        case .transition:
            return "NOW"
        case .overdue:
            return "+" + clock(from: activeStep.endDate, to: now)
        case .critical:
            return "-" + clock(from: activeStep.endDate.addingTimeInterval(bufferSeconds), to: now)
        case .completed:
            return schedule.targetDate.formatted(date: .omitted, time: .shortened)
        }
    }

    private var timerCaption: String {
        switch urgency {
        case .preparation:
            "until \(activeStep?.step.title.lowercased() ?? "start")"
        case .transition:
            if let next = nextStep {
                "next: \(next.step.title) · \(next.step.durationMinutes) min"
            } else {
                "last step"
            }
        case .overdue:
            "past due"
        case .critical:
            "buffer lost"
        case .completed:
            nextSchedule.flatMap { $0.steps.first }.map { "routine starts · " + $0.step.title.lowercased() } ?? "routine starts"
        }
    }

    private var buttonTitle: String {
        switch urgency {
        case .preparation: "Start now"
        case .transition, .overdue: "I'm moving"
        case .critical: "I'm on it"
        case .completed: "Reset for tomorrow"
        }
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if urgency == .critical {
            Text(urgency.reassurance ?? "")
                .font(SignalFont.grotesk(14, .medium))
                .foregroundStyle(style.ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else if urgency == .completed {
            Button(action: skipAction) {
                Text("Skip \(nextDateLabel.lowercased())")
                    .font(SignalFont.grotesk(14, .medium))
                    .foregroundStyle(style.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        } else if urgency == .preparation {
            VStack(spacing: 8) {
                if canSpendBuffer {
                    Button(action: extendAction) {
                        Text("+\(extensionMinutes) minutes")
                            .font(SignalFont.grotesk(14, .medium))
                            .foregroundStyle(style.ink.opacity(0.55))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Spends \(extensionMinutes) minutes of your safety buffer")
                }
                Button(action: skipAction) {
                    Text("Skip \(dayLabel)")
                        .font(SignalFont.grotesk(14, .medium))
                        .foregroundStyle(style.ink.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        } else if canSpendBuffer {
            Button(action: extendAction) {
                Text("+\(extensionMinutes) minutes")
                    .font(SignalFont.grotesk(14, .medium))
                    .foregroundStyle(style.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Spends \(extensionMinutes) minutes of your safety buffer")
        } else {
            Text("No buffer left today.")
                .font(SignalFont.grotesk(14, .medium))
                .foregroundStyle(style.ink.opacity(0.45))
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Helpers

    private var nextStep: ScheduledStep? {
        guard let activeStep,
              let index = schedule.steps.firstIndex(where: { $0.id == activeStep.id }),
              schedule.steps.indices.contains(index + 1)
        else { return nil }
        return schedule.steps[index + 1]
    }

    private var bufferSeconds: TimeInterval {
        Double(schedule.plan.bufferMinutes * 60)
    }

    /// M:SS, promoting to H:MM:SS past the hour so a long overrun never renders
    /// as an unreadable minute count like "828:19".
    private func clock(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        guard hours > 0 else {
            return String(format: "%d:%02d", minutes, seconds % 60)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
    }
}

// MARK: - Timeline screen (frame 3)

private struct TimelineScreen: View {
    let routine: Routine
    let schedule: RoutineSchedule
    let activeStep: ScheduledStep?
    let completedIDs: Set<UUID>
    let outcomes: [DayOutcome]
    let resetAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("This morning")
                        .font(SignalFont.grotesk(26, .bold))
                        .displayTracking(26)
                        .foregroundStyle(Signal.textPrimary)

                    Text("\(routine.name) at \(schedule.targetDate.formatted(date: .omitted, time: .shortened)) · back-planned from arrival")
                        .font(SignalFont.grotesk(14))
                        .foregroundStyle(Signal.textSecondary)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(schedule.steps) { item in
                            TimelineRow(
                                item: item,
                                isActive: item.id == activeStep?.id,
                                isCompleted: completedIDs.contains(item.id)
                            )
                        }
                        DepartureRow(date: schedule.targetDate)
                    }
                    .padding(.top, 24)

                    weeklyCard
                        .padding(.top, 28)

                    if !completedIDs.isEmpty {
                        Button {
                            resetAction()
                            dismiss()
                        } label: {
                            Text("Reset today")
                                .font(SignalFont.grotesk(15, .semibold))
                                .foregroundStyle(Signal.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Signal.surface, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Signal.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(SignalFont.grotesk(15, .semibold))
                        .foregroundStyle(Signal.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var weeklyCard: some View {
        let onTimeCount = outcomes.filter { $0 == .onTime }.count
        let recorded = outcomes.filter { $0 != .noRecord }.count

        return SignalCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("This week")
                    .signalEyebrow(tracking: 0.1)

                Text(recorded == 0
                     ? "No mornings recorded yet"
                     : "\(onTimeCount) of \(recorded) mornings on time")
                    .font(SignalFont.grotesk(17, .bold))
                    .foregroundStyle(Signal.textPrimary)
                    .padding(.top, 10)

                HStack(spacing: 6) {
                    ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                        Capsule()
                            .fill(outcome == .onTime ? Signal.accent : Signal.border)
                            .frame(height: 6)
                    }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

private struct TimelineRow: View {
    let item: ScheduledStep
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: isActive ? 14 : 10, height: isActive ? 14 : 10)
                    .overlay {
                        if isActive {
                            Circle().stroke(Signal.accent.opacity(0.25), lineWidth: 4)
                        }
                    }
                    .padding(.top, isActive ? 2 : 4)
                Rectangle()
                    .fill(Signal.border)
                    .frame(width: 2)
                    .frame(minHeight: 20)
            }
            .frame(width: 14)

            HStack(spacing: 8) {
                Text("\(item.startDate.formatted(date: .omitted, time: .shortened)) · \(item.step.title)")
                    .font(SignalFont.grotesk(isActive ? 16 : 15, isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? Signal.textPrimary : Signal.textSecondary)

                if isActive {
                    Text("\(item.step.durationMinutes) min")
                        .font(SignalFont.mono(13, .medium))
                        .foregroundStyle(Signal.accent)
                } else if isCompleted {
                    Text("— done")
                        .font(SignalFont.grotesk(15, .medium))
                        .foregroundStyle(Signal.textSecondary.opacity(0.5))
                }
            }
            .padding(.bottom, 18)

            Spacer(minLength: 0)
        }
    }

    private var dotColor: Color {
        if isActive { return Signal.now }
        if isCompleted { return Signal.upcoming }
        return Signal.inactive
    }
}

private struct DepartureRow: View {
    let date: Date

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(Signal.inactive)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
                .frame(width: 14)

            Text("\(date.formatted(date: .omitted, time: .shortened)) · Latest departure")
                .font(SignalFont.grotesk(15, .medium))
                .foregroundStyle(Signal.textSecondary)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Empty state

private struct NoRoutineView: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Nothing planned yet")
                .font(SignalFont.grotesk(26, .bold))
                .displayTracking(26)
                .foregroundStyle(Signal.textPrimary)

            Text("Create a routine and the coach will back-plan every step from the time you need to be ready.")
                .font(SignalFont.grotesk(15))
                .foregroundStyle(Signal.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Signal.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
