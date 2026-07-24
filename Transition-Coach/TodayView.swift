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
            let windowPhase = schedule.windowPhase(
                at: context.date,
                completedStepIDs: completedIDs
            )
            let style = StateStyle(urgency)
            let snapshot = watchSnapshot(
                schedule: schedule,
                completedIDs: completedIDs,
                windowPhase: windowPhase
            )

            Group {
                if isSkippedToday {
                    let nextSchedule = ScheduleCalculator.schedule(
                        for: routine.plan,
                        on: nextRoutineDate
                    )
                    UpcomingRoutineScreen(
                        schedule: nextSchedule,
                        now: context.date,
                        statusMessage: "Today is skipped",
                        secondaryActionTitle: "Undo today's skip",
                        secondaryAction: {
                            withAnimation(.snappy) {
                                routine.skippedDates.removeAll { Calendar.current.isDateInToday($0) }
                            }
                        }
                    )
                } else if windowPhase == .upcoming {
                    UpcomingRoutineScreen(schedule: schedule, now: context.date)
                } else if windowPhase == .finished {
                    let nextSchedule = ScheduleCalculator.schedule(
                        for: routine.plan,
                        on: nextRoutineDate
                    )
                    UpcomingRoutineScreen(schedule: nextSchedule, now: context.date)
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
                        completedIDs: completedIDs,
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
            .onChange(of: snapshot, initial: true) { _, latest in
                WatchLink.shared.publish(latest)
                WatchLink.shared.primaryActionHandler = {
                    advance(in: schedule)
                }
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

    /// What the watch mirrors. On a skipped day it shows the next run instead,
    /// so the wrist never contradicts the phone.
    private func watchSnapshot(
        schedule: RoutineSchedule,
        completedIDs: Set<UUID>,
        windowPhase: RoutineWindowPhase
    ) -> CoachSnapshot {
        guard isSkippedToday || windowPhase == .finished else {
            return CoachSnapshot(schedule: schedule, day: day, completedStepIDs: completedIDs)
        }
        let next = ScheduleCalculator.schedule(for: routine.plan, on: nextRoutineDate)
        return CoachSnapshot(schedule: next, day: nextRoutineDate, completedStepIDs: [])
    }

    /// The watch's button does exactly what the phone's does: finish the step in
    /// front of you, or reset once the routine is done.
    private func advance(in schedule: RoutineSchedule) {
        guard !isSkippedToday else { return }
        if let step = schedule.activeStep(completedStepIDs: sessionStore.completedStepIDs) {
            withAnimation(.snappy) { sessionStore.complete(step.id) }
        } else {
            withAnimation(.snappy) { sessionStore.reset() }
        }
    }
}

// MARK: - Calm waiting screen

private struct UpcomingRoutineScreen: View {
    let schedule: RoutineSchedule
    let now: Date
    var statusMessage: String?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transition Coach")
                    .signalEyebrow(color: Signal.restingSecondary, tracking: 0.14)
                Spacer(minLength: 12)
                Text(now.formatted(date: .omitted, time: .shortened))
                    .font(SignalFont.mono(12, .semibold))
                    .foregroundStyle(Signal.restingSecondary)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(SignalFont.grotesk(13, .medium))
                    .foregroundStyle(Signal.restingSecondary)
                    .padding(.top, 12)
            }

            Spacer(minLength: 34)

            Image(systemName: routineSymbol)
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Signal.restingInk)
                .frame(width: 80, height: 80)
                .background(Signal.restingSurface, in: .circle)
                .shadow(color: Signal.restingInk.opacity(0.06), radius: 16, y: 7)

            Text("Next routine")
                .signalEyebrow(color: Signal.restingSecondary, tracking: 0.12)
                .padding(.top, 30)

            Text(schedule.plan.name)
                .font(SignalFont.grotesk(42, .bold))
                .displayTracking(42)
                .foregroundStyle(Signal.restingInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            Text(startLine)
                .font(SignalFont.grotesk(16, .medium))
                .foregroundStyle(Signal.restingSecondary)
                .padding(.top, 14)

            if !schedule.steps.isEmpty {
                LazyVGrid(columns: stepColumns, alignment: .leading, spacing: stepSpacing) {
                    ForEach(schedule.steps) { item in
                        UpcomingStepPreview(
                            title: item.step.title,
                            symbolName: item.step.symbolName,
                            isCompact: usesCompactStepGrid
                        )
                    }
                }
                .padding(.top, 18)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Routine steps")
            }

            Text(detailLine)
                .font(SignalFont.grotesk(14, .medium))
                .foregroundStyle(Signal.restingSecondary)
                .padding(.top, schedule.steps.isEmpty ? 5 : 14)

            Spacer(minLength: 34)

            Text("Starts in")
                .signalEyebrow(color: Signal.restingSecondary, tracking: 0.12)

            Text(SignalClock.text(from: now, to: schedule.startDate))
                .font(SignalFont.mono(54, .bold))
                .foregroundStyle(Signal.restingInk)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.48)
                .padding(.top, 4)

            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .font(SignalFont.grotesk(14, .medium))
                    .foregroundStyle(Signal.restingSecondary)
                    .buttonStyle(.plain)
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 44)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Signal.restingBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Next routine, \(schedule.plan.name), \(detailLine), starts in \(SignalClock.text(from: now, to: schedule.startDate))"
        )
    }

    private var routineSymbol: String {
        schedule.plan.symbolName
    }

    private var durationMinutes: Int {
        schedule.plan.steps.reduce(0) { $0 + max(1, $1.durationMinutes) }
    }

    private var usesCompactStepGrid: Bool {
        schedule.steps.count > 8
    }

    private var stepColumns: [GridItem] {
        let count = usesCompactStepGrid ? 3 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .leading),
            count: count
        )
    }

    private var stepSpacing: CGFloat {
        usesCompactStepGrid ? 8 : 10
    }

    private var startLine: String {
        let calendar = Calendar.current
        let prefix: String
        if calendar.isDateInToday(schedule.startDate) {
            prefix = "Today"
        } else if calendar.isDateInTomorrow(schedule.startDate) {
            prefix = "Tomorrow"
        } else {
            prefix = schedule.startDate.formatted(.dateTime.weekday(.wide).month().day())
        }
        return "\(prefix) at \(schedule.startDate.formatted(date: .omitted, time: .shortened))"
    }

    private var detailLine: String {
        let stepCount = schedule.steps.count
        let steps = stepCount == 1 ? "1 step" : "\(stepCount) steps"
        let readyTime = schedule.plannedFinishDate.formatted(date: .omitted, time: .shortened)
        return "\(steps) · \(durationMinutes) min · ready by \(readyTime)"
    }
}

