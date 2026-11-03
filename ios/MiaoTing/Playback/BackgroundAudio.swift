import AVFoundation
import MediaPlayer

/// 后台播放 / 锁屏控制，对应 Android 端 `PlayerService` 的前台 Service + 通知。
final class BackgroundAudio {

    static let shared = BackgroundAudio()

    private var activated = false

    private init() {
        registerRemoteCommands()
    }

    func activate() {
        // setActive 会和系统音频服务通信，偶尔要几百毫秒；
        // 放在主线程会把界面卡住，这里丢到后台。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default,
                                        options: [.allowBluetooth, .allowAirPlay])
                try session.setActive(true, options: [])
                self?.activated = true
            } catch {
                // 模拟器或音频服务异常时静默失败
            }
        }
    }

    func deactivate() {
        guard activated else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        activated = false
    }

    func updateNowPlaying(title: String, playing: Bool) {
        let speed = PlaybackController.shared.speed
        // MPNowPlayingInfoCenter 的 setter 要走系统媒体服务，
        // 网络/锁屏状态异常时会阻塞主线程，放到后台。
        DispatchQueue.global(qos: .utility).async {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: title.isEmpty ? "秒听" : title,
                MPMediaItemPropertyArtist: "秒听 · 直播抢货伴侣",
                MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPMediaItemPropertyAlbumTitle: "直播音频"
            ]
            info[MPMediaItemPropertyAlbumTitle] = "直播音频"
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            PlaybackController.shared.toggle()
            return .success
        }
        center.pauseCommand.addTarget { _ in
            PlaybackController.shared.stop()
            return .success
        }
        center.stopCommand.addTarget { _ in
            PlaybackController.shared.stop()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            PlaybackController.shared.toggle()
            return .success
        }
    }
}
