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
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowAirPlay])
            try session.setActive(true, options: [])
            activated = true
        } catch {
            // 静默失败：某些模拟器环境无法激活音频会话
        }
    }

    func deactivate() {
        guard activated else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        activated = false
    }

    func updateNowPlaying(title: String, playing: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? "秒听" : title,
            MPMediaItemPropertyArtist: "秒听 · 直播抢货伴侣",
            MPNowPlayingInfoPropertyPlaybackRate: playing ? PlaybackController.shared.speed : 0,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        info[MPMediaItemPropertyAlbumTitle] = "直播音频"
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
