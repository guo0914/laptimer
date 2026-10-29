import SwiftUI

/// 历史记录：每次结束的正计时会话，含分段明细与分享导出。
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView("还没有记录",
                                           systemImage: "clock.badge.questionmark",
                                           description: Text("结束一次正计时后，分段会保存在这里。"))
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                row(session)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.remove(store.sessions[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(_ session: SavedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(TimeText.clock(session.total))
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text("\(session.laps.count) 段")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(TimeText.stamp(session.startedAt))
                if let limit = session.limit {
                    Text("限时 " + TimeText.clock(limit))
                }
                if let fastest = session.fastestLap {
                    Text("最快 " + TimeText.lap(fastest.split))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 明细

struct SessionDetailView: View {
    let session: SavedSession

    private var summaryText: String {
        var lines: [String] = []
        lines.append("总计 \(TimeText.clock(session.total))")
        if let limit = session.limit {
            lines.append("限时 \(TimeText.clock(limit))")
        }
        if let average = session.averageSplit {
            lines.append("平均分段 \(TimeText.lap(average))")
        }
        lines.append("共 \(session.laps.count) 段")
        lines.append("开始 \(TimeText.stamp(session.startedAt))")
        lines.append("结束 \(TimeText.stamp(session.endedAt))")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TimeText.clock(session.total))
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("分段") {
                ForEach(session.laps) { lap in
                    HStack {
                        Text(String(format: "%02d", lap.index))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        Text(TimeText.lap(lap.split))
                            .font(.system(size: 17, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Text(TimeText.lap(lap.total))
                            .font(.system(size: 12, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ShareLink(item: exportText) {
                    Label("分享分段表", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(TimeText.stamp(session.startedAt))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var exportText: String {
        var lines = ["计时记录 \(TimeText.stamp(session.startedAt))", summaryText, "", "段次\t本段\t累计"]
        for lap in session.laps {
            lines.append("\(lap.index)\t\(TimeText.lap(lap.split))\t\(TimeText.lap(lap.total))")
        }
        return lines.joined(separator: "\n")
    }
}
