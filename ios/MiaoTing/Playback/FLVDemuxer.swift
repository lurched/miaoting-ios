import Foundation

/// AAC AudioSpecificConfig，等价于 Android 端 `La`（a）对象。
struct AACConfig: Equatable {
    let asc: Data
    let sampleRateIndex: Int
    let sampleRate: Int
    let channels: Int
}

/// FLV 增量解析器，等价于 Android 端 `Lc`。
///
/// 只关心 tagType == 8（audio）里的 AAC 数据：
///  - AACPacketType 0 -> AudioSpecificConfig（csd-0）
///  - AACPacketType 1 -> 裸 AAC 帧
///
/// 非 AAC 的音频编码（SoundFormat != 10）直接丢弃：直播源目前只会给 AAC。
final class FLVDemuxer {

    /// AudioSpecificConfig 里的采样率索引表，与 Android 端 `LP.f()` 完全一致。
    static let sampleRates: [Int] = [
        96000, 88200, 64000, 48000, 44100, 32000,
        24000, 22050, 16000, 12000, 11025, 8000, 7350
    ]

    var onConfig: ((AACConfig) -> Void)?
    var onPacket: ((Data, Int) -> Void)?      // (裸 AAC 帧, 时间戳 ms)
    var onInvalidStream: (() -> Void)?

    private var buf: [UInt8] = []
    private var offset = 0
    private var headerParsed = false

    private(set) var config: AACConfig?
    private(set) var packetsReceived = 0

    func reset() {
        buf.removeAll(keepingCapacity: true)
        offset = 0
        headerParsed = false
        config = nil
        packetsReceived = 0
    }

    func append(_ data: Data) {
        buf.append(contentsOf: data)
        parse()
    }

    // MARK: - 解析

    private func parse() {
        if !headerParsed {
            guard buf.count - offset >= 13 else { return }
            guard buf[offset] == 0x46, buf[offset + 1] == 0x4C, buf[offset + 2] == 0x56 else {
                // 不是 FLV：清空并通知上层（等价于 Android 端 `this.a = new byte[0]`）
                buf.removeAll(keepingCapacity: true)
                offset = 0
                onInvalidStream?()
                return
            }
            let dataOffset = (Int(buf[offset + 5]) << 24)
                | (Int(buf[offset + 6]) << 16)
                | (Int(buf[offset + 7]) << 8)
                | Int(buf[offset + 8])
            let skip = max(dataOffset, 9) + 4   // header + PreviousTagSize0
            guard buf.count - offset >= skip else { return }
            offset += skip
            headerParsed = true
        }

        while true {
            let available = buf.count - offset
            guard available >= 11 else { break }

            let tagType = buf[offset]
            let dataSize = (Int(buf[offset + 1]) << 16)
                | (Int(buf[offset + 2]) << 8)
                | Int(buf[offset + 3])
            let timestamp = (Int(buf[offset + 7]) << 24)
                | (Int(buf[offset + 4]) << 16)
                | (Int(buf[offset + 5]) << 8)
                | Int(buf[offset + 6])
            // 11 字节 tag header + body + 4 字节 PreviousTagSize
            let total = 11 + dataSize + 4
            guard dataSize >= 2, available >= total else { break }

            if tagType == 8 {
                let p = offset + 11
                let soundFormat = (buf[p] >> 4) & 0x0F
                if soundFormat == 10 {                       // AAC
                    let aacPacketType = buf[p + 1]
                    if aacPacketType == 0, dataSize > 2 {
                        let start = p + 2
                        let asc = Data(buf[start..<(p + dataSize)])
                        if let cfg = Self.parseASC(asc) {
                            config = cfg
                            onConfig?(cfg)
                        }
                    } else if aacPacketType == 1, dataSize > 2 {
                        let start = p + 2
                        let frame = Data(buf[start..<(p + dataSize)])
                        packetsReceived += 1
                        onPacket?(frame, timestamp)
                    }
                }
            }
            offset += total
        }

        // 回收已消费前缀，避免长直播把内存撑爆
        if offset > 256 * 1024 {
            buf.removeFirst(offset)
            offset = 0
        }
    }

    /// AudioSpecificConfig: 5 bit objectType / 4 bit freqIndex / 4 bit channelConfig
    ///
    /// 只读前两个字节，与 Android 端 `LP.f()` + `La.<init>` 完全一致：
    /// channelConfig 为 0 时按 1 处理，为 7（7.1）时按 8 处理。
    static func parseASC(_ asc: Data) -> AACConfig? {
        guard asc.count >= 2 else { return nil }
        let b0 = asc[asc.startIndex]
        let b1 = asc[asc.startIndex + 1]
        let objectType = Int((b0 >> 3) & 0x1F)
        guard objectType == 2 || objectType == 5 else { return nil }   // AAC-LC / HE-AAC

        let freqIndex = Int(((b0 & 0x07) << 1) | ((b1 >> 7) & 0x01))
        var channelConfig = Int((b1 >> 3) & 0x0F)
        channelConfig = channelConfig == 7 ? 8 : max(1, channelConfig)

        guard freqIndex < sampleRates.count else { return nil }

        return AACConfig(
            asc: asc,
            sampleRateIndex: freqIndex,
            sampleRate: sampleRates[freqIndex],
            channels: channelConfig
        )
    }
}
