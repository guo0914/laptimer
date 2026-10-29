import SwiftUI

/// 限时设置：可直接键盘输入时长，也保留常用预设。
///
/// 支持的输入写法：
///   `30`      30 分钟（纯数字默认按分钟）
///   `30:00`   30 分钟
///   `1:30`    1 分 30 秒
///   `1:30:00` 1 小时 30 分
///   `90s` `90秒` `2h` `2小时` 等带单位的写法
struct LimitSheet: View {
    let current: TimeInterval?
    let onApply: (TimeInterval?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @FocusState private var isInputFocused: Bool

    private static let presets: [Int] = [5, 10, 15, 20, 30, 45, 60, 90]

    init(current: TimeInterval?, onApply: @escaping (TimeInterval?) -> Void) {
        self.current = current
        self.onApply = onApply
        _input = State(initialValue: current.map { TimeText.durationInputText($0) } ?? "")
    }

    /// 当前输入解析出的秒数；nil 表示无法识别或为空。
    private var parsed: TimeInterval? {
        guard let value = TimeText.parseDuration(input), value > 0 else { return nil }
        return value
    }

    private var isValid: Bool { parsed != nil }

    /// 输入是否刚好等于某个预设（用于高亮预设按钮）。
    private var matchedPreset: Int? {
        guard let parsed else { return nil }
        return Self.presets.first { TimeInterval($0 * 60) == parsed }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inputSection
                    presetSection
                    hintSection
                    if current != nil { clearSection }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("限时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("设置") {
                        guard let parsed else { return }
                        onApply(parsed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                // 没设置过限时就默认聚焦，方便直接敲数字
                if current == nil { isInputFocused = true }
            }
        }
    }

    // MARK: - 键盘输入

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("输入时长")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("如 30、1:30、2:00:00", text: $input)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if isValid { applyAndClose() } }
                    .focused($isInputFocused)
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )

                if !input.isEmpty {
                    Button {
                        input = ""
                        isInputFocused = true
                        Feedback.tap()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空")
                }
            }

            // 解析结果反馈
            Group {
                if input.isEmpty {
                    Text("纯数字按分钟计算，也可写 1:30 或 90s")
                        .foregroundStyle(.tertiary)
                } else if let parsed {
                    Label("= \(TimeText.clock(parsed))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Label("无法识别，试试 30、1:30 或 90s", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .animation(.easeOut(duration: 0.15), value: input)
        }
    }

    private var borderColor: Color {
        if input.isEmpty { return Color.gray.opacity(0.25) }
        return isValid ? Color.accentColor.opacity(0.6) : Color.orange.opacity(0.6)
    }

    // MARK: - 预设

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常用")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(Self.presets, id: \.self) { value in
                    presetButton(value)
                }
            }
        }
    }

    private func presetButton(_ value: Int) -> some View {
        let selected = matchedPreset == value
        return Button {
            input = "\(value)"
            isInputFocused = false
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
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - 说明与清除

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("到达时限时只提醒、不打断计时，你可以继续分段或手动结束。")
            Text("支持写法：30 ＝ 30 分钟 · 1:30 ＝ 1 分 30 秒 · 1:30:00 ＝ 1 小时 30 分 · 90s ＝ 90 秒 · 2h ＝ 2 小时")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
    }

    private var clearSection: some View {
        Button(role: .destructive) {
            onApply(nil)
            dismiss()
        } label: {
            Text("清除限时").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func applyAndClose() {
        guard let parsed else { return }
        onApply(parsed)
        dismiss()
    }
}
