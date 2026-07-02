import Foundation
import UserNotifications

/// Schedules the repeating Monday-morning "your weekly recap is ready" local
/// notification. The notification body is static — the actual numbers live in
/// the Dashboard's weekly recap card, which is always up to date when opened.
enum WeeklyRecapNotifier {
    static let identifier = "weeklyRecap"

    /// Requests permission if needed and schedules the repeating trigger.
    /// Returns false when the user denied notification permission.
    static func schedule() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Riepilogo settimanale 📊"
        content.body = "La tua settimana di allenamento è pronta: aprimi per vederla."
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = 2   // Monday
        comps.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        try? await center.add(UNNotificationRequest(identifier: identifier,
                                                    content: content,
                                                    trigger: trigger))
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
