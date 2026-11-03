import AVFoundation
import AudioToolbox

/// 用 AudioQueue 直接播 FLV 里的裸 AAC 帧。
///
/// 为什么不用 AVAudioEngine + AudioConverter：
/// AudioConverter 要求调用方自己实现 VBR 的输入回调，任何一个字段错了就是整片失败
/// （实测 1160 帧全部 `dec=0`）。AudioQueue 是 AudioToolbox 里成熟的「解码 + 播放」
/// 一体接口：给 ASBD + magic cookie，之后只往队列里塞裸 AAC 帧就行，
/// 解码、重采样、输出全由系统做，延迟也是直出的（没有 HLS 那种分片延迟）。
final class FLVAudioQueuePlayer {

    private var queue: AudioQueueRef?
    private var sampleRate: Double = 48000
    private var channels: UInt32 = 2
    private(set) var enqueued = 0
    private(set) var started = false
    /// 队列里还没播完的 buffer 数，用来判断要不要丢弃积压追直播。
    private var inFlight = 0

    var onError: ((String) -> Void)?

    /// 按 AudioSpecificConfig 建队列。
    func configure(asc: Data, sampleRate: Double, channels: UInt32) -> Bool {
        stop()

        self.sampleRate = sampleRate
        self.channels = max(1, channels)

        var desc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: self.channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var newQueue: AudioQueueRef?
        let status = AudioQueueNewOutput(
            &desc,
            { userData, queue, buffer in
                // buffer 播完回收
                AudioQueueFreeBuffer(queue, buffer)
                guard let userData else { return }
                let player = Unmanaged<FLVAudioQueuePlayer>.fromOpaque(userData).takeUnretainedValue()
                player.inFlight = max(0, player.inFlight - 1)
            },
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil,
            0,
            &newQueue
        )
        guard status == noErr, let newQueue else {
            onError?("AudioQueueNewOutput 失败：\(status)")
            return false
        }

        var cookie = [UInt8](asc)
        let cookieStatus = AudioQueueSetProperty(newQueue,
                                                 kAudioQueueProperty_MagicCookie,
                                                 &cookie,
                                                 UInt32(cookie.count))
        if cookieStatus != noErr {
            AudioQueueDispose(newQueue, true)
            onError?("设置 magic cookie 失败：\(cookieStatus)")
            return false
        }

        let startStatus = AudioQueueStart(newQueue, nil)
        guard startStatus == noErr else {
            AudioQueueDispose(newQueue, true)
            onError?("AudioQueueStart 失败：\(startStatus)")
            return false
        }

        queue = newQueue
        started = true
        return true
    }

    /// 塞一帧裸 AAC。
    func enqueue(_ frame: Data) {
        guard let queue, started, !frame.isEmpty else { return }

        // 积压太多直接丢，保证听到的是“现在”
        if inFlight > 60 {
            AudioQueueReset(queue)
            inFlight = 0
        }

        var buffer: AudioQueueBufferRef?
        guard AudioQueueAllocateBuffer(queue, UInt32(frame.count), &buffer) == noErr,
              let buffer else { return }

        frame.copyBytes(to: buffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self),
                        count: frame.count)
        buffer.pointee.mAudioDataByteSize = UInt32(frame.count)

        guard AudioQueueEnqueueBuffer(queue, buffer, 0, nil) == noErr else {
            AudioQueueFreeBuffer(queue, buffer)
            return
        }
        inFlight += 1
        enqueued += 1
    }

    /// 变速。AudioQueue 的 PlayRate 范围 0.5–2.0，和 Android 一样是变调的。
    func setRate(_ rate: Float) {
        guard let queue else { return }
        AudioQueueSetParameter(queue, kAudioQueueParam_PlayRate, max(0.5, min(2.0, rate)))
    }

    func stop() {
        guard let queue else { return }
        started = false
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
        self.queue = nil
        inFlight = 0
    }

    deinit {
        stop()
    }
}
