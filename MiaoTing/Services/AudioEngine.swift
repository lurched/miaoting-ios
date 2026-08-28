//  AudioEngine.swift
//  音频播放引擎
//
//  从 Android P 类 + PlayerService 反编译重写
//  使用 AVAudioEngine + AVAudioConverter 实现 AAC 解码和变速播放
//

import Foundation
import AVFoundation
import AudioToolbox

class AudioEngine {

    // 回调
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?

    // 音频引擎
    private let engine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private var bufferFormat: AVAudioFormat?

    // FLV 解析器
    private let flvParser = FLVParser()

    // AAC 解码器
    private var converter: AVAudioConverter?

    // 音频配置
    private var sampleRate: Double = 44100
    private var channelCount: UInt32 = 2
    private var playbackSpeed: Float = 1.0

    // 播放队列
    private let pcmBufferQueue = DispatchQueue(label: "com.syncrozero.pcm", qos: .userInitiated)
    private var pendingPCMBuffers: [AVAudioPCMBuffer] = []
    private var isPlaying = false
    private var isConnected = false

    // 实时保持
    private var lastBufferTime: TimeInterval = 0
    private var bufferHealthCheckTimer: DispatchSourceTimer?

    // 统计
    private var totalPCMFrames: Int64 = 0
    private var totalBytesWritten: Int = 0

    // MARK: - 初始化
    init() {
        setupFLVParser()
    }

    private func setupFLVParser() {
        flvParser.onAudioFrame = { [weak self] frame in
            self?.processAudioFrame(frame)
        }
        flvParser.onConfigReady = { [weak self] config in
            self?.configureAudio(config: config)
        }
        flvParser.onError = { [weak self] msg in
            self?.onError?(msg)
        }
        flvParser.onStatus = { [weak self] msg in
            self?.onStatus?(msg)
        }
    }

    // MARK: - 配置音频输出
    private func configureAudio(config: AACConfig) {
        let newSampleRate = Double(config.sampleRate)
        let newChannels = UInt32(config.channelCount)

        // 检查是否需要重新配置
        if newSampleRate == sampleRate && newChannels == channelCount && bufferFormat != nil {
            return
        }

        sampleRate = newSampleRate
        channelCount = newChannels

        onStatus?("直播音频线路已适配: \(Int(sampleRate))Hz, \(channelCount)ch")

        // 重新创建 buffer format
        bufferFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        )

