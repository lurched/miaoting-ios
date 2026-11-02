import AVFoundation
import AudioToolbox

/// 把裸 AAC 帧解码成 PCM，等价于 Android 端 `LP` 里的 MediaCodec("audio/mp4a-latm") 部分。
///
/// Android 侧用 `MediaFormat.createAudioFormat + setByteBuffer("csd-0", asc)`，
/// iOS 侧对应 `AudioConverter` + `kAudioConverterDecompressionMagicCookie`。
final class AACDecoder {

    private var converter: AudioConverterRef?
    private var configuredASC: Data?
    private final class Feed {
        var nsPacket: NSData = NSData()
        var consumed = true
    }
    private let feed = Feed()

    private(set) var sampleRate: Double = 44100
    private(set) var channelCount: AVAudioChannelCount = 2
    private(set) var pcmFormat: AVAudioFormat?

    deinit {
        if let converter {
            AudioConverterDispose(converter)
        }
    }

    /// 按 AudioSpecificConfig 建立（或复用）解码器。声道/采样率变化时重建。
    func configure(_ cfg: AACConfig) -> Bool {
        if configuredASC == cfg.asc, converter != nil { return true }

        if let converter {
            AudioConverterDispose(converter)
            self.converter = nil
        }

        sampleRate = Double(cfg.sampleRate)
        channelCount = AVAudioChannelCount(max(1, cfg.channels))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: channelCount) else { return false }

        var inDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var outDesc = format.streamDescription.pointee
        var newConverter: AudioConverterRef?
        let status = AudioConverterNew(&inDesc, &outDesc, &newConverter)
        guard status == noErr, let newConverter else { return false }

        let asc = [UInt8](cfg.asc)
        let ascCount = asc.count
        asc.withUnsafeBufferPointer { buf in
            _ = AudioConverterSetProperty(newConverter,
                                          kAudioConverterDecompressionMagicCookie,
                                          UInt32(ascCount),
                                          buf.baseAddress)
        }

        converter = newConverter
        pcmFormat = format
        configuredASC = cfg.asc
        return true
    }

    /// 解码一个 AAC 帧。返回 nil 表示需要更多输入（或该帧无效）。
    func decode(packet: Data) -> AVAudioPCMBuffer? {
        guard let converter, let pcmFormat else { return nil }

        feed.nsPacket = packet as NSData
        feed.consumed = false

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 8192) else {
            return nil
        }
        var frameCount = UInt32(outBuffer.frameCapacity)
        let status = AudioConverterFillComplexBuffer(
            converter,
            Self.inputProc,
            Unmanaged.passUnretained(feed).toOpaque(),
            &frameCount,
            outBuffer.mutableAudioBufferList,
            nil
        )
        guard status == noErr, frameCount > 0 else { return nil }
        outBuffer.frameLength = frameCount
        return outBuffer
    }

    // MARK: - C 回调

    private static let inputProc: AudioConverterComplexInputDataProc = {
        _, ioNumberDataPackets, ioData, _, inUserData in
        guard let inUserData else {
            ioNumberDataPackets.pointee = 0
            return noErr
        }
        let feed = Unmanaged<Feed>.fromOpaque(inUserData).takeUnretainedValue()
        guard !feed.consumed, feed.nsPacket.length > 0 else {
            ioNumberDataPackets.pointee = 0
            return noErr
        }

        let length = feed.nsPacket.length
        ioNumberDataPackets.pointee = 1
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = 1
        ioData.pointee.mBuffers.mDataByteSize = UInt32(length)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: feed.nsPacket.bytes)
        feed.consumed = true
        return noErr
    }
}
