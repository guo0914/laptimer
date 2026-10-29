// 引擎层类型检查用的最小平台桩。
//
// 把 UIKit / Combine / AudioToolbox / UserNotifications 里引擎与模型实际用到的
// 那几个符号换成最小实现，这样 StopwatchEngine、CountdownEngine、HistoryStore、
// 模型与格式化逻辑可以在 Windows 的 Swift 编译器下被**真实类型检查**，
// 从而在没有 Mac 的情况下捕获类型错误与成员拼写错误。
//
// 只服务于 Scripts/typecheck-engine.ps1，不会编进 App。
// UI 层（SwiftUI 视图）无法用桩代替，必须在 Mac 的 Xcode 里检查。

import Foundation

// MARK: - Combine 最小替身

final class ObservableObjectPublisher {
    func send() {}
}

protocol ObservableObject: AnyObject {}

extension ObservableObject {
    var objectWillChange: ObservableObjectPublisher { ObservableObjectPublisher() }
}

@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    var projectedValue: Published<Value> { self }
}

// MARK: - UIKit 触觉反馈

final class UISelectionFeedbackGenerator {
    func selectionChanged() {}
}

final class UIImpactFeedbackGenerator {
    enum FeedbackStyle {
        case light
        case medium
        case heavy
    }

    init(style: FeedbackStyle) {}
    func prepare() {}
    func impactOccurred() {}
}

final class UINotificationFeedbackGenerator {
    enum FeedbackType {
        case success
        case warning
        case error
    }

    func notificationOccurred(_ type: FeedbackType) {}
}

// MARK: - AudioToolbox

func AudioServicesPlaySystemSound(_ soundID: UInt32) {}
func AudioServicesPlayAlertSound(_ alertID: UInt32) {}

// MARK: - UserNotifications

final class UNMutableNotificationContent {
    var title: String = ""
    var body: String = ""
    var sound: UNNotificationSound?
}

final class UNNotificationSound {
    static let `default` = UNNotificationSound()
}

final class UNTimeIntervalNotificationTrigger {
    init(timeInterval: TimeInterval, repeats: Bool) {}
}

final class UNNotificationRequest {
    init(identifier: String,
         content: UNMutableNotificationContent,
         trigger: UNTimeIntervalNotificationTrigger?) {}
}

final class UNUserNotificationCenter {
    struct AuthorizationOptions: OptionSet {
        let rawValue: Int
        static let badge = AuthorizationOptions(rawValue: 1)
        static let sound = AuthorizationOptions(rawValue: 2)
        static let alert = AuthorizationOptions(rawValue: 4)
    }

    static func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }

    func requestAuthorization(options: UNUserNotificationCenter.AuthorizationOptions,
                              completionHandler: @escaping (Bool, Error?) -> Void) {
        completionHandler(true, nil)
    }

    func add(_ request: UNNotificationRequest,
             withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {}

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}
