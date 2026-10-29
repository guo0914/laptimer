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

    // MARK: - 键盘输入解析

    /// 用户可能输入的时长写法：
    ///   `30`        → 30 分钟
    ///   `30:00`     → 30 分钟
    ///   `1:30`      → 1 分 30 秒
    ///   `1:30:00`   → 1 小时 30 分
    ///   `90s` / `90秒` → 90 秒
    ///   `2h` / `2小时` → 2 小时
    /// 返回 nil 表示无法解析。
    static func parseDuration(_ raw: String) -> TimeInterval? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "＇", with: "'")

        guard !text.isEmpty else { return nil }

        // 去掉尾部单位，判断是秒 / 分 / 小时
        var unitScale: Double = 60   // 无单位时按分钟
        let lowered = text.lowercased()
        for (suffix, scale) in [("小时", 3600.0), ("时", 3600.0), ("h", 3600.0),
                                ("分钟", 60.0), ("分", 60.0), ("m", 60.0),
                                ("秒钟", 1.0), ("秒", 1.0), ("s", 1.0)] {
            if lowered.hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count))
                unitScale = scale
                break
            }
        }
        text = text.trimmingCharacters(in: .whitespaces)

        // 带冒号：按 时:分:秒 逐段解析
        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 3 else { return nil }
            var total: Double = 0
            var multipliers: [Double] = []
            switch parts.count {
            case 3: multipliers = [3600, 60, 1]
            case 2: multipliers = [60, 1]
            default: multipliers = [60]
            }
            for (index, part) in parts.enumerated() {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                // 允许空段（如 1::30 表示 1 分 0 秒 30？这里不支持，按 0 处理）
                let value = trimmed.isEmpty ? 0 : Double(trimmed)
                guard let value, value >= 0 else { return nil }
                total += value * multipliers[index]
            }
            guard total > 0 else { return nil }
            return total
        }

        // 纯数字：按单位换算
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            return nil
        }
        return value * unitScale
    }

    /// 把秒数写成限时输入框里的默认文本（尽量短且可回读）。
    static func durationInputText(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded())
        guard total > 0 else { return "" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        if seconds > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return "\(minutes)"
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
