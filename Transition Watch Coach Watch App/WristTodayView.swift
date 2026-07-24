import SwiftUI

/// The wrist mirror of the Today screen: same state, same color, same countdown,
/// and the one button that moves the routine forward.
///
/// Deliberately read-only otherwise — routines, skipping and every setting live
/// on iPhone/iPad. The watch never plans; it renders what the phone sent.
struct WristTodayView: View {
    @State private var link = WatchLink.shared
    @State private var lastActionFailed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let snapshot = link.snapshot, context.date <= snapshot.expiresAt {
                if isWaitingForRoutine(snapshot, at: context.date) {
                    UpcomingWristScreen(snapshot: snapshot, now: context.date)
                } else {
                    LiveWristScreen(
                        snapshot: snapshot,
                        now: context.date,
                        isReachable: link.isReachable,
                        lastActionFailed: lastActionFailed,
                        action: primaryAction
                    )
                }
            } else {
                WaitingScreen(hasStalePlan: link.snapshot != nil)
            }
        }
        .task { link.activate() }
    }

    private func primaryAction() {
        link.requestPrimaryAction { succeeded in
            lastActionFailed = !succeeded
        }
    }

    private func isWaitingForRoutine(_ snapshot: CoachSnapshot, at date: Date) -> Bool {
        guard snapshot.completedCount == 0 else { return false }
        return date < (snapshot.steps.first?.start ?? snapshot.targetDate)
    }
}

private struct UpcomingWristScreen: View {
    let snapshot: CoachSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transition Coach")
                .signalEyebrow(size: 9, color: Signal.restingSecondary, tracking: 0.1)

            Spacer(minLength: 8)

            HStack(spacing: 9) {
                Image(systemName: snapshot.steps.first?.symbolName ?? "clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Signal.restingInk)
                    .frame(width: 34, height: 34)
                    .background(Signal.restingSurface, in: .circle)

                Text(snapshot.routineName)
                    .font(SignalFont.grotesk(17, .bold))
                    .foregroundStyle(Signal.restingInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            Text(SignalClock.text(from: now, to: startDate))
                .font(SignalFont.mono(31, .bold))
                .foregroundStyle(Signal.restingInk)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("until next routine")
                .font(SignalFont.grotesk(11, .medium))
                .foregroundStyle(Signal.restingSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Signal.restingBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var startDate: Date {
        snapshot.steps.first?.start ?? snapshot.targetDate
    }
}

private struct LiveWristScreen: View {
    let snapshot: CoachSnapshot
    let now: Date
    let isReachable: Bool
    let lastActionFailed: Bool
    let action: () -> Void

    var body: some View {
        let urgency = snapshot.urgency(at: now)
        let style = SignalStateStyle(urgency)

        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.routineName)
                .signalEyebrow(size: 10, color: style.ink.opacity(0.65), tracking: 0.12)
                .lineLimit(1)

            Text(headline(urgency))
                .font(SignalFont.grotesk(19, .bold))
                .foregroundStyle(style.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Spacer(minLength: 6)

            Text(timerText(urgency))
                .font(SignalFont.mono(34, .bold))
                .foregroundStyle(style.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            Text(caption(urgency))
                .font(SignalFont.grotesk(11, .medium))
                .foregroundStyle(style.ink.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Button(action: action) {
                Text(buttonTitle(urgency))
                    .font(SignalFont.grotesk(15, .bold))
                    .foregroundStyle(style.buttonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(style.buttonBackground, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .opacity(isReachable ? 1 : 0.5)

            if lastActionFailed {
                Text("iPhone not reachable")
                    .font(SignalFont.grotesk(10, .medium))
                    .foregroundStyle(style.ink.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 3)
            } else if !snapshot.steps.isEmpty {
                SignalStepPips(
                    total: snapshot.steps.count,
                    completed: snapshot.completedCount,
                    ink: style.ink
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(style.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.35), value: urgency)
        .preferredColorScheme(style.prefersDarkChrome ? .dark : .light)
    }

    // MARK: Copy — trimmed for the wrist, same vocabulary as the phone

    private func headline(_ urgency: RoutineUrgency) -> String {
        guard let step = snapshot.activeStep else { return urgency.title }
        return urgency == .critical ? urgency.title : step.title
    }

    private func timerText(_ urgency: RoutineUrgency) -> String {
        guard let step = snapshot.activeStep else {
            return snapshot.targetDate.formatted(date: .omitted, time: .shortened)
        }
        switch urgency {
        case .preparation:
            return SignalClock.text(from: now, to: step.start)
        case .transition:
            return "NOW"
        case .overdue:
            return "+" + SignalClock.text(from: step.end, to: now)
        case .critical:
            let bufferEnd = step.end.addingTimeInterval(Double(snapshot.bufferMinutes * 60))
            return "-" + SignalClock.text(from: bufferEnd, to: now)
        case .completed:
            return snapshot.targetDate.formatted(date: .omitted, time: .shortened)
        }
    }

    private func caption(_ urgency: RoutineUrgency) -> String {
        switch urgency {
        case .preparation: "until \(snapshot.activeStep?.title.lowercased() ?? "start")"
        case .transition: "step \(snapshot.completedCount + 1) of \(snapshot.steps.count)"
        case .overdue: "past due"
        case .critical: "buffer lost"
        case .completed: "target time"
        }
    }

    private func buttonTitle(_ urgency: RoutineUrgency) -> String {
        switch urgency {
        case .preparation: "Start now"
        case .transition, .overdue: "I'm moving"
        case .critical: "I'm on it"
        case .completed: "Reset"
        }
    }
}

/// Shown when the phone has never synced, or when the plan on the wrist is for a
/// window that has already closed. Better an honest blank than a stale red screen.
private struct WaitingScreen: View {
    let hasStalePlan: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.badge.exclamationmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Signal.accent)

            Text(hasStalePlan ? "Plan is out of date" : "Nothing planned yet")
                .font(SignalFont.grotesk(15, .bold))
                .foregroundStyle(Signal.textPrimary)
                .multilineTextAlignment(.center)

            Text("Open Transition Coach on your iPhone.")
                .font(SignalFont.grotesk(12))
                .foregroundStyle(Signal.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Signal.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#Preview {
    WristTodayView()
}
