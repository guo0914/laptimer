// 引擎行为自检：真的构造 StopwatchEngine / CountdownEngine 并执行操作，
// 验证分段切分、限时到点、暂停不累计、结束产出历史、重启恢复等行为。
//
// 注意：必须在驱动 RunLoop 的情况下等待，不能 Thread.sleep ——
// 引擎的到点检查依赖 RunLoop 上的 Timer，这与 App 里的真实行为一致。
//
// Windows（配合平台桩）：
//   Scripts/typecheck-engine.ps1 -RunEngineCheck
//
// Mac：
//   swiftc LapTimer/TimeFormatting.swift LapTimer/TimerModels.swift LapTimer/SessionStore.swift \
//          LapTimer/Feedback.swift LapTimer/Notifier.swift LapTimer/StopwatchEngine.swift \
//          LapTimer/CountdownEngine.swift Scripts/engine-check.swift -o /tmp/enginecheck
//   /tmp/enginecheck

import Foundation

@main
struct EngineCheck {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label)")
        }
    }

    static func approximate(_ actual: TimeInterval,
                            _ expected: TimeInterval,
                            _ tolerance: TimeInterval,
                            _ label: String) {
        let ok = abs(actual - expected) <= tolerance
        let fmt = String(format: "%.2f", actual)
        let want = String(format: "%.2f", expected)
        expect(ok, "\(label)（得到 \(fmt)，期望约 \(want)）")
    }

    /// 在驱动 RunLoop 的前提下等待，让引擎内部的 Timer 正常触发。
    static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func main() {
        // 测试落在可写的工作区目录，不污染真实 App 的 Application Support
        let overrideBase = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".enginecheck-store", isDirectory: true)
        try? FileManager.default.createDirectory(at: overrideBase, withIntermediateDirectories: true)
        SessionStore.baseDirectoryOverride = overrideBase

        let store = SessionStore.shared
        expect(store.isWritable, "落盘目录可写（测试前提）")
        store.remove(key: "stopwatch")
        store.remove(key: "countdown")

        // MARK: 正计时
        print("正计时引擎")
        let sw = StopwatchEngine()

        expect(!sw.isRunning, "初始未运行")
        expect(!sw.hasSession, "初始无会话")

        sw.start()
        expect(sw.isRunning, "开始后运行中")
        expect(sw.hasSession, "开始后有会话")

        wait(0.3)
        let firstTotal = sw.elapsed()
        sw.addLap()
        expect(sw.laps.count == 1, "记一段后段数为 1")
        if let lap = sw.laps.first {
            approximate(lap.total, firstTotal, 0.15, "第 1 段累计等于当时总时长")
            approximate(lap.split, firstTotal, 0.15, "首段用时等于总时长")
            expect(lap.index == 1, "首段序号为 1")
        }

        sw.pause()
        expect(!sw.isRunning, "暂停后停止运行")
        let frozen = sw.elapsed()
        wait(0.4)
        approximate(sw.elapsed(), frozen, 0.02, "暂停后时间不再增长")

        sw.resume()
        expect(sw.isRunning, "继续后运行中")

        wait(0.3)
        sw.addLap()
        expect(sw.laps.count == 2, "第二次记段后段数为 2")
        if sw.laps.count == 2 {
            let l2 = sw.laps[1]
            expect(l2.index == 2, "段序号从 1 递增")
            expect(l2.total >= l2.split, "累计不小于本段")
            approximate(l2.total - sw.laps[0].total, l2.split, 0.02, "本段 = 累计差")
            // 暂停的 0.4 秒不应计入第二段
            expect(l2.split < 0.9, "暂停时间不计入分段")
        }

        expect(sw.averageSplit != nil, "能算出平均分段")
        expect(sw.fastestLapID != nil, "两段后能标出最快段")

        sw.deleteLastLap()
        expect(sw.laps.count == 1, "撤销后段数为 1")

        let session = sw.finish()
        expect(session != nil, "结束后产出历史记录")
        if let session {
            expect(session.laps.count == 1, "历史里保留 1 段")
            expect(session.total > 0, "历史总时长大于 0")
            expect(session.averageSplit != nil, "历史能算平均")
        }
        expect(!sw.hasSession, "结束后会话清空")
        expect(sw.laps.isEmpty, "结束后分段清空")
        expect(!sw.isRunning, "结束后不在运行")

        // MARK: 限时
        print("限时行为")
        store.remove(key: "stopwatch")
        let sw2 = StopwatchEngine()
        sw2.setLimit(1.5)
        expect(sw2.limit == 1.5, "限时可设置")
        expect(sw2.limitProgress == 0, "未开始时进度为 0")
        expect(!sw2.isOverLimit, "未开始时未超时")

        sw2.start()
        wait(1.9)
        expect(sw2.isOverLimit, "超过限时后标记超时")
        expect(sw2.isRunning, "超时后仍在计时（只提醒不打断）")
        expect((sw2.limitProgress ?? 0) >= 1.0, "超时后进度封顶")
        expect((sw2.limitRemaining ?? 1) <= 0, "超时后剩余时间不为正")

        // 超时后仍可正常记段
        sw2.addLap()
        expect(sw2.laps.count == 1, "超时后仍可记段")

        sw2.discard()
        expect(!sw2.hasSession, "丢弃后会话清空")
        expect(sw2.limit == nil, "丢弃后限时也被清空")

        // MARK: 倒计时
        print("倒计时引擎")
        store.remove(key: "countdown")
        let cd = CountdownEngine()
        cd.setDuration(2)
        expect(cd.duration == 2, "时长可设置")
        expect(!cd.hasStarted, "初始未开始")
        expect(cd.progress == 0, "进度为 0")

        cd.start()
        expect(cd.isRunning, "开始后运行中")
        expect(cd.hasStarted, "开始后有 started 标记")

        wait(0.2)
        cd.pause()
        expect(!cd.isRunning, "暂停后停止")
        let remainAtPause = cd.remaining()
        wait(0.3)
        approximate(cd.remaining(), remainAtPause, 0.02, "暂停后剩余时间不变")

        cd.resume()
        expect(cd.isRunning, "继续后运行中")

        cd.extend(by: 1)
        expect(abs(cd.duration - 3) < 0.001, "延长后时长变 3 秒")

        cd.reset()
        expect(abs(cd.duration - 3) < 0.001, "重置保留时长")
        expect(!cd.hasStarted, "重置后回到未开始")
        expect(cd.remaining() == 3, "重置后剩余等于时长")

        cd.setDuration(1)
        cd.start()
        wait(1.3)
        expect(cd.isFinished, "到点后标记结束")
        expect(!cd.isRunning, "到点后停止运行")
        expect(cd.remaining() == 0, "到点后剩余为 0")
        expect(cd.progress >= 1.0, "到点后进度封顶")

        // MARK: 重启恢复
        print()
        print("进程重启后的恢复")
        store.remove(key: "stopwatch")
        let a = StopwatchEngine()
        a.setLimit(10)
        a.start()
        wait(0.4)
        a.addLap()
        a.persistForBackground()

        let b = StopwatchEngine()   // 模拟重启后重新构造
        expect(b.isRunning, "重启后仍在运行")
        expect(b.laps.count == 1, "重启后分段保留")
        expect(b.limit == 10, "重启后限时保留")
        expect(b.elapsed() >= 0.4, "重启后时长接续")

        // 暂停态的恢复
        b.pause()
        b.persistForBackground()
        let c = StopwatchEngine()
        expect(!c.isRunning, "暂停态重启后仍是暂停")
        expect(c.laps.count == 1, "暂停态重启后分段保留")
        approximate(c.elapsed(), b.elapsed(), 0.5, "暂停态重启后时长一致")

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
