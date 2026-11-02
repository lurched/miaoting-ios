import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var pulse = false
    @State private var showRooms = true

    private let speeds: [Float] = [1.0, 1.2, 1.3, 1.5, 1.8, 2.0]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                nowPlayingCard
                inputCard
                controlCard
                speedCard
                roomsCard
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("秒听")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("直播抢货伴侣")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if state.isLoggedIn {
                Text(state.user?.display ?? "已登录")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceHigh, in: Capsule())
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Button("登录") { state.showLogin = true }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 当前直播间

    private var nowPlayingCard: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Theme.accent.opacity(0.35), lineWidth: 2)
                        .frame(width: 54, height: 54)
                        .scaleEffect(state.isPlaying ? (pulse ? 1.06 : 0.96) : 1)
                    Circle()
                        .fill(state.isPlaying ? Theme.accent : Theme.textSecondary.opacity(0.4))
                        .frame(width: 30, height: 30)
                    if let badge = platformBadge, !state.isPlaying {
                        Text(badge)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.roomTitle.isEmpty ? "直播音频" : state.roomTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(state.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(state.isPlaying ? Theme.accent : Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var platformBadge: String? {
        switch state.platformName {
        case "抖音": return "抖"
        case "快手": return "快"
        case "小红书": return "薯"
        case "淘宝": return "淘"
        default: return nil
        }
    }

    // MARK: - 输入

    private var inputCard: some View {
        Card(padding: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(Theme.textSecondary)
                    TextField("粘贴直播链接或整段分享文字", text: $state.input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                HStack(spacing: 10) {
                    Button("一键粘贴") {
                        if let text = UIPasteboard.general.string { state.input = text }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)

                    Button("清空") { state.input = "" }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    Button {
                        state.resolveAndPlay()
                    } label: {
                        HStack(spacing: 6) {
                            if state.isBusy { ProgressView().controlSize(.small).tint(.black) }
                            Text(state.isBusy ? "识别中" : "快速播放")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .frame(width: 132)
                    .disabled(state.isBusy)
                }
            }
        }
    }

    // MARK: - 播放控制

    private var controlCard: some View {
        Card {
            HStack(spacing: 12) {
                Button {
                    state.togglePlay()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: state.isPlaying ? "stop.fill" : "play.fill")
                        Text(state.isPlaying ? "停止播放" : "开始收听")
                    }
                }
                .buttonStyle(PillButtonStyle(fill: state.isPlaying ? Theme.danger : Theme.accent,
                                             foreground: state.isPlaying ? .white : .black))

                Button {
                    state.showPaywall = true
                } label: {
                    VStack(spacing: 2) {
                        Text(state.hasActiveEntitlement ? "权益有效" : "开通会员")
                            .font(.system(size: 13, weight: .semibold))
                        Text(state.entitlement?.summary ?? "未开通")
                            .font(.system(size: 10))
                            .opacity(0.7)
                    }
                }
                .buttonStyle(PillButtonStyle(fill: Theme.surfaceHigh, foreground: Theme.textPrimary))
                .frame(width: 118)
            }
        }
    }

    // MARK: - 倍速

    private var speedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("播放速度")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Toggle("保持音调", isOn: Binding(
                        get: { state.preservesPitch },
                        set: { state.setPreservesPitch($0) }
                    ))
                    .labelsHidden()
                    .tint(Theme.accent)
                    .scaleEffect(0.8)
                }
                HStack(spacing: 8) {
                    ForEach(speeds, id: \.self) { value in
                        Button {
                            state.setSpeed(value)
                        } label: {
                            Text(String(format: "%.1fx", value))
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(abs(state.speed - value) < 0.01 ? Theme.accent : Theme.surfaceHigh,
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .foregroundStyle(abs(state.speed - value) < 0.01 ? .black : Theme.textPrimary)
                        }
                    }
                }
                Text(state.preservesPitch
                     ? "保持音调：用 TimePitch 拉伸，加速不变声。"
                     : "变调模式：用 Varispeed 重采样，和安卓端手写插值一致。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - 我的直播间

    private var roomsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的直播间")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Menu {
                    ForEach(AppState.SortMode.allCases) { mode in
                        Button(mode.rawValue) { state.sortMode = mode }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(state.sortMode.rawValue)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            if state.sortedRooms.isEmpty {
                Card {
                    Text("还没有收藏的直播间，识别成功后点「收藏」即可加入。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(state.sortedRooms) { room in
                        roomRow(room)
                    }
                }
            }
        }
    }

    private func roomRow(_ room: Room) -> some View {
        Button {
            state.resolveAndPlay(room.roomUrl)
        } label: {
            HStack(spacing: 12) {
                Text(room.platformBadge)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(room.platformName) · \(room.likeCount) 人收藏")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if room.ownedByCurrentUser {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .onTapGesture { Task { await state.deleteRoom(room) } }
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底栏

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button("用户协议") { state.openLegal(.terms) }
                Button("隐私政策") { state.openLegal(.privacy) }
                if state.isLoggedIn {
                    Button("退出登录") { Task { await state.logout() } }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)

            if PatchFlags.bypassEntitlementGate {
                Text("本地补丁：权益门禁已放开（对应 MainActivity.B()）")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.danger.opacity(0.8))
            }

            Text("秒听 \(AppVersion.name) · 仅供本地测试")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(.top, 12)
    }
}
