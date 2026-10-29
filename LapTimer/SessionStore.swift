import Foundation

/// 极简 JSON 落盘，写 Application Support/CountUpTimer 目录。
/// 原子写入，避免崩溃时留下半个文件。
///
/// `baseDirectoryOverride` 供自动化测试把落盘目录指到可写位置，
/// App 运行时保持 nil，走正常的 Application Support。
final class SessionStore {
    static var baseDirectoryOverride: URL?

    static let shared = SessionStore()

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let base = Self.baseDirectoryOverride
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("CountUpTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    private func url(for key: String) -> URL {
        directory.appendingPathComponent(key + ".json")
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    func save<T: Encodable>(_ value: T, key: String) -> Bool {
        guard let data = try? encoder.encode(value) else { return false }
        do {
            try data.write(to: url(for: key), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// 落盘目录是否真的可用（自动化测试用来确认环境）。
    var isWritable: Bool {
        let probe = directory.appendingPathComponent("probe.tmp")
        guard (try? Data("ok".utf8).write(to: probe)) != nil else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }
}