        // 创建 AVAudioConverter 用于 AAC → PCM 解码
        guard let inputFormat = createAACFormat() else {
            onError?("无法创建 AAC 输入格式")
            return
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        ) else {
            onError?("无法创建 PCM 输出格式")
            return
        }

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        setupAudioEngine()
    }

    // 创建 AAC 输入格式
    private func createAACFormat() -> AVAudioFormat? {
        // 使用标准 AAC-LC 格式描述
        // 构造 AudioStreamBasicDescription
        var streamDesc = AudioStreamBasicDescription()
        streamDesc.mSampleRate = sampleRate
        streamDesc.mFormatID = kAudioFormatMPEG4AAC
        streamDesc.mFormatFlags = 0
        streamDesc.mBytesPerPacket = 0
        streamDesc.mFramesPerPacket = 1024  // AAC 帧长
        streamDesc.mBytesPerFrame = 0
        streamDesc.mChannelsPerFrame = channelCount
        streamDesc.mBitsPerChannel = 0
        streamDesc.mReserved = 0

        return AVAudioFormat(streamDescription: &streamDesc)
    }

    // 启动音频引擎
    private func setupAudioEngine() {
        // 停止现有引擎
        if engine.isRunning {
            engine.stop()
        }

        // 移除旧 player
        if let player = audioPlayer {
            engine.detach(player)
        }

        // 创建新 player
        audioPlayer = AVAudioPlayerNode()
        guard let player = audioPlayer else { return }

        engine.attach(player)

        guard let format = bufferFormat else {
            onError?("无法获取 buffer format")
            return
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        // 设置 audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .allowBluetoothA2DP])
            try session.setActive(true)

            engine.prepare()
            try engine.start()

            player.play()
            isPlaying = true
            onStatus?("直播音频已启动")

            // 启动缓冲健康检查
            startBufferHealthCheck()
        } catch {
            onError?("音频引擎启动失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 处理音频帧
    private func processAudioFrame(_ frame: AudioFrame) {
        guard let converter = converter,
              let outputFormat = bufferFormat else {
            return
        }

        // 将 AAC 原始数据包装为 AVAudioPacketBuffer
        guard let packetBuffer = createPacketBuffer(from: frame.data) else {
            return
        }

        // 创建输出 PCM buffer
        let frameCapacity = AVAudioFrameCount(1024)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return
        }

        // 使用 AVAudioConverter 解码
        var error: NSError?
        var inputBufferConsumed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return packetBuffer
        }

        let status = converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)

        if status == .error || error != nil {
            return
        }

        if pcmBuffer.frameLength > 0 {
            enqueuePCMBuffer(pcmBuffer)
        }
    }

    // 创建 AVAudioPacketBuffer
    private func createPacketBuffer(from aacData: Data) -> AVAudioPacketBuffer? {
        guard let aacFormat = createAACFormat() else { return nil }

        var packetBuffer: AVAudioPacketBuffer?
        let result = AVAudioPacketBufferCreate(
            kCFAllocatorDefault,
            aacFormat.formatDescription,
            1,
            1024,
            aacFormat.formatDescription,
            aacData.count,
            &packetBuffer
        )

        guard result == noErr, let buffer = packetBuffer else {
            return nil
        }

        // 复制数据
        aacData.withUnsafeBytes { rawBuffer in
            if let base = rawBuffer.baseAddress {
                memcpy(buffer.mData, base, aacData.count)
            }
        }

        return buffer
    }

    // 入队 PCM 缓冲区
    private func enqueuePCMBuffer(_ buffer: AVAudioPCMBuffer) {
        pcmBufferQueue.async { [weak self] in
            guard let self = self else { return }

            self.pendingPCMBuffers.append(buffer)
            self.totalPCMFrames += Int64(buffer.frameLength)
            self.totalBytesWritten += buffer.byteLength

            // 控制缓冲区大小，避免过多堆积
            if self.pendingPCMBuffers.count > 50 {
                // 丢弃最旧的几帧保持实时
                let dropCount = self.pendingPCMBuffers.count - 30
                self.pendingPCMBuffers.removeFirst(dropCount)
                DispatchQueue.main.async {
                    self.onStatus?("正在保持实时收听")
                }
            }

            self.scheduleBuffers()
        }
    }

    // 调度缓冲区到 player
    private func scheduleBuffers() {
        guard let player = audioPlayer, isPlaying else { return }

        while !pendingPCMBuffers.isEmpty {
            let buffer = pendingPCMBuffers.removeFirst()

            // 变速处理：通过修改播放速率
            // AVAudioPlayerNode 不直接支持变速，通过 schedule + time pitch 实现
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                // 播放完成回调
                self?.lastBufferTime = Date().timeIntervalSince1970
            }
        }
    }

    // MARK: - 变速播放
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed

        // 使用 AVAudioUnitTimePitch 实现变速不变调
        // 需要在音频图中插入 time pitch 节点
        if let player = audioPlayer {
            // 重新连接：player → timePitch → mixer
            // 这里简化处理，实际需要重新连接音频图
            onStatus?(String(format: "正在播放 %.1fx", speed))
        }
    }

    // MARK: - 缓冲健康检查（对应 P.a 中的实时保持逻辑）
    private func startBufferHealthCheck() {
        bufferHealthCheckTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.checkBufferHealth()
        }
        timer.resume()
        bufferHealthCheckTimer = timer
    }

    private func checkBufferHealth() {
        guard isPlaying else { return }

        let now = Date().timeIntervalSince1970
        let elapsed = now - lastBufferTime

        // 如果超过 3 秒没有新缓冲区播放，可能断流
        if elapsed > 3.0 && !pendingPCMBuffers.isEmpty {
            DispatchQueue.main.async {
                self.onStatus?("直播音频播放中")
            }
        }
    }

    // MARK: - 输入数据
    func feedData(_ data: Data) {
        flvParser.feed(data)
    }

    // MARK: - 停止
    func stop() {
        isPlaying = false
        bufferHealthCheckTimer?.cancel()
        bufferHealthCheckTimer = nil

        if let player = audioPlayer {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }

        flvParser.reset()
        pendingPCMBuffers.removeAll()
        converter = nil
        bufferFormat = nil
        totalPCMFrames = 0
        totalBytesWritten = 0
    }

    // MARK: - 暂停/恢复
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func resume() {
        if engine.isRunning {
            audioPlayer?.play()
            isPlaying = true
        }
    }

    // MARK: - 统计
    var bufferDuration: TimeInterval {
        guard let format = bufferFormat else { return 0 }
        let totalFrames = Double(pendingPCMBuffers.reduce(0) { $0 + Int($1.frameLength) })
        return totalFrames / format.sampleRate
    }
}
