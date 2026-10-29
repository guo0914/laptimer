import SwiftUI

/// App 入口。正计时 / 倒计时切换放在根视图，
/// 两个引擎都由 App 持有，切模式不会丢状态。
@main
struct LapTimerApp: App {
    @StateObject private var stopwatch = StopwatchEngine()
    @StateObject private var countdown = CountdownEngine()
    @StateObject private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView(stopwatch: stopwatch, countdown: countdown, history: history)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    @ObservedObject var stopwatch: StopwatchEngine
    @ObservedObject var countdown: CountdownEngine
    @ObservedObject var history: HistoryStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: TimerMode = .stopwatch
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ZStack {
                GlowBackground(tint: mode == .stopwatch ? Palette.accent : Palette.warn)

                Group {
                    switch mode {
                    case .stopwatch:
                        StopwatchView(engine: stopwatch, history: history)
                    case .countdown:
                        CountdownView(engine: countdown)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ModeSegmentedControl(selection: $mode)
                        .frame(width: 220)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHistory = true
                        Feedback.tap()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .accessibilityLabel("历史记录")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) {
                HistoryView(store: history)
            }
        }
        .onAppear {
            Notifier.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                stopwatch.persistForBackground()
                countdown.persistForBackground()
            case .active:
                // 回到前台立刻按真实时钟重算，避免挂起造成的显示漂移
                stopwatch.objectWillChange.send()
                countdown.objectWillChange.send()
            @unknown default:
                break
            }
        }
    }
}
