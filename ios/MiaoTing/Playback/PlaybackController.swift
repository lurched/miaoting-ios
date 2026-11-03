import AVFoundation

/// 播放总控：按 URL 形态分流到 FLV 自研链路或 HLS(AVPlayer) 链路。
///
/// 与 Android 端 `PlayerService.onStartCommand("...PLAY")` 的分支一一对应：
///   `url` 含 m3u8 / pull-hls  → MediaPlayer（iOS: AVPlayer）
///   其它                      → 自建 FLV demux + MediaCodec 解码（iOS: FLVDemuxer + AudioConverter）
final class PlaybackController {

    static let shared = PlaybackController()

    enum Status: Equatable {
        case idle
        case preparing
        case playing
        case failed(String)

        var text: String {
            switch self {
            case .idle: return "未播放"
            case .preparing: return "正在连接直播音频"
            case .playing: return "正在播放"
            case .failed(let m): return m
            }
        }
    }

    private(set) var status: Status = .idle {
        didSet {
            guard status != oldValue else { return }
            let s = status
            DispatchQueue.main.async { [weak self] in self?.onStatus?(s) }
        }
    }
    var onStatus: ((Status) -> Void)?
    var onTitle: ((String) -> Void)?

    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""

    var speed: Float = 1.0 {
        didSet { avPlayer?.rate = speed }
    }

    /// 增益（RemoteIO 的 render 回调里乘），界面可调
    var gain: Float = 2.2 {
        didSet { rioPlayer.gain = gain }
    }
    var preservesPitch: Bool = true

    private let demuxer = FLVDemuxer()
    private let decoder = AACDecoder()
    private let rioPlayer = RemoteIOPlayer()
    private var loader: FLVStreamLoader?
    private var avPlayer: AVPlayer?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var watchdog: DispatchWorkItem?
    /// 实际在播/正在连的地址，诊断面板用。
    private(set) var activeStreamURL: String = ""
    /// 已收到的字节数 / AAC 帧数 / PCM buffer 数，诊断用。
    private(set) var bytesReceived = 0

    private(set) var configCalls = 0
    private(set) var packetCalls = 0
    private(set) var decodedFrames = 0
    private(set) var decodeFails = 0

    var diagnosticsLine: String {
        let d = demuxer
        return "bytes=\(bytesReceived) tags=\(d.tagsSeen) aac=\(d.aacTagsSeen) cfg=\(configCalls) pkt=\(packetCalls) dec=\(decodedFrames) fail=\(decodeFails) playing=\(rioPlayer.started ? "on" : "off")"
    }

    private init() {
        rioPlayer.onError = { [weak self] message in
            self?.status = .failed(message)
        }
        configureDemuxer()
    }

    private func configureDemuxer() {
        demuxer.onConfig = { [weak self] config in
            guard let self else { return }
            self.configCalls += 1
            guard self.decoder.configure(config) else {
                self.status = .failed("音频参数不支持：\(config.sampleRate)Hz/\(config.channels)ch")
                return
            }
            guard self.rioPlayer.configure(sampleRate: Double(config.sampleRate),
                                           channels: UInt32(config.channels)) else { return }
            self.rioPlayer.gain = self.gain
            self.cancelWatchdog()
            self.status = .playing
        }

        demuxer.onPacket = { [weak self] packet, _ in
            guard let self else { return }
            self.packetCalls += 1
            if let buffer = self.decoder.decode(packet: packet) {
                self.decodedFrames += 1
                self.rioPlayer.enqueue(buffer)
            } else {
                self.decodeFails += 1
            }
        }

        demuxer.onInvalidStream = { [weak self] in
            self?.status = .failed("音频流格式无法识别，请稍后重试。")
        }
    }

    // MARK: - 控制

    /// 抖音 CDN 的 flv 加上 `only_audio=1` 才会只推音频轨，
    /// 抓包里安卓端就是这么请求的；HTML 里的原始地址没有这个参数。
    static func audioOnlyVariant(_ url: URL) -> URL {
        let text = url.absoluteString
        guard text.contains("douyincdn.com"), !text.lowercased().contains("only_audio=1") else { return url }
        let separator = text.contains("?") ? "&" : "?"
        return URL(string: text + separator + "only_audio=1") ?? url
    }

    func play(url: URL, title: String) {
        stop()
        let url = Self.audioOnlyVariant(url)
        currentURL = url
        currentTitle = title
        activeStreamURL = url.absoluteString
        onTitle?(title)
        status = .preparing

        if Self.isHLS(url) {
            playHLS(url)
        } else {
            playFLV(url)
        }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        loader?.cancel()
        loader = nil
        demuxer.reset()
        rioPlayer.stop()
        teardownAVPlayer()
        // 保留 currentURL：锁屏 / 界面上的“继续播放”要靠它重连
        status = .idle
    }

    func toggle() {
        switch status {
        case .playing, .preparing:
            stop()
        default:
            if let url = currentURL { play(url: url, title: currentTitle) }
        }
    }

    static func isHLS(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        return s.contains(".m3u8") || s.contains("m3u8") || s.contains("pull-hls")
    }

    // MARK: - FLV

    private func playFLV(_ url: URL) {
        configureAudioSession()

        let loader = FLVStreamLoader()
        self.loader = loader
        loader.onData = { [weak self] data in
            guard let self else { return }
            self.bytesReceived += data.count
            self.demuxer.append(data)
        }
        loader.onFinished = { [weak self] error in
            guard let self else { return }
            if let error {
                self.status = .failed(error.localizedDescription)
            } else if self.status == .preparing {
                self.status = .failed("直播间暂未开播。")
            }
        }
        loader.start(url: url, referer: Self.referer(for: url))
        startWatchdog()
        BackgroundAudio.shared.updateNowPlaying(title: currentTitle, playing: true)
    }

    // MARK: - HLS

    private func playHLS(_ url: URL) {
        configureAudioSession()

        // 实测抖音的 m3u8 不校验 Referer/UA，直接给 AVURLAsset 就行
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        let av = AVPlayer(playerItem: item)
        av.automaticallyWaitsToMinimizeStalling = true
        av.allowsExternalPlayback = false
        avPlayer = av

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                av.rate = self.speed
                self.status = .playing
            case .failed:
                self.status = .failed(item.error?.localizedDescription ?? "播放失败，请稍后重试。")
            default:
                break
            }
        }
        av.playImmediately(atRate: speed)
        BackgroundAudio.shared.updateNowPlaying(title: currentTitle, playing: true)
    }

    /// 12 秒内没收到任何音频帧就判超时，避免界面永远停在「正在连接」。
    func playTestTone() {
        // AudioQueue 版本不再提供测试音，保留接口避免界面报错
    }

    private func startWatchdog(seconds: TimeInterval = 12) {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.status == .preparing {
                self.status = .failed("连接超时：\(Int(seconds)) 秒内没有收到音频数据。")
                self.loader?.cancel()
                self.loader = nil
            }
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func teardownAVPlayer() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        avPlayer?.pause()
        avPlayer = nil
    }

    // MARK: - 环境

    private func configureAudioSession() {
        BackgroundAudio.shared.activate()
    }

    /// 对应 Android 端 `g.q()`：按源站决定 Referer。
    static func referer(for url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("kuaishou.com") { return "https://live.kuaishou.com/" }
        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") || host.contains("xhscdn") {
            return "https://www.xiaohongshu.com/"
        }
        if host == "tbzb.taobao.com" { return "https://tbzb.taobao.com/" }
        return "https://live.douyin.com/"
    }
}
