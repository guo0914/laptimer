import SwiftUI

/// 限时设置：常用预设 + 自定义分钟数。
struct LimitSheet: View {
    let current: TimeInterval?
    let onApply: (TimeInterval?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var useCustom: Bool

    private static let presets: [Int] = [5, 10, 15, 20, 30, 45, 60, 90]

    init(current: TimeInterval?, onApply: @escaping (TimeInterval?) -> Void) {
        self.current = current
        self.onApply = onApply
        let currentMinutes = current.map { Int($0 / 60) } ?? 0
        _minutes = State(initialValue: currentMinutes)
        _useCustom = State(initialValue: currentMinutes > 0 && !Self.presets.contains(currentMinutes))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("到达时限时只提醒、不打断计时，你可以继续分段或手动结束。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                              spacing: 10) {
                        ForEach(Self.presets, id: \.self) { value in
                            presetButton(value)
                        }
                    }

                    Stepper(value: $minutes, in: 1...600, step: 1) {
                        HStack {
                            Text("自定义")
                            Spacer()
                            Text(minutes > 0 ? "\(minutes) 分钟" : "未设置")
                                .monospacedDigit()
                                .foregroundStyle(minutes > 0 ? .primary : .secondary)
                        }
                    }
                    .onChange(of: minutes) { _, newValue in
                        useCustom = !Self.presets.contains(newValue)
                    }

                    if current != nil {
                        Button(role: .destructive) {
                            onApply(nil)
                            dismiss()
                        } label: {
                            Text("清除限时").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("限时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("设置") {
                        onApply(minutes > 0 ? TimeInterval(minutes * 60) : nil)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(minutes <= 0)
                }
            }
        }
    }

    private func presetButton(_ value: Int) -> some View {
        let selected = !useCustom && minutes == value
        return Button {
            minutes = value
            useCustom = false
            Feedback.tap()
        } label: {
            Text("\(value)′")
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
