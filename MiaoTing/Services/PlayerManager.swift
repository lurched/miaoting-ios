//  PlayerManager.swift
//  播放管理器
//
//  整合 API 解析 + 流客户端 + 音频引擎
//  对应 Android PlayerService 的完整逻辑
//

import Foundation
import Combine

class PlayerManager: ObservableObject, @unchecked Sendable {

    @Published var status: PlayerStatus = .idle
    @Published var statusText: String = "等待输入"
    @Published var playbackSpeed: Float = 1.0

    private let apiClient = APIClient.shared
    private var streamClient: StreamClient?
    private var audioEngine: AudioEngine?
    private var currentRoom: RoomInfo?
    private var currentStreamIndex: Int = 0
    private var streamFallbackTask: Task<Void, Never>?

    // 回调给 UI
    var onRoomResolved: ((RoomInfo) -> Void)?

    // MARK: - 解析并播放
    func resolveAndPlay(url: String, token: String) {
        cancel()
        status = .connecting
        statusText = "正在解析直播地址..."

        streamFallbackTask = Task {
            do {
                let room = try await apiClient.resolveLiveURL(url, token: token)
                currentRoom = room

                await MainActor.run {
                    onRoomResolved?(room)
                    self.statusText = "已解析: \(room.roomTitle.isEmpty ? room.platform.rawValue : room.roomTitle)"
                }

                if room.streamURLs.isEmpty {
                    await MainActor.run {
                        self.status = .error("无可用流地址")
                        self.statusText = "暂无可用音频"
                    }
                    return
                }

                // 尝试每个流地址，直到成功
                for (index, stream) in room.streamURLs.enumerated() {
                    if Task.isCancelled { return }

                    await MainActor.run {
                        self.currentStreamIndex = index
                        self.statusText = "尝试流地址 \(index + 1)/\(room.streamURLs.count) (\(stream.protocolLabel))"
                    }

                    let success = await tryStream(stream: stream, room: room)
                    if success { return }
                }

                await MainActor.run {
                    self.status = .error("所有流地址均失败")
                    self.statusText = "播放失败"
                }

            } catch {
                await MainActor.run {
                    let msg: String
                    if let apiError = error as? APIError {
                        msg = apiError.errorDescription ?? "未知错误"
                    } else {
                        msg = error.localizedDescription
                    }
                    self.status = .error(msg)
                    self.statusText = msg
                }
            }
        }
    }

    // MARK: - 尝试单个流地址
    private func tryStream(stream: StreamURL, room: RoomInfo) async -> Bool {
        return await withCheckedContinuation { continuation in
            let client = StreamClient()
            let engine = AudioEngine()

            self.streamClient = client
            self.audioEngine = engine

            var hasReceivedData = false
            var hasStartedPlaying = false
            var continuationCalled = false

            let timeout = DispatchTime.now() + 8.0

            // 超时检查
            DispatchQueue.main.asyncAfter(deadline: timeout) {
                if !hasReceivedData && !continuationCalled {
                    continuationCalled = true
                    client.stop()
                    engine.stop()
                    DispatchQueue.main.async {
                        self.statusText = "流连接超时: \(stream.protocolLabel)"
                    }
                    continuation.resume(returning: false)
                }
            }

            // 状态回调
            engine.onStatus = { msg in
                DispatchQueue.main.async {
                    self.statusText = msg

                    if msg.contains("已启动") && !hasStartedPlaying {
                        hasStartedPlaying = true
                        DispatchQueue.main.async {
                            self.status = .playing
                            self.statusText = String(format: "正在播放 %.1fx", self.playbackSpeed)
                        }
                    }
                }
            }

            engine.onError = { msg in
                DispatchQueue.main.async {
                    self.statusText = "音频错误: \(msg)"
                }
            }

            // 数据回调
            client.onData = { data in
                if !hasReceivedData {
                    hasReceivedData = true
                }
                engine.feedData(data)
            }

            client.onError = { msg in
                if !continuationCalled {
                    continuationCalled = true
                    DispatchQueue.main.async {
                        self.statusText = "流错误: \(msg)"
                    }
                    continuation.resume(returning: false)
                }
            }

            client.onStatus = { msg in
                DispatchQueue.main.async {
                    self.statusText = msg
                }
            }

            // 开始流连接
            client.startStreaming(url: stream.url)

            // 如果开始播放，标记成功
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if hasReceivedData && !continuationCalled {
                    continuationCalled = true
                    continuation.resume(returning: true)
                }
            }
        }
    }

    // MARK: - 停止
    func cancel() {
        streamFallbackTask?.cancel()
        streamFallbackTask = nil
        streamClient?.stop()
        audioEngine?.stop()
        streamClient = nil
        audioEngine = nil
        status = .idle
    }

    // MARK: - 变速
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        audioEngine?.setPlaybackSpeed(speed)
        if status == .playing {
            statusText = String(format: "正在播放 %.1fx", speed)
        }
    }

    // MARK: - 暂停/恢复
    func pause() {
        audioEngine?.pause()
        status = .paused
        statusText = "已暂停"
    }

    func resume() {
        audioEngine?.resume()
        status = .playing
        statusText = String(format: "正在播放 %.1fx", playbackSpeed)
    }
}
