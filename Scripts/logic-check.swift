// 纯逻辑自检：不依赖 SwiftUI / UIKit。
//
// 用法（Mac 或装了 Swift 的 Windows）：
//   swiftc LapTimer/TimeFormatting.swift Scripts/logic-check.swift -o /tmp/logiccheck
//   /tmp/logiccheck
//
// 全部通过时退出码为 0。

import Foundation

@main
struct LogicCheck {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label)")
        }
    }

    static func expectEqual(_ actual: String, _ expected: String, _ label: String) {
        expect(actual == expected, "\(label)（得到 \(actual)，期望 \(expected)）")
    }

    static func main() {
        print("TimeText 自检")

        let p1 = TimeText.stopwatchParts(754.56)
        expectEqual(p1.main, "12:34", "正计时主数字")
        expectEqual(p1.fraction, "56", "正计时百分秒")

        let p2 = TimeText.stopwatchParts(3725.04)
        expectEqual(p2.main, "1:02:05", "超过一小时带小时位")
        expectEqual(p2.fraction, "04", "百分秒补零")

        let p3 = TimeText.stopwatchParts(0)
        expectEqual(p3.main, "00:00", "零值")
        expectEqual(p3.fraction, "00", "零值百分秒")

        let p4 = TimeText.stopwatchParts(-5)
        expectEqual(p4.main, "00:00", "负值兜底")

        expectEqual(TimeText.clock(1800), "30:00", "限时 30 分钟")
        expectEqual(TimeText.clock(5400), "1:30:00", "限时 90 分钟")

        expectEqual(TimeText.countdown(0.4), "00:01", "倒计时向上取整")
        expectEqual(TimeText.countdown(0), "00:00", "倒计时归零")
        expectEqual(TimeText.countdown(65.2), "01:06", "倒计时 65.2 秒")

        expectEqual(TimeText.lap(102.18), "01:42.18", "分段格式")
        expectEqual(TimeText.lap(0.5), "00:00.50", "分段零点五秒")
        expectEqual(TimeText.lap(600), "10:00.00", "分段大于 10 分钟")

        expectEqual(TimeText.delta(11.2), "+11\"", "偏慢差值")
        expectEqual(TimeText.delta(-12.2), "−12\"", "偏快差值（负号是 U+2212）")
        expectEqual(TimeText.delta(0.4), "持平", "无差值")

        // 键盘输入的时长解析
        func expectDuration(_ text: String, _ expected: Double?, _ label: String) {
            let actual = TimeText.parseDuration(text)
            if let expected {
                if let actual {
                    expect(abs(actual - expected) < 0.001,
                           "\(label)：\(text) → \(Int(actual))s（期望 \(Int(expected))s）")
                } else {
                    expect(false, "\(label)：\(text) 解析为 nil（期望 \(Int(expected))s）")
                }
            } else {
                expect(actual == nil, "\(label)：\(text) 应解析失败")
            }
        }

        expectDuration("30", 1800, "纯数字按分钟")
        expectDuration("30:00", 1800, "分钟:秒")
        expectDuration("1:30", 90, "1 分 30 秒")
        expectDuration("1:30:00", 5400, "时:分:秒")
        expectDuration("2:05:30", 7530, "带小时的完整写法")
        expectDuration("90s", 90, "秒单位")
        expectDuration("90秒", 90, "中文秒单位")
        expectDuration("2h", 7200, "小时单位")
        expectDuration("2小时", 7200, "中文小时单位")
        expectDuration("15m", 900, "分钟单位")
        expectDuration("15分", 900, "中文分钟单位")
        expectDuration(" 30 ", 1800, "首尾空格")
        expectDuration("1：30", 90, "全角冒号")
        expectDuration("0.5", 30, "小数分钟")
        expectDuration("", nil, "空字符串")
        expectDuration("abc", nil, "非数字")
        expectDuration("0", nil, "零应视为无效")
        expectDuration("-5", nil, "负数应视为无效")
        expectDuration("1:2:3:4", nil, "超过三段应无效")

        // 回读：秒数 → 输入框文本 → 解析回原值
        expectEqual(TimeText.durationInputText(1800), "30", "30 分钟回读")
        expectEqual(TimeText.durationInputText(90), "1:30", "90 秒回读")
        expectEqual(TimeText.durationInputText(5400), "1:30:00", "90 分钟回读")
        expectEqual(TimeText.durationInputText(0), "", "零值回读为空")
        for value in [60.0, 90.0, 600.0, 1800.0, 5400.0, 7200.0] {
            let text = TimeText.durationInputText(value)
            let back = TimeText.parseDuration(text)
            expect(back == value, "回读往返一致：\(Int(value))s → \"\(text)\" → \(back.map { Int($0) } ?? -1)s")
        }

        // 引擎的时间推算：累计 + 运行中增量
        struct Snap {
            var accumulated: Double
            var startedAt: Date?
            var isRunning: Bool
        }

        func elapsed(_ s: Snap, at date: Date) -> Double {
            var value = s.accumulated
            if s.isRunning, let start = s.startedAt {
                value += max(0, date.timeIntervalSince(start))
            }
            return max(0, value)
        }

        let base = Date(timeIntervalSince1970: 1_000)
        let running = Snap(accumulated: 12, startedAt: base, isRunning: true)
        expect(abs(elapsed(running, at: base.addingTimeInterval(30)) - 42) < 0.001, "运行中累计推算")

        let paused = Snap(accumulated: 42, startedAt: nil, isRunning: false)
        expect(abs(elapsed(paused, at: base.addingTimeInterval(300)) - 42) < 0.001, "暂停后不增长")

        let stale = Snap(accumulated: 42, startedAt: base, isRunning: false)
        expect(abs(elapsed(stale, at: base.addingTimeInterval(300)) - 42) < 0.001, "已停但残留起跳时刻不增长")

        print()
        if failures == 0 {
            print("全部通过")
            exit(0)
        } else {
            print("\(failures) 项失败")
            exit(1)
        }
    }
}
