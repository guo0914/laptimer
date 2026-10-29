import Foundation

#if canImport(UIKit)
import UIKit
import AudioToolbox
#endif

/// 触觉与声音反馈。集中在这里，方便以后在设置里统一开关。
enum Feedback {
    static var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticsEnabled") }
    }

    static var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEnabled") }
    }

    /// 记一段：轻而清晰的确认感。
    static func lap() {
        guard hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func tap() {
        guard hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 暂停 / 继续：中等强度。
    static func toggle() {
        guard hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// 限时到点：警示级震动 + 提示音，但计时继续。
    static func limitReached() {
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        if soundEnabled {
            AudioServicesPlaySystemSound(1005)
        }
    }

    /// 倒计时结束。
    static func finished() {
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if soundEnabled {
            AudioServicesPlayAlertSound(1005)
        }
    }
}
