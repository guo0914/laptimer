import SwiftUI

// MARK: - 背景

/// 深色渐变 + 顶部一层对焦光斑，对应方案 A 的「驾驶舱」氛围。
struct GlowBackground: View {
    var tint: Color = Palette.accent

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Palette.backgroundTop, Palette.background],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.55)
            )

            RadialGradient(
                colors: [tint.opacity(0.16), tint.opacity(0.05), .clear],
                center: .init(x: 0.5, y: 0.12),
                startRadius: 8,
                endRadius: 320
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 分段控件

struct ModeSegmentedControl: View {
    @Binding var selection: TimerMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TimerMode.allCases, id: \.self) { mode in
                let isSelected = mode == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.easeOut(duration: 0.18)) { selection = mode }
                    Feedback.tap()
                } label: {
                    Text(mode.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Palette.accentInk : Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Palette.accentGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - 主时间

struct BigTimeDisplay: View {
    let parts: TimeText.Parts
    var dimmed: Bool = false
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.main)
                .font(.system(size: 72, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint ?? Color.white)
                .shadow(color: (tint ?? .white).opacity(0.18), radius: 18, y: 2)
            Text("." + parts.fraction)
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryText)
        }
        .opacity(dimmed ? 0.55 : 1)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(parts.main).\(parts.fraction)")
    }
}

// MARK: - 限时进度

struct LimitProgressView: View {
    let used: String
    let remainingText: String
    let progress: Double
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("限时")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                Text(used)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.primaryText)
                Spacer(minLength: 8)
                Text(remainingText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isOver ? Palette.danger : Palette.warn)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(isOver
                              ? AnyShapeStyle(Palette.danger)
                              : AnyShapeStyle(LinearGradient(colors: [Palette.accent, Palette.warn],
                                                             startPoint: .leading,
                                                             endPoint: .trailing)))
                        .frame(width: max(0, proxy.size.width * CGFloat(min(1, progress))))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 按钮

/// 圆形的次级按钮（停止 / 暂停 / 继续）。
struct SecondaryCircleButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Palette.secondaryText
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13))
            }
            .foregroundStyle(isEnabled ? tint : Palette.quaternaryText)
            .frame(width: 72, height: 72)
            .background(
                Circle()
                    .fill(Color.white.opacity(isEnabled ? 0.07 : 0.035))
                    .overlay(Circle().stroke(Color.white.opacity(0.09), lineWidth: 1))
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
    }
}

/// 中间的主按钮（开始 / 记段）。
struct PrimaryCircleButton: View {
    let title: String
    var tint: Color = Palette.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accentInk)
                .frame(width: 88, height: 88)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [Palette.accentLight, tint],
                                             startPoint: .top,
                                             endPoint: .bottom))
                )
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: tint.opacity(0.45), radius: 22, y: 10)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 胶囊小按钮

struct CapsuleChip: View {
    let title: String
    var isSelected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Palette.accent : Palette.tertiaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Palette.accent.opacity(0.16) : Color.white.opacity(0.05))
                        .overlay(
                            Capsule().stroke(isSelected
                                             ? Palette.accent.opacity(0.5)
                                             : Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
