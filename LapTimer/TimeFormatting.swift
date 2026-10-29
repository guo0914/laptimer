import Foundation

/// 计时相关的纯格式化逻辑。不依赖 UIKit / SwiftUI，
/// 可用 `Scripts/verify-logic.sh` 单独编译验证。
enum TimeText {
    struct Parts {
        var main: String
        var fraction: String
    }

    /// 正计时显示：主数字 + 百分秒。超过 1 小时自动带上小时位。
    static func stopwatchParts(_ interval: TimeInterval) -> Parts {
        let clamped = max(0, interval)
        let centis = Int((clamped * 100).rounded(.down))
        let hundredths = centis % 100
        let totalSeconds = centis / 100
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        let main: String
        if hours > 0 {
            main = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            main = String(format: "%02d:%02d", minutes, seconds)
        }
        return Parts(main: main, fraction: String(format: "%02d", hundredths))
    }

    /// 固定长度 M:SS / H:MM:SS，用于限时、总时长展示。
    static func clock(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(0, interval).rounded(.down))
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 倒计时剩余时间，向上取整，避免最后一秒提前归零。
    static func countdown(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(ceil(max(0, interval)))
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 分段用时：MM:SS.CC
    static func lap(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        let centis = Int((clamped * 100).rounded(.down))
        let hundredths = centis % 100
        let totalSeconds = centis / 100
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    /// 分段与平均值的差值，例如 `+11"` / `−12"` / `持平`。
    static func delta(_ interval: TimeInterval) -> String {
        let value = Int(interval.rounded())
        if value == 0 { return "持平" }
        if value > 0 { return "+\(value)\"" }
        return "−\(abs(value))\""
    }

    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 H:mm"
        return formatter
    }()

    static func clockTime(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }
}