private struct UpcomingStepPreview: View {
    let title: String
    let symbolName: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Image(systemName: symbolName)
                .font(.system(
                    size: isCompact ? 11 : 13,
                    weight: .semibold
                ))
                .foregroundStyle(Signal.restingInk)
                .frame(
                    width: isCompact ? 24 : 28,
                    height: isCompact ? 24 : 28
                )
                .background(Signal.restingSurface, in: .circle)

            Text(title)
                .font(SignalFont.grotesk(isCompact ? 11 : 13, .medium))
                .foregroundStyle(Signal.restingInk.opacity(0.78))
                .lineLimit(isCompact ? 1 : 2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Colors for one schedule state. Defined in Shared so the watch mirrors them.
private typealias StateStyle = SignalStateStyle

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
    let completedIDs: Set<UUID>
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

            if urgency != .completed {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text(routineEndText)
                        .font(SignalFont.mono(13, .semibold))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(style.ink.opacity(urgency == .critical ? 0.82 : 0.68))
                .padding(.top, 14)
                .accessibilityLabel(routineEndAccessibilityLabel)
            }

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(timerText)
                    .font(SignalFont.mono(56, .bold))
                    .foregroundStyle(style.ink)
                    .contentTransition(.numericText())
                    // A long overrun renders as H:MM:SS, which is too wide at 56pt.
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
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
        }
        .padding(.leading, 28)
        .padding(.trailing, schedule.steps.isEmpty ? 28 : 84)
        .padding(.top, 24)
        .padding(.bottom, 44)
        .frame(maxWidth: 560)
        .overlay(alignment: .trailing) {
            if !schedule.steps.isEmpty {
                LiveStepProgressRail(
                    steps: schedule.steps,
                    activeStepID: activeStep?.id,
                    completedIDs: completedIDs,
                    ink: style.ink,
                    background: style.background
                )
                .padding(.trailing, 20)
                .padding(.vertical, 74)
            }
        }
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

    private var routineEndText: String {
        if now <= schedule.plannedFinishDate {
            return "\(clock(from: now, to: schedule.plannedFinishDate)) until routine end"
        }
        return "+\(clock(from: schedule.plannedFinishDate, to: now)) past planned end"
    }

    private var routineEndAccessibilityLabel: String {
        if now <= schedule.plannedFinishDate {
            return "Time until routine end: \(clock(from: now, to: schedule.plannedFinishDate))"
        }
        return "Past planned routine end by \(clock(from: schedule.plannedFinishDate, to: now))"
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

    private func clock(from start: Date, to end: Date) -> String {
        SignalClock.text(from: start, to: end)
    }
}

private struct LiveStepProgressRail: View {
    let steps: [ScheduledStep]
    let activeStepID: UUID?
    let completedIDs: Set<UUID>
    let ink: Color
    let background: Color

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, item in
                        let isActive = item.id == activeStepID
                        let isCompleted = completedIDs.contains(item.id)

                        LiveStepProgressIcon(
                            symbolName: item.step.symbolName,
                            isActive: isActive,
                            isCompleted: isCompleted,
                            ink: ink,
                            background: background
                        )
                            .id(item.id)
                            .accessibilityLabel(
                                "Step \(index + 1), \(item.step.title), \(stateLabel(isActive: isActive, isCompleted: isCompleted))"
                            )
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .frame(width: 52)
            .frame(maxHeight: 360)
            .onChange(of: activeStepID, initial: true) { _, newValue in
                guard let target = newValue ?? steps.last?.id else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Routine progress")
    }

    private func stateLabel(isActive: Bool, isCompleted: Bool) -> String {
        if isActive { return "current" }
        if isCompleted { return "completed" }
        return "upcoming"
    }
}

private struct LiveStepProgressIcon: View {
    let symbolName: String
    let isActive: Bool
    let isCompleted: Bool
    let ink: Color
    let background: Color

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(
                size: isActive ? 19 : 15,
                weight: isActive ? .bold : .semibold
            ))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(fill)
                    .overlay {
                        if !isActive && !isCompleted {
                            Circle()
                                .stroke(ink.opacity(0.26), lineWidth: 1)
                        }
                    }
            }
            .overlay(alignment: .bottomTrailing) {
                if isCompleted && !isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(background)
                        .frame(width: 13, height: 13)
                        .background(Signal.complete, in: .circle)
                }
            }
            .shadow(
                color: isActive ? ink.opacity(0.22) : .clear,
                radius: 8,
                y: 2
            )
    }

    private var diameter: CGFloat {
        isActive ? 44 : 34
    }

    private var foreground: Color {
        if isActive { return background }
        if isCompleted { return Signal.complete }
        return ink.opacity(0.46)
    }

    private var fill: Color {
        if isActive { return ink }
        if isCompleted { return ink.opacity(0.13) }
        return .clear
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
