//  MainView.swift
//  主界面
//
//  SwiftUI 实现，对应 Android MainActivity 的全部 UI 逻辑
//

import SwiftUI

struct MainView: View {

    @EnvironmentObject var appState: AppState
    @StateObject private var playerManager = PlayerManager()

    @State private var showSettings = false
    @State private var showHistory = false
    @State private var resolvedRoom: RoomInfo?

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color.black.opacity(0.95)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 顶部标题栏
                    headerBar

                    // 输入区
                    inputSection

                    // 状态显示
                    statusSection

                    // 播放控制
                    if playerManager.status == .playing || playerManager.status == .paused {
                        controlSection
                    }

                    // 房间信息
                    if let room = resolvedRoom {
                        roomInfoSection(room: room)
                    }

                    Spacer()

                    // 底部历史/设置按钮
                    bottomBar
                }
                .padding(.horizontal, 16)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView(appState: appState)
            }
            .sheet(isPresented: $showHistory) {
                HistoryView(appState: appState) { url in
                    appState.inputURL = url
                    startPlayback(url)
                }
            }
        }
    }

    // MARK: - 标题栏
    private var headerBar: some View {
        HStack {
            Text("秒听")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 255/255, green: 46/255, blue: 77/255), Color(red: 255/255, green: 100/255, blue: 130/255)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("v1.1.3")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Capsule())

            Spacer()

            Button(action: { showHistory = true }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - 输入区
    private var inputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))

                TextField("粘贴直播间链接或分享口令", text: $appState.inputURL)
                    .font(.system(size: 15))
                    .tint(Color(red: 255/255, green: 46/255, blue: 77/255))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit {
                        startPlayback(appState.inputURL)
                    }

                if !appState.inputURL.isEmpty {
                    Button(action: { appState.inputURL = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                // 粘贴按钮
                Button(action: pasteFromClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13))
                        Text("粘贴")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }

                // 识别按钮
                Button(action: { startPlayback(appState.inputURL) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 15))
                        Text("识别并播放")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 255/255, green: 46/255, blue: 77/255), Color(red: 255/255, green: 80/255, blue: 100/255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .disabled(appState.inputURL.isEmpty || playerManager.status == .connecting)

                Spacer()

                // 停止按钮
                if playerManager.status == .playing || playerManager.status == .paused || playerManager.status == .connecting {
                    Button(action: stopPlayback) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 15))
                            Text("停止")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Color(red: 255/255, green: 80/255, blue: 80/255))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(red: 255/255, green: 80/255, blue: 80/255).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 状态显示
    private var statusSection: some View {
        HStack(spacing: 10) {
            // 状态指示灯
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.5), radius: 4)

            Text(playerManager.statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(2)

            Spacer()

            // 旋转动画（连接中）
            if playerManager.status == .connecting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
                    .tint(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 12)
    }

    private var statusColor: Color {
        switch playerManager.status {
        case .playing: return Color.green
        case .connecting: return Color.orange
        case .paused: return Color.yellow
        case .error: return Color.red
        default: return Color.gray
        }
    }

    // MARK: - 播放控制
    private var controlSection: some View {
        VStack(spacing: 12) {
            // 变速控制
            HStack(spacing: 8) {
                Text("倍速")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                ForEach([Float(1.0), 1.5, 2.0, 3.0], id: \.self) { speed in
                    Button(action: { playerManager.setSpeed(speed) }) {
                        Text(String(format: "%.1fx", speed))
                            .font(.system(size: 13, weight: playerManager.playbackSpeed == speed ? .bold : .medium))
                            .foregroundColor(playerManager.playbackSpeed == speed ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                playerManager.playbackSpeed == speed ?
                                Color(red: 255/255, green: 46/255, blue: 77/255) :
                                Color.white.opacity(0.08)
                            )
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // 暂停/恢复
                Button(action: {
                    if playerManager.status == .playing {
                        playerManager.pause()
                    } else if playerManager.status == .paused {
                        playerManager.resume()
                    }
                }) {
                    Image(systemName: playerManager.status == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(red: 255/255, green: 46/255, blue: 77/255))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 12)
    }

    // MARK: - 房间信息
    private func roomInfoSection(room: RoomInfo) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // 平台标识
                Text(room.platform.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(room.platform.color)
                    .clipShape(Capsule())

                // 房间标题
                Text(room.roomTitle.isEmpty ? room.platform.rawValue : room.roomTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer()
            }

            // 流地址列表
            if room.streamURLs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(room.streamURLs.enumerated()), id: \.element.id) { index, stream in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(stream.playable ? Color.green : Color.gray)
                                    .frame(width: 5, height: 5)
                                Text(stream.protocolLabel)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 12)
    }

    // MARK: - 底部栏
    private var bottomBar: some View {
        HStack {
            Text("支持: 小红书 / 抖音 / 快手 / 淘宝")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))

            Spacer()

            Text("syncrozero.com")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.bottom, 8)
    }

    // MARK: - 操作
    private func startPlayback(_ input: String) {
        guard !input.isEmpty else { return }
        playerManager.onRoomResolved = { room in
            resolvedRoom = room
            if !room.roomTitle.isEmpty {
                appState.addToHistory(url: input, title: room.roomTitle)
            }
        }
        playerManager.resolveAndPlay(url: input, token: appState.apiToken)
    }

    private func stopPlayback() {
        playerManager.cancel()
        resolvedRoom = nil
        appState.reset()
    }

    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            appState.inputURL = cleaned
        }
    }
}

// MARK: - 设置视图
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("API Token") {
                    SecureField("Token (Bearer)", text: $appState.apiToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Text("用于 syncrozero.com API 认证。留空则匿名访问。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.1.3 (113)")
                    LabeledContent("平台", value: "iOS")
                    LabeledContent("后端", value: "syncrozero.com")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 历史记录视图
struct HistoryView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    var onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                if appState.history.isEmpty {
                    Text("暂无历史记录")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                } else {
                    ForEach(appState.history) { entry in
                        Button(action: {
                            onSelect(entry.url)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(entry.url)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)

                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.03))
                    }
                    .onDelete { offsets in
                        appState.history.remove(atOffsets: offsets)
                    }
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if !appState.history.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("清空") {
                            appState.clearHistory()
                        }
                    }
                }
            }
        }
    }
}
