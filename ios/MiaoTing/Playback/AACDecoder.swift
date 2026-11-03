import AVFoundation
import AudioToolbox

/// 裸 AAC 帧 → PCM。
///
/// 两个关键点（都踩过坑）：
/// 1. AAC 是 VBR，`inputProc` 必须通过 `outDataPacketDescription` 告诉解码器每包多大；
/// 2. `AudioConverterFillComplexBuffer` 的最后一个参数是**输出**描述，对 PCM 要传 nil。
///    之前误传了输入描述的指针，等于把刚写进去的输入描述覆盖成垃圾，于是每帧都失败（dec=0）。
///
/// 另外 `AudioConverterConvertBuffer` 只支持 PCM→PCM，不能用来解 AAC，那条路是死的。
final class AACDecoder {

    private var converter: AudioConverterRef?
    private var configuredASC: Data?

    private final class Feed {
        var nsPacket: NSData = NSData()
        var consumed = true
        var packetDescription = AudioStreamPacketDescription()
        let descPointer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)

        deinit {
            descPointer.deallocate()
        }
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

    func decode(packet: Data) -> AVAudioPCMBuffer? {
        guard let converter, let pcmFormat, !packet.isEmpty else { return nil }

        feed.nsPacket = packet as NSData
        feed.consumed = false
        feed.packetDescription = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: 0,
            mDataByteSize: UInt32(packet.count)
        )
        feed.descPointer.pointee = feed.packetDescription

        guard let out = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 2048) else { return nil }
        var frameCount = UInt32(out.frameCapacity)

        let status = AudioConverterFillComplexBuffer(
            converter,
            Self.inputProc,
            Unmanaged.passUnretained(feed).toOpaque(),
            &frameCount,
            out.mutableAudioBufferList,
            nil                    // ← 输出描述，PCM 不需要；传指针会覆盖输入描述
        )
        guard status == noErr, frameCount > 0 else { return nil }
        out.frameLength = frameCount
        return out
    }

    private static let inputProc: AudioConverterComplexInputDataProc = {
        _, ioNumberDataPackets, ioData, outPacketDescription, inUserData in
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

        if let outPacketDescription {
            outPacketDescription.pointee = feed.descPointer
        }

        feed.consumed = true
        return noErr
    }
}
