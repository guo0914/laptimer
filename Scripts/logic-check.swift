// 纯逻辑自检：不依赖 SwiftUI / UIKit。
// 用法（在 Mac 上）：
//   swiftc LapTimer/TimeFormatting.swift Scripts/logic-check.swift -o /tmp/logiccheck
//   /tmp/logiccheck
// 全部通过时退出码为 0。

import Foundation

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label)")
    }
}

func expectEqual(_ actual: String, _ expected: String, _ label: String) {
    expect(actual == expected, "\(label)（得到 \(actual)，期望 \(expected)）")
}

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

// 引擎的时间推算：累计 + 运行中增量
struct Snap { var accumulated: Double; var startedAt: Date?; var isRunning: Bool }

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

if failures == 0 {
    print("全部通过")
    exit(0)
} else {
    print("\(failures) 项失败")
    exit(1)
}
