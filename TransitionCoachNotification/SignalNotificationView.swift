import SwiftUI

/// Payload the scheduler puts in `UNNotificationContent.userInfo`.
struct StepNotification {
    var instruction: String
    var nextTitle: String
    var nextDurationMinutes: Int
    var stepIndex: Int
    var stepCount: Int

    var detail: String {
        guard !nextTitle.isEmpty else {
            return stepCount > 0 ? "Last step of \(stepCount)" : "Last step"
        }
        return "\(nextTitle) starts next · \(nextDurationMinutes) min"
    }

    init(userInfo: [AnyHashable: Any], fallbackBody: String) {
        instruction = userInfo["stepTitle"] as? String ?? fallbackBody
        nextTitle = userInfo["nextTitle"] as? String ?? ""
        nextDurationMinutes = userInfo["nextDurationMinutes"] as? Int ?? 0
        stepIndex = userInfo["stepIndex"] as? Int ?? 0
        stepCount = userInfo["stepCount"] as? Int ?? 0
    }
}

/// The banner from frame 4: dark blurred surface, amber accent bar, "TC" mark,
/// bold instruction line. Replaces the default notification body layout.
struct SignalNotificationView: View {
    let step: StepNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Signal.accent)
                .frame(width: 5)

            mark
                .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Transition Coach")
                        .signalEyebrow(size: 12, color: .white.opacity(0.6), tracking: 0.08)
                    Spacer(minLength: 8)
                    Text("now")
                        .font(SignalFont.grotesk(12, .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(step.instruction)
                    .font(SignalFont.grotesk(17, .bold))
                    .tracking(-0.17)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.detail)
                    .font(SignalFont.grotesk(14))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 16)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.white.opacity(0.14)
                Signal.background.opacity(0.55)
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        }
        .environment(\.colorScheme, .dark)
    }

    private var mark: some View {
        Text("TC")
            .font(SignalFont.grotesk(13, .bold))
            .foregroundStyle(Signal.accent)
            .frame(width: 34, height: 34)
            .background(Signal.background, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Signal.accent.opacity(0.4), lineWidth: 1)
            }
            .padding(.top, 16)
    }
}
