import AVFoundation

/// 直播音频播放链，等价于 Android 端 `LP` + `PlayerService` 的 FLV 路径：
///
///   AAC 帧 → MediaCodec 解码 → PCM → AudioTrack.write
///
/// iOS 改成：
///
///   AAC 帧 → AudioConverter 解码 → AVAudioPCMBuffer → AVAudioPlayerNode
///          → AVAudioUnitVarispeed → AVAudioUnitTimePitch → mainMixer
///
/// 两个变速节点的组合复刻了 Android 的两种行为：
///  - preservesPitch = true  → 只开 TimePitch，加速不变调（对应 MediaPlayer.setPlaybackParams）
///  - preservesPitch = false → 只开 Varispeed，加速同时变调（对应 `LP.a()` 里手写的线性插值重采样）
final class LiveAudioPlayer {

    enum State: Equatable {
        case idle
        case buffering
        case playing
        case failed(String)

        var text: String {
            switch self {
            case .idle: return "未播放"
            case .buffering: return "正在缓冲直播音频"
            case .playing: return "正在播放"
            case .failed(let message): return message
            }
        }
    }

    var onStateChange: ((State) -> Void)?
    var onLevel: ((Float) -> Void)?

    /// 默认 1.3x，和 Android 端 `PlayerService.c = 1067869798`（float 1.3f）一致。
    var speed: Float = 1.3 {
        didSet { applySpeed() }
    }
    var preservesPitch = true {
        didSet { applySpeed() }
    }
    /// 线性增益。抖音那条 only_audio 流的电平偏低，直接播比原声小很多，
    /// 这里在喂给播放节点之前乘一个系数（AudioQueue 那条路做不到，所以换回 AVAudioEngine）。
    var gain: Float = 2.2
    /// 允许的最大积压，超过就丢弃已排队缓冲去追直播（Android 端是 pause/flush/play）。
    /// 原版阈值是 0.35s + 250ms 冷却；移动网络下 0.35s 容易反复重排，这里放宽到 0.9s。
    var maxLatency: Double = 0.9
    /// 起播前先攒多久的音频。
    var startThreshold: Double = 0.35

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let timePitch = AVAudioUnitTimePitch()

    private let queue = DispatchQueue(label: "com.miaoting.live.audio")
    private var attached = false
    private var connectedFormat: AVAudioFormat?
    private var pendingFrames: Double = 0
    private var sampleRate: Double = 44100
    private var generation = 0
    private var isRunning = false
    /// 已收到的 PCM buffer 数，诊断用。
    private(set) var receivedBuffers = 0
    /// 引擎当前是否在跑，诊断用。
    var engineRunning: Bool { engine.isRunning }
    private var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            let s = state
            DispatchQueue.main.async { [weak self] in self?.onStateChange?(s) }
        }
    }

    // MARK: - 生命周期

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.pendingFrames = 0
            self.isRunning = true
            self.state = .buffering
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.generation += 1
            self.pendingFrames = 0
            self.player.stop()
            self.engine.stop()
            self.state = .idle
        }
    }

    func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            self.performResetLocked()
        }
    }

    // MARK: - 数据

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        applyGain(buffer)
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.sampleRate = buffer.format.sampleRate
            self.ensureGraphLocked(format: buffer.format)

            // 积压太多说明解码追不上直播，丢掉旧缓冲重新对齐（对应 Android 的 flush）。
            if self.pendingFrames / self.sampleRate > self.maxLatency {
                self.performResetLocked()
                self.state = .playing
            }

            self.pendingFrames += Double(buffer.frameLength)
            self.receivedBuffers += 1
            let gen = self.generation
            self.player.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard gen == self.generation else { return }
                    self.pendingFrames = max(0, self.pendingFrames - Double(buffer.frameLength))
                }
            }

            if !self.player.isPlaying,
               self.pendingFrames / self.sampleRate >= self.startThreshold {
                self.startPlaybackLocked()
            }
        }
    }

    // MARK: - 内部

    /// 播一段 440Hz 正弦波，用来判断问题出在音频栈还是数据链路。
    func playTestTone() {
        queue.async { [weak self] in
            guard let self else { return }
            let sampleRate = 44100.0
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                self.state = .failed("无法创建测试音频格式")
                return
            }
            self.ensureGraphLocked(format: format)
            do {
                try self.engine.start()
            } catch {
                self.state = .failed("测试音引擎启动失败：\(error.localizedDescription)")
                return
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(sampleRate)) else { return }
            buffer.frameLength = AVAudioFrameCount(sampleRate)
            if let channel = buffer.floatChannelData?[0] {
                for i in 0..<Int(sampleRate) {
                    channel[i] = Float(sin(2 * Double.pi * 440 * Double(i) / sampleRate)) * 0.2
                }
            }
            self.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            self.player.play()
            self.state = .playing
        }
    }

    private func applyGain(_ buffer: AVAudioPCMBuffer) {
        guard gain != 1.0, let data = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard channels > 0, frames > 0 else { return }
        for c in 0..<channels {
            let pointer = data[c]
            for i in 0..<frames {
                let value = pointer[i] * gain
                pointer[i] = max(-1.0, min(1.0, value))
            }
        }
    }

    private func ensureGraphLocked(format: AVAudioFormat) {
        if let connectedFormat, connectedFormat.sampleRate == format.sampleRate,
           connectedFormat.channelCount == format.channelCount {
            return
        }

        let wasRunning = engine.isRunning
        engine.stop()
        player.stop()

        if !attached {
            engine.attach(player)
            engine.attach(varispeed)
            engine.attach(timePitch)
            attached = true
        }
        engine.connect(player, to: varispeed, format: format)
        engine.connect(varispeed, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()

        connectedFormat = format
        applySpeed()
        if wasRunning {
            try? engine.start()
        }
    }

    private func startPlaybackLocked() {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                state = .failed("音频引擎启动失败：\(error.localizedDescription)")
                return
            }
        }
        guard engine.isRunning else {
            state = .failed("音频引擎未运行（可能被系统占用）")
            return
        }
        player.play()
        isRunning = true
        state = .playing
    }

    private func performResetLocked() {
        generation += 1
        pendingFrames = 0
        player.stop()
        if engine.isRunning {
            player.play()
        }
    }

    private func applySpeed() {
        let rate = max(1.0, min(2.0, speed))
        timePitch.rate = preservesPitch ? rate : 1.0
        varispeed.rate = preservesPitch ? 1.0 : rate
    }
}
