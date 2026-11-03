import SwiftUI
import UIKit

/// 首页「收听」：状态圆环 + 粘贴框 + 播放控制 + 倍速。
///
/// 布局对应 Android `MainActivity.S()` 的 `i == 0` 分支。
struct ListenView: View {
    @EnvironmentObject private var state: AppState

    /// Android 端的 5 档：1.0 / 1.1 / 1.2 / 1.3 / 1.5
    private let speeds: [Float] = [1.0, 1.1, 1.2, 1.3, 1.5]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                statusCard
                inputCard
                controlRow
                speedCard
                volumeCard
                disclaimer
                supportEntry
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // 对应 f()：38dp 图标 + 「秒」「听」两色 + syncrozero.com
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: "ear.badge.waveform")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: -2) {
                HStack(spacing: 0) {
                    Text("秒").font(.system(size: 23, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text("听").font(.system(size: 23, weight: .bold)).foregroundStyle(Theme.accent)
                }
                Text("syncrozero.com")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if state.isLoggedIn {
                Text("已登录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceHigh, in: Capsule())
            } else {
                Button("登录") { state.showLogin = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 状态卡片

    private var statusCard: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                if state.isPlaying || !state.roomTitle.isEmpty {
                    Button {
                        Task { await state.addCurrentRoom() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("添加")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceHigh, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isBusy)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            PulseIndicator(playing: state.isPlaying,
                           badge: badgeText,
                           tint: state.isPlaying ? Theme.accent : Theme.textSecondary)

            Text(primaryStatus)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(secondaryStatus)
                .font(.system(size: 13))
                .foregroundStyle(state.isPlaying ? Theme.accent : Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var badgeText: String? {
        switch state.platformName {
        case "抖音": return "抖"
        case "快手": return "快"
        case "小红书": return "薯"
        case "淘宝": return "淘"
        default: return nil
        }
    }

    private var primaryStatus: String {
        if state.isBusy { return "正在识别直播间" }
        if state.isPlaying { return state.roomTitle.isEmpty ? "直播音频" : state.roomTitle }
        if !state.statusText.isEmpty, state.statusText != "未播放" { return state.roomTitle.isEmpty ? "直播音频" : state.roomTitle }
        return "等待识别直播间"
    }

    private var secondaryStatus: String {
        if state.isBusy { return "正在解析直播间地址" }
        if state.isPlaying { return state.statusText }
        if !state.input.isEmpty { return "粘贴链接后可再次快速播放。" }
        return "粘贴直播链接或分享文字后开始。"
    }

    // MARK: - 输入

    private var inputCard: some View {
        Card(padding: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("粘贴直播链接或整段分享文字", text: $state.input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                HStack(spacing: 8) {
                    ChipButton(title: "一键粘贴") {
                        if let text = UIPasteboard.general.string { state.input = text }
                    }
                    ChipButton(title: "清空") { state.input = "" }
                    Spacer(minLength: 0)
                    Button {
                        state.resolveAndPlay()
                    } label: {
                        HStack(spacing: 6) {
                            if state.isBusy { ProgressView().controlSize(.small).tint(.black) }
                            Text(state.isBusy ? "识别中" : "快速播放")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isBusy)
                }
            }
        }
    }

    // MARK: - 播放 / 停止

    private var controlRow: some View {
        HStack(spacing: 10) {
            Button {
                if state.isPlaying {
                    state.stop()
                } else {
                    state.resolveAndPlay()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: state.isPlaying ? "stop.fill" : "play.fill")
                    Text(state.isPlaying ? "停止播放" : "开始收听")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(state.isPlaying ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(state.isPlaying ? Theme.danger : Theme.accent,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                state.showPaywall = true
            } label: {
                VStack(spacing: 2) {
                    Text(state.hasActiveEntitlement ? "权益有效" : "套餐/权益")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(state.entitlement?.summary ?? "未开通")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(width: 104)
                .padding(.vertical, 11)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 倍速

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("播放速度")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "%.1fx", state.speed))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 6) {
                ForEach(speeds, id: \.self) { value in
                    let active = abs(state.speed - value) < 0.05
                    Button {
                        state.setSpeed(value)
                    } label: {
                        Text(value == 1.0 ? "1x" : String(format: "%.1fx", value))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(active ? Theme.accent : Color.white.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(active ? .black : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color(red: 14 / 255, green: 16 / 255, blue: 21 / 255),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 音量

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("音量")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("系统媒体音量")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            SystemVolumeSlider()
                .frame(height: 32)

            HStack(spacing: 8) {
                Text("增强")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: Binding(
                    get: { Double(state.gain) },
                    set: { state.setGain(Float($0)) }
                ), in: 1.0...4.0)
                .tint(Theme.accent)
                Text(String(format: "%.1fx", state.gain))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, alignment: .trailing)
            }

        }
        .padding(12)
        .background(Color(red: 14 / 255, green: 16 / 255, blue: 21 / 255),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 声明 / 客服

    private var disclaimer: some View {
        Text("声明：内部测试版，仅限授权测试与技术研究；请勿传播、商用或用于违规获取、传播内容。")
            .font(.system(size: 10))
            .foregroundStyle(Theme.textSecondary.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private var supportEntry: some View {
        Button {
            state.showPaywall = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("点击联系客服，加交流群")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
