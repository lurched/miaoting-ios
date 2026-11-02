import SwiftUI

/// 直播间状态圆环，对应 Android 端 `LN`（自定义 View 的 onDraw）。
///
/// 三层同心圆 + 播放时的呼吸波动；停止时中心显示平台字（抖/快/薯/淘），
/// 播放时显示 5 根律动的柱子。
struct PulseIndicator: View {
    let playing: Bool
    let badge: String?
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            ZStack {
                // 外圈：sin 波动
                Circle()
                    .stroke(tint.opacity(0.32), lineWidth: 2)
                    .frame(width: 110, height: 110)
                    .scaleEffect(playing ? 1 + 0.02 * sin(t * 2.2) : 1)

                // 中圈：cos 波动
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(playing ? 1 + 0.03 * cos(t * 2.2) : 1)

                // 蕊
                Circle()
                    .fill(tint)
                    .frame(width: 56, height: 56)

                if playing {
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            let h = 10 + 16 * (0.5 + 0.5 * sin(t * 4 + Double(index) * 0.9))
                            Capsule()
                                .fill(Color.black.opacity(0.85))
                                .frame(width: 4, height: h)
                        }
                    }
                } else if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 132, height: 132)
        }
    }
}

/// 小标题 + 说明的区块头（右侧控件由调用方自己拼）。
struct SectionHead: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 账号页的「标签 / 值」行。
struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    var wide: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
    }
}

/// 胶囊/方块小按钮。
struct ChipButton: View {
    let title: String
    var filled: Bool = false
    var tint: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? .black : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(filled ? tint : Theme.surfaceHigh,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}
