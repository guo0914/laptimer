import Foundation
import SwiftUI
import Combine

/// 正计时引擎：分段、限时、暂停/继续、进程重启后恢复。
/// 时间一律用「累计时长 + 起跳时刻」推算，不做逐秒累加，
/// 所以后台挂起、锁屏、杀进程都不会丢时间。
final class StopwatchEngine: ObservableObject {
    @Published private(set) var snapshot: StopwatchSnapshot

    private let storeKey = "stopwatch"
    private var limitTimer: Timer?

    init() {
        snapshot = SessionStore.shared.load(StopwatchSnapshot.self, key: "stopwatch")
            ?? StopwatchSnapshot()
        if snapshot.isRunning, snapshot.startedAt == nil {
            snapshot.isRunning = false
        }
        refreshRunningSideEffects()
    }

    // MARK: - 派生状态

    func elapsed(at date: Date = Date()) -> TimeInterval {
        Self.elapsed(for: snapshot, at: date)
    }

    static func elapsed(for snapshot: StopwatchSnapshot, at date: Date) -> TimeInterval {
        var value = snapshot.accumulated
        if snapshot.isRunning, let startedAt = snapshot.startedAt {
            value += max(0, date.timeIntervalSince(startedAt))
        }
        return max(0, value)
    }

    var isRunning: Bool { snapshot.isRunning }
    var hasSession: Bool { snapshot.sessionStart != nil || !snapshot.laps.isEmpty || snapshot.accumulated > 0 }
    var laps: [LapRecord] { snapshot.laps }
    var limit: TimeInterval? { snapshot.limit }

    var currentSplit: TimeInterval {
        liveSplit(at: Date())
    }

    /// 进行中那一段的用时，按给定时刻计算（供 TimelineView 逐帧使用）。
    func liveSplit(at date: Date) -> TimeInterval {
        let last = snapshot.laps.last?.total ?? 0
        return max(0, elapsed(at: date) - last)
    }

    /// 是否有东西可清（用于「重置」按钮的可用状态）。
    var hasAccumulated: Bool { snapshot.accumulated > 0 }

    var limitProgress: Double? {
        guard let limit = snapshot.limit, limit > 0 else { return nil }
        return min(1, elapsed() / limit)
    }

    var limitRemaining: TimeInterval? {
        guard let limit = snapshot.limit else { return nil }
        return limit - elapsed()
    }

    var isOverLimit: Bool {
        guard let limit = snapshot.limit else { return false }
        return elapsed() >= limit
    }

    /// 相对「此前平均分段」的偏差，用来标偏慢 / 最快。
    func delta(for lap: LapRecord) -> TimeInterval? {
        let earlier = snapshot.laps.filter { $0.index < lap.index }
        guard !earlier.isEmpty else { return nil }
        let average = earlier.reduce(0) { $0 + $1.split } / Double(earlier.count)
        return lap.split - average
    }

    var fastestLapID: UUID? {
        guard snapshot.laps.count >= 2 else { return nil }
        return snapshot.laps.min { $0.split < $1.split }?.id
    }

    var averageSplit: TimeInterval? {
        guard !snapshot.laps.isEmpty else { return nil }
        return snapshot.laps.reduce(0) { $0 + $1.split } / Double(snapshot.laps.count)
    }

    // MARK: - 操作

    func start() {
        guard !snapshot.isRunning else { return }
        if snapshot.sessionStart == nil {
            snapshot.sessionStart = Date()
            snapshot.laps = []
            snapshot.accumulated = 0
            snapshot.limitAlerted = false
        }
        snapshot.startedAt = Date()
        snapshot.isRunning = true
        Feedback.tap()
        persist()
        refreshRunningSideEffects()
    }

    func pause() {
        guard snapshot.isRunning else { return }
        snapshot.accumulated = elapsed()
        snapshot.startedAt = nil
        snapshot.isRunning = false
        snapshot.pauseCount += 1
        Feedback.toggle()
        persist()
        refreshRunningSideEffects()
    }

    func resume() {
        guard !snapshot.isRunning, snapshot.sessionStart != nil else { return }
        snapshot.startedAt = Date()
        snapshot.isRunning = true
        Feedback.toggle()
        persist()
        refreshRunningSideEffects()
    }

    func togglePause() {
        if snapshot.isRunning {
            pause()
        } else {
            resume()
        }
    }

    /// 记一段：以当前总时长切分。
    func addLap() {
        guard snapshot.sessionStart != nil else { return }
        let now = Date()
        let total = elapsed(at: now)
        let previousTotal = snapshot.laps.last?.total ?? 0
        let split = max(0, total - previousTotal)
        let record = LapRecord(index: snapshot.laps.count + 1,
                               split: split,
                               total: total,
                               recordedAt: now)
        snapshot.laps.append(record)
        snapshot.limitAlerted = isOverLimit
        Feedback.lap()
        persist()
    }

    /// 撤销最近一段。
    func deleteLastLap() {
        guard !snapshot.laps.isEmpty else { return }
        snapshot.laps.removeLast()
        Feedback.tap()
        persist()
    }

    func setLimit(_ limit: TimeInterval?) {
        snapshot.limit = limit
        snapshot.limitAlerted = isOverLimit
        persist()
        refreshRunningSideEffects()
    }

    /// 结束本次计时，返回可保存的历史记录。
    func finish() -> SavedSession? {
        let now = Date()
        let total = elapsed(at: now)
        let session = snapshot.sessionStart
        let laps = snapshot.laps
        let limit = snapshot.limit

        snapshot = StopwatchSnapshot()
        persist()
        refreshRunningSideEffects()
        Notifier.cancel("limit")

        guard let startedAt = session, total > 0 else { return nil }
        return SavedSession(startedAt: startedAt,
                            endedAt: now,
                            total: total,
                            limit: limit,
                            laps: laps)
    }

    /// 直接丢弃，不留历史。
    func discard() {
        snapshot = StopwatchSnapshot()
        persist()
        refreshRunningSideEffects()
        Notifier.cancel("limit")
    }

    // MARK: - 限时检查

    /// 到达限时只提醒，不打断计时（继续分段 / 继续计时由你决定）。
    private func checkLimit() {
        guard snapshot.isRunning, let limit = snapshot.limit, !snapshot.limitAlerted else { return }
        guard elapsed() >= limit else { return }
        snapshot.limitAlerted = true
        Feedback.limitReached()
        persist()
    }

    private func refreshRunningSideEffects() {
        limitTimer?.invalidate()
        limitTimer = nil

        if snapshot.isRunning {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.checkLimit()
            }
            RunLoop.main.add(timer, forMode: .common)
            limitTimer = timer
            scheduleLimitNotificationIfNeeded()
        } else {
            Notifier.cancel("limit")
        }
    }

    private func scheduleLimitNotificationIfNeeded() {
        Notifier.cancel("limit")
        guard snapshot.isRunning,
              let limit = snapshot.limit,
              !snapshot.limitAlerted else { return }
        let remaining = limit - elapsed()
        guard remaining > 0 else { return }
        Notifier.scheduleLimit(after: remaining)
    }

    private func persist() {
        SessionStore.shared.save(snapshot, key: storeKey)
    }

    /// 进入后台时落盘并补一次到点通知。
    func persistForBackground() {
        if snapshot.isRunning {
            snapshot.accumulated = elapsed()
            snapshot.startedAt = Date()
        }
        persist()
        scheduleLimitNotificationIfNeeded()
    }
}
