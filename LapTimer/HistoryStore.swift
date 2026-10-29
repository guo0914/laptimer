import Foundation
import Combine

/// 历史记录存储。用「内存数组 + JSON 落盘」，最多保留 200 条。
/// 只在主线程读写（由界面驱动）。
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [SavedSession] = []

    private let storeKey = "history"
    private let limit = 200

    init() {
        sessions = SessionStore.shared.load([SavedSession].self, key: storeKey) ?? []
    }

    func add(_ session: SavedSession) {
        sessions.insert(session, at: 0)
        if sessions.count > limit {
            sessions.removeLast(sessions.count - limit)
        }
        persist()
    }

    func remove(_ session: SavedSession) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    func removeAll() {
        sessions.removeAll()
        persist()
    }

    private func persist() {
        SessionStore.shared.save(sessions, key: storeKey)
    }
}
