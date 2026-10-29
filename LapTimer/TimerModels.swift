import Foundation

struct LapRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var index: Int
    var split: TimeInterval
    var total: TimeInterval
    var recordedAt: Date
}

struct SavedSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date
    var total: TimeInterval
    var limit: TimeInterval?
    var laps: [LapRecord]

    var averageSplit: TimeInterval? {
        guard !laps.isEmpty else { return nil }
        return laps.reduce(0) { $0 + $1.split } / Double(laps.count)
    }

    var fastestLap: LapRecord? {
        laps.min { $0.split < $1.split }
    }
}

/// 落盘用的正计时快照。运行中用「累计时长 + 开始时刻」表达，
/// 因此杀掉进程后重新打开也能续上正确进度。
struct StopwatchSnapshot: Codable {
    var startedAt: Date?
    var accumulated: TimeInterval = 0
    var isRunning: Bool = false
    var laps: [LapRecord] = []
    var limit: TimeInterval?
    var limitAlerted: Bool = false
    var sessionStart: Date?
    var pauseCount: Int = 0
}

struct CountdownSnapshot: Codable {
    var duration: TimeInterval = 300
    var startedAt: Date?
    var accumulated: TimeInterval = 0
    var isRunning: Bool = false
    var finished: Bool = false
}
