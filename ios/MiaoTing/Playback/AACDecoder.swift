import AVFoundation
import AudioToolbox

/// 把裸 AAC 帧解码成 PCM。
///
/// 用 `AudioConverterConvertBuffer`（同步、一次一包），而不是
/// `AudioConverterFillComplexBuffer`（要自己实现 VBR 输入回调，字段错一个就整片失败）。
/// 输出是非交错 float32，方便上层直接做增益。
final class AACDecoder {

    private var converter: AudioConverterRef?
    private var configuredASC: Data?

    private(set) var sampleRate: Double = 44100
    private(set) var channelCount: AVAudioChannelCount = 2
    private(set) var pcmFormat: AVAudioFormat?

    deinit {
        if let converter {
            AudioConverterDispose(converter)
        }
    }

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
        guard AudioConverterNew(&inDesc, &outDesc, &newConverter) == noErr,
              let newConverter else { return false }

        let asc = [UInt8](cfg.asc)
        asc.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            _ = AudioConverterSetProperty(newConverter,
                                          kAudioConverterDecompressionMagicCookie,
                                          UInt32(asc.count),
                                          base)
        }

        converter = newConverter
        pcmFormat = format
        configuredASC = cfg.asc
        return true
    }

    /// 解一帧，返回非交错 float32 PCM。
    func decode(packet: Data) -> AVAudioPCMBuffer? {
        guard let converter, let pcmFormat else { return nil }
        guard !packet.isEmpty else { return nil }
        guard let out = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 2048) else { return nil }

        var outputBytes = UInt32(out.frameCapacity) * 4 * UInt32(pcmFormat.channelCount)
        let status = packet.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return AudioConverterConvertBuffer(converter,
                                               UInt32(packet.count),
                                               base,
                                               &outputBytes,
                                               out.mutableAudioBufferList)
        }
        guard status == noErr, outputBytes > 0 else { return nil }

        let frames = outputBytes / (4 * UInt32(pcmFormat.channelCount))
        guard frames > 0 else { return nil }
        out.frameLength = frames
        return out
    }
}
