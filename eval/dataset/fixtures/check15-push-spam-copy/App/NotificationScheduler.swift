import Foundation
import UserNotifications

enum NotificationScheduler {
    static func scheduleHourlyDeals() {
        let content = UNMutableNotificationContent()
        content.title = "🔥 Hot deal alert!"
        content.body = "New discounts just dropped — open now before they're gone!"
        // repeats every hour, all day
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
        let request = UNNotificationRequest(identifier: "hourly-deals",
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
