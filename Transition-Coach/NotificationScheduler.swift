import Foundation
import UserNotifications

@MainActor
enum NotificationScheduler {
    /// Shared with the notification content extension's `UNNotificationExtensionCategory`.
    static let stepCategoryIdentifier = "TRANSITION_STEP"

    static func enable(for routine: Routine) async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            guard granted else { return false }
            routine.notificationsEnabled = true
            await reschedule(routine)
            return true
        } catch {
            return false
        }
    }

    static func disable(for routine: Routine) async {
        routine.notificationsEnabled = false
        await removeNotifications(for: routine.id)
    }

    static func reschedule(_ routine: Routine) async {
        await removeNotifications(for: routine.id)
        guard routine.notificationsEnabled, routine.isEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let schedule = ScheduleCalculator.schedule(for: routine.plan, on: Date(), calendar: calendar)

        for (index, item) in schedule.steps.enumerated() {
            let next = schedule.steps.indices.contains(index + 1) ? schedule.steps[index + 1] : nil

            let content = UNMutableNotificationContent()
            content.title = "Transition Coach"
            content.body = item.step.title
            content.sound = .default
            content.threadIdentifier = routine.id.uuidString
            // Lets the notification content extension take over the expanded view.
            content.categoryIdentifier = Self.stepCategoryIdentifier
            content.userInfo = [
                "routineID": routine.id.uuidString,
                "stepID": item.id.uuidString,
                "stepTitle": item.step.title,
                "stepIndex": index + 1,
                "stepCount": schedule.steps.count,
                "nextTitle": next?.step.title ?? "",
                "nextDurationMinutes": next?.step.durationMinutes ?? 0
            ]

            let components = calendar.dateComponents([.hour, .minute], from: item.startDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: identifier(for: routine.id, stepID: item.id),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private static func removeNotifications(for routineID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "transition-coach.\(routineID.uuidString)."
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func identifier(for routineID: UUID, stepID: UUID) -> String {
        "transition-coach.\(routineID.uuidString).\(stepID.uuidString)"
    }
}
