import Foundation
import SwiftUI
import Combine

/// 倒计时：常规功能，加「进程重启后继续」与后台到点通知。
final class CountdownEngine: ObservableObject {
    @Published private(set) var snapshot: CountdownSnapshot

    private let storeKey = "countdown"
    private var tickTimer: Timer?

    init() {
        snapshot = SessionStore.shared.load(CountdownSnapshot.self, key: "countdown")
            ?? CountdownSnapshot()
        if snapshot.isRunning, snapshot.startedAt == nil {
            snapshot.isRunning = false
        }
        refreshRunningSideEffects()
        checkFinished()
    }

    // MARK: - 派生状态

    func elapsed(at date: Date = Date()) -> TimeInterval {
        var value = snapshot.accumulated
        if snapshot.isRunning, let startedAt = snapshot.startedAt {
            value += max(0, date.timeIntervalSince(startedAt))
        }
        return max(0, value)
    }

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(0, snapshot.duration - elapsed(at: date))
    }

    var isRunning: Bool { snapshot.isRunning }
    var duration: TimeInterval { snapshot.duration }
    var isFinished: Bool { snapshot.finished }

    var progress: Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(1, elapsed() / snapshot.duration)
    }

    var hasStarted: Bool { snapshot.accumulated > 0 || snapshot.isRunning || snapshot.finished }

    // MARK: - 操作

    func setDuration(_ value: TimeInterval) {
        let clamped = max(1, value)
        snapshot = CountdownSnapshot(duration: clamped,
                                     startedAt: nil,
                                     accumulated: 0,
                                     isRunning: false,
                                     finished: false)
        Feedback.tap()
        persist()
        refreshRunningSideEffects()
    }

    func start() {
        if isFinished {
            snapshot.accumulated = 0
            snapshot.finished = false
        }
        guard !snapshot.isRunning else { return }
        snapshot.startedAt = Date()
        snapshot.isRunning = true
        snapshot.finished = false
        Feedback.tap()
        persist()
        refreshRunningSideEffects()
    }

    func pause() {
        guard snapshot.isRunning else { return }
        snapshot.accumulated = elapsed()
        snapshot.startedAt = nil
        snapshot.isRunning = false
        Feedback.toggle()
        persist()
        refreshRunningSideEffects()
    }

    func resume() {
        guard !snapshot.isRunning, !isFinished else { return }
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

    /// +1 分钟这类延长操作：结束后也能顺延重开。
    func extend(by seconds: TimeInterval) {
        snapshot.duration += seconds
        if snapshot.finished {
            snapshot.finished = false
            snapshot.accumulated = min(snapshot.accumulated, snapshot.duration - 1)
        }
        persist()
        refreshRunningSideEffects()
    }

    func reset() {
        snapshot = CountdownSnapshot(duration: snapshot.duration)
        persist()
        refreshRunningSideEffects()
        Notifier.cancel("countdown")
    }

    // MARK: - 到点检查

    private func checkFinished() {
        guard snapshot.isRunning, remaining() <= 0 else { return }
        snapshot.accumulated = snapshot.duration
        snapshot.startedAt = nil
        snapshot.isRunning = false
        snapshot.finished = true
        Feedback.finished()
        persist()
        refreshRunningSideEffects()
    }

    private func refreshRunningSideEffects() {
        tickTimer?.invalidate()
        tickTimer = nil

        if snapshot.isRunning {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.checkFinished()
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer

            let remaining = remaining()
            if remaining > 0 {
                Notifier.scheduleCountdown(after: remaining)
            }
        } else {
            Notifier.cancel("countdown")
        }
    }

    private func persist() {
        SessionStore.shared.save(snapshot, key: storeKey)
    }

    func persistForBackground() {
        if snapshot.isRunning {
            snapshot.accumulated = elapsed()
            snapshot.startedAt = Date()
            persist()
            let remaining = remaining()
            if remaining > 0 {
                Notifier.scheduleCountdown(after: remaining)
            }
        } else {
            persist()
        }
    }
}
