import Foundation
import UserNotifications

/// 后台提醒：App 被切到后台或锁屏时，靠本地通知把「到点」补上。
/// 通知权限没给也不影响前台使用。
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func schedule(id: String, after seconds: TimeInterval, title: String, body: String) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleLimit(after seconds: TimeInterval) {
        schedule(id: "limit",
                 after: seconds,
                 title: "已到达设定时限",
                 body: "正计时仍在继续，记得查看当前分段。")
    }

    static func scheduleCountdown(after seconds: TimeInterval) {
        schedule(id: "countdown",
                 after: seconds,
                 title: "倒计时结束",
                 body: "时间到了。")
    }

    static func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["limit", "countdown"])
    }
}
