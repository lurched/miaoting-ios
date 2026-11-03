import AVFoundation
import AudioToolbox

/// 用 AudioUnit 的 RemoteIO 直接输出 PCM。
///
/// 相比 AudioQueue：音量上限不再是 1.0，可以在 render 回调里乘任意增益；
/// 相比 AVAudioEngine：没有节点图，不会因为格式协商卡住主线程。
/// 代价是环形缓冲和 render 回调要自己写。
final class RemoteIOPlayer {

    private var unit: AudioComponentInstance?
    private var sampleRate: Double = 48000
    private var channels: UInt32 = 2

    /// 线性增益，界面可调。
    var gain: Float = 2.2

    /// 交错 float32 环形缓冲（L,R,L,R…）
    private var ring: UnsafeMutablePointer<Float>?
    private let ringFrames: Int = 48000 * 2          // 2 秒
    private var writeIndex = 0
    private var readIndex = 0
    private let lock = NSLock()

    private(set) var started = false
    private(set) var framesWritten = 0

    var onError: ((String) -> Void)?

    deinit {
        stop()
    }

    func configure(sampleRate: Double, channels: UInt32) -> Bool {
        stop()

        self.sampleRate = sampleRate
        self.channels = max(1, channels)

        let frames = ringFrames
        let total = frames * Int(self.channels)
        ring = UnsafeMutablePointer<Float>.allocate(capacity: total)
        ring?.initialize(repeating: 0, count: total)
        writeIndex = 0
        readIndex = 0

        // 1) RemoteIO 单元
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &desc) else {
            onError?("找不到 RemoteIO 组件")
            return false
        }
        var newUnit: AudioComponentInstance?
        guard AudioComponentInstanceNew(component, &newUnit) == noErr, let newUnit else {
            onError?("创建 RemoteIO 失败")
            return false
        }

        // 2) 输出格式：float32 非交错
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: self.channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        guard AudioUnitSetProperty(newUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   0,
                                   &format,
                                   UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr else {
            AudioComponentInstanceDispose(newUnit)
            onError?("设置输出格式失败")
            return false
        }

        // 3) render 回调
        var callback = AURenderCallbackStruct(
            inputProc: { inRefCon, _, _, _, inNumberFrames, ioData in
                let player = Unmanaged<RemoteIOPlayer>.fromOpaque(inRefCon).takeUnretainedValue()
                return player.render(frameCount: Int(inNumberFrames), ioData: ioData)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        guard AudioUnitSetProperty(newUnit,
                                   kAudioUnitProperty_SetRenderCallback,
                                   kAudioUnitScope_Input,
                                   0,
                                   &callback,
                                   UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr else {
            AudioComponentInstanceDispose(newUnit)
            onError?("设置 render 回调失败")
            return false
        }

        // 4) 初始化 + 启动
        guard AudioUnitInitialize(newUnit) == noErr else {
            AudioComponentInstanceDispose(newUnit)
            onError?("AudioUnit 初始化失败")
            return false
        }
        guard AudioOutputUnitStart(newUnit) == noErr else {
            AudioUnitUninitialize(newUnit)
            AudioComponentInstanceDispose(newUnit)
            onError?("RemoteIO 启动失败")
            return false
        }

        unit = newUnit
        started = true
        return true
    }

    /// 把解码出来的 PCM 写进环形缓冲。
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard started, let ring else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0, let data = buffer.floatChannelData else { return }

        lock.lock()
        defer { lock.unlock() }

        let capacity = ringFrames
        let maxFrames = min(frames, capacity)

        // 积压超过 1.5 秒就丢掉最旧的，保证听的是“现在”
        var occupied = writeIndex - readIndex
        if occupied < 0 { occupied += capacity }
        if occupied + maxFrames > capacity - 4096 {
            readIndex = (writeIndex - capacity / 4 + capacity) % capacity
        }

        for i in 0..<maxFrames {
            for c in 0..<min(channelCount, Int(channels)) {
                ring[(writeIndex + i) * Int(channels) + c] = data[c][i]
            }
        }
        writeIndex = (writeIndex + maxFrames) % capacity
        framesWritten += maxFrames
    }

    private func render(frameCount: Int, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ioData else { return noErr }
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        guard !buffers.isEmpty else { return noErr }

        let channelCount = Int(channels)
        let capacity = ringFrames

        lock.lock()
        var available = writeIndex - readIndex
        if available < 0 { available += capacity }
        let take = min(frameCount, available)

        let gain = self.gain
        for frame in 0..<take {
            for c in 0..<channelCount {
                guard c < buffers.count,
                      let dst = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                var value = ring?[((readIndex + frame) % capacity) * channelCount + c] ?? 0
                value *= gain
                dst[frame] = max(-1.0, min(1.0, value))
            }
        }
        readIndex = (readIndex + take) % capacity
        lock.unlock()

        // 不够的补静音，避免爆音
        if take < frameCount {
            for c in 0..<buffers.count {
                guard let dst = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in take..<frameCount { dst[frame] = 0 }
            }
        }
        return noErr
    }

    func stop() {
        guard let unit else { return }
        started = false
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        if let ring {
            ring.deallocate()
            self.ring = nil
        }
    }
}
