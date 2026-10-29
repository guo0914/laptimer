import SwiftUI

/// 倒计时：常规功能（预设时长、开始/暂停/继续/重置、+1 分钟、到点提醒）。
struct CountdownView: View {
    @ObservedObject var engine: CountdownEngine

    @State private var showCustomSheet = false

    private static let presets: [Int] = [1, 3, 5, 10, 15, 25, 45, 60]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            ringSection
            if !engine.hasStarted { presetGrid }
            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .sheet(isPresented: $showCustomSheet) {
            DurationSheet(initialMinutes: max(1, Int(engine.duration / 60))) { minutes in
                engine.setDuration(TimeInterval(minutes * 60))
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 环

    private var ringSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: CGFloat(engine.progress))
                    .stroke(
                        engine.isFinished
                            ? AnyShapeStyle(Palette.danger)
                            : AnyShapeStyle(LinearGradient(colors: [Palette.accentLight, Palette.accent, Palette.warn],
                                                           startPoint: .topLeading,
                                                           endPoint: .bottomTrailing)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.15), value: engine.progress)

                VStack(spacing: 8) {
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                        .tracking(1.5)

                    TimelineView(.animation(minimumInterval: 0.05, paused: !engine.isRunning)) { context in
                        Text(TimeText.countdown(engine.remaining(at: context.date)))
                            .font(.system(size: 54, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(engine.isFinished ? Palette.danger : Palette.primaryText)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }

                    Text("时长 " + TimeText.clock(engine.duration))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.quaternaryText)
                }
            }
            .frame(width: 268, height: 268)
            .padding(.top, 6)
        }
    }

    private var statusLabel: String {
        if engine.isFinished { return "已结束" }
        if engine.isRunning { return "倒计时中" }
        if engine.hasStarted { return "已暂停" }
        return "准备就绪"
    }

    // MARK: - 预设

    private var presetGrid: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 8) {
                ForEach(Self.presets, id: \.self) { value in
                    let selected = Int(engine.duration / 60) == value
                    Button {
                        engine.setDuration(TimeInterval(value * 60))
                        Feedback.tap()
                    } label: {
                        Text("\(value)′")
                            .font(.system(size: 14, weight: selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(selected ? Palette.accent.opacity(0.18) : Color.white.opacity(0.05))
                                    .overlay(Capsule().stroke(selected ? Palette.accent.opacity(0.55)
                                                                       : Color.white.opacity(0.08), lineWidth: 1))
                            )
                            .foregroundStyle(selected ? Palette.accent : Palette.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                showCustomSheet = true
                Feedback.tap()
            } label: {
                Text("自定义时长")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
    }

    // MARK: - 控制

    private var controls: some View {
        HStack {
            SecondaryCircleButton(title: engine.hasStarted ? "重置" : "自定义",
                                  systemImage: engine.hasStarted ? "arrow.counterclockwise" : "slider.horizontal.3",
                                  tint: Palette.secondaryText,
                                  isEnabled: true) {
                if engine.hasStarted { engine.reset() } else { showCustomSheet = true }
            }

            Spacer()

            if !engine.isRunning {
                PrimaryCircleButton(title: engine.isFinished ? "再来" : (engine.hasStarted ? "继续" : "开始")) {
                    if engine.isFinished {
                        engine.reset()
                        engine.start()
                    } else if engine.hasStarted {
                        engine.resume()
                    } else {
                        engine.start()
                    }
                }
            } else {
                PrimaryCircleButton(title: "暂停") { engine.pause() }
            }

            Spacer()

            SecondaryCircleButton(title: "+1′", systemImage: "plus", tint: Palette.warn) {
                engine.extend(by: 60)
            }
            .opacity(engine.isRunning || engine.hasStarted ? 1 : 0.4)
            .disabled(!(engine.isRunning || engine.hasStarted))
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .padding(.top, 10)
    }
}

// MARK: - 自定义时长

struct DurationSheet: View {
    let initialMinutes: Int
    let onApply: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int

    init(initialMinutes: Int, onApply: @escaping (Int) -> Void) {
        self.initialMinutes = initialMinutes
        self.onApply = onApply
        _minutes = State(initialValue: max(1, initialMinutes))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    TextField("分钟", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 140)
                    Text("分钟")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                Stepper("", value: $minutes, in: 1...600, step: 1)
                    .labelsHidden()

                Spacer()
            }
            .navigationTitle("自定义时长")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onApply(max(1, minutes))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
