import SwiftUI

/// 方案 A 的核心界面：一屏看完「限时进度 + 主时间 + 分段表 + 三键」。
struct StopwatchView: View {
    @ObservedObject var engine: StopwatchEngine
    @ObservedObject var history: HistoryStore

    @State private var showLimitSheet = false
    @State private var showFinishConfirm = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            limitSection
            timeSection
            lapSection
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .overlay(alignment: .top) { toastView }
        .sheet(isPresented: $showLimitSheet) {
            LimitSheet(current: engine.limit) { newValue in
                engine.setLimit(newValue)
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("结束这次计时？",
                            isPresented: $showFinishConfirm,
                            titleVisibility: .visible) {
            Button("结束并保存记录") { finishAndSave() }
            Button("直接丢弃", role: .destructive) {
                engine.discard()
                showToast("已丢弃")
            }
            Button("继续计时", role: .cancel) {}
        } message: {
            Text("结束后会把这次的分段保存到「记录」里。")
        }
    }

    // MARK: - 限时

    @ViewBuilder
    private var limitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let limit = engine.limit {
                TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: !engine.isRunning)) { context in
                    let elapsed = engine.elapsed(at: context.date)
                    let over = elapsed >= limit
                    LimitProgressView(
                        used: TimeText.clock(min(elapsed, limit)) + " / " + TimeText.clock(limit),
                        remainingText: over
                            ? "已超时 " + TimeText.clock(elapsed - limit)
                            : "剩余 " + TimeText.clock(limit - elapsed),
                        progress: limit > 0 ? min(1, elapsed / limit) : 0,
                        isOver: over
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showLimitSheet = true
                    Feedback.tap()
                }
                .accessibilityHint("轻点修改限时")
            } else {
                Button {
                    showLimitSheet = true
                    Feedback.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                        Text("设置限时")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: - 主时间

    private var timeSection: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.isRunning)) { context in
                BigTimeDisplay(parts: TimeText.stopwatchParts(engine.elapsed(at: context.date)))
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
            }

            Text(subtitleText)
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiaryText)
                .monospacedDigit()
        }
        .padding(.top, 12)
        .padding(.horizontal, 22)
    }

    private var subtitleText: String {
        guard let start = engine.snapshot.sessionStart else {
            if let limit = engine.limit {
                return "限时 \(TimeText.clock(limit)) · 点「开始」计时，随时可记段"
            }
            return "点「开始」计时，随时可记段"
        }
        let startText = TimeText.clockTime(start)
        if engine.isRunning {
            return "\(startText) 开始 · 第 \(engine.laps.count + 1) 段进行中"
        }
        return "\(startText) 开始 · 已暂停 · 共 \(engine.laps.count) 段"
    }

    // MARK: - 分段表

    private var lapSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("段次").frame(width: 40, alignment: .leading)
                Text("本段").frame(maxWidth: .infinity, alignment: .leading)
                Text("累计").frame(width: 76, alignment: .trailing)
                Text("对比").frame(width: 52, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundStyle(Palette.quaternaryText)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 6)

            if engine.laps.isEmpty && !engine.hasSession {
                placeholderLaps
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if engine.hasSession {
                                LiveLapRow(engine: engine)
                                    .id("live")
                            }
                            ForEach(engine.laps.reversed()) { lap in
                                LapRow(
                                    lap: lap,
                                    delta: engine.delta(for: lap),
                                    isFastest: lap.id == engine.fastestLapID
                                )
                                .id(lap.id)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .onChange(of: engine.laps.count) { _, _ in
                        guard let lastID = engine.laps.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(lastID, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var placeholderLaps: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag")
                .font(.system(size: 24))
                .foregroundStyle(Palette.quaternaryText)
            Text("还没有分段")
                .font(.system(size: 13))
                .foregroundStyle(Palette.tertiaryText)
            Text("开始后点「记段」，每段用时与累计会记在这里。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.quaternaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - 底部三键

    private var controls: some View {
        HStack {
            SecondaryCircleButton(
                title: engine.hasSession ? "结束" : "重置",
                systemImage: engine.hasSession ? "stop.fill" : "arrow.counterclockwise",
                isEnabled: engine.hasSession || engine.hasAccumulated
            ) {
                if engine.hasSession {
                    showFinishConfirm = true
                } else {
                    engine.discard()
                    showToast("已重置")
                }
            }

            Spacer()

            if engine.hasSession {
                PrimaryCircleButton(title: "记段") { engine.addLap() }
                    .contextMenu {
                        Button(role: .destructive) {
                            engine.deleteLastLap()
                            showToast("已撤销最近一段")
                        } label: {
                            Label("撤销最近一段", systemImage: "arrow.uturn.backward")
                        }
                    }
            } else {
                PrimaryCircleButton(title: "开始") { engine.start() }
            }

            Spacer()

            if engine.hasSession {
                SecondaryCircleButton(
                    title: engine.isRunning ? "暂停" : "继续",
                    systemImage: engine.isRunning ? "pause.fill" : "play.fill",
                    tint: engine.isRunning ? Palette.accentLight : Palette.warn
                ) {
                    engine.togglePause()
                }
            } else {
                SecondaryCircleButton(title: "限时", systemImage: "timer") {
                    showLimitSheet = true
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [Palette.background.opacity(0), Palette.background.opacity(0.92)],
                           startPoint: .top,
                           endPoint: .bottom)
        )
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.4), lineWidth: 1))
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func finishAndSave() {
        if let session = engine.finish() {
            history.add(session)
            showToast("已保存 \(session.laps.count) 段")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }
}

// MARK: - 分段行

struct LapRow: View {
    let lap: LapRecord
    let delta: TimeInterval?
    let isFastest: Bool

    private var deltaText: String {
        guard let delta else { return "—" }
        return isFastest ? "最快" : TimeText.delta(delta)
    }

    private var deltaColor: Color {
        guard let delta else { return Palette.quaternaryText }
        if isFastest { return Palette.accent }
        if delta > 1 { return Palette.danger }
        if delta < -1 { return Palette.accent.opacity(0.85) }
        return Palette.tertiaryText
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(String(format: "%02d", lap.index))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.quaternaryText)
                .frame(width: 40, alignment: .leading)

            Text(TimeText.lap(lap.split))
                .font(.system(size: 18, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isFastest ? Palette.accentLight : Palette.primaryText.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(TimeText.lap(lap.total))
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryText)
                .frame(width: 76, alignment: .trailing)

            Text(deltaText)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(deltaColor)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background {
            if isFastest {
                LinearGradient(colors: [Palette.accent.opacity(0.12), .clear],
                               startPoint: .leading,
                               endPoint: .trailing)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 进行中那一段：本段用时随时间跳，后面标「进行中」。
struct LiveLapRow: View {
    @ObservedObject var engine: StopwatchEngine

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !engine.isRunning)) { context in
            let live = engine.liveSplit(at: context.date)
            HStack(spacing: 0) {
                Text(String(format: "%02d", engine.laps.count + 1))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.quaternaryText)
                    .frame(width: 40, alignment: .leading)

                Text(TimeText.lap(live))
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(engine.isRunning ? "进行中" : "已暂停")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.quaternaryText)
                    .frame(width: 76, alignment: .trailing)

                Text("—")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.quaternaryText)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
    }
}
