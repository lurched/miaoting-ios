//  FLVParser.swift
//  FLV 流解析器
//
//  从 Android P 类 + c 类反编译重写
//  负责从 HTTP-FLV 流中提取 AAC 音频帧
//

import Foundation

// FLV 数据类型
enum FLVDataType: UInt8 {
    case audio = 8
    case video = 9
    case script = 18
}

// FLV 标签头（11 字节）
struct FLVTagHeader {
    let type: FLVDataType
    let dataSize: Int       // 3 bytes big-endian
    var timestamp: Int      // 3 bytes + 1 byte extended
    let streamID: Int       // 3 bytes (always 0)

    init?(data: Data) {
        guard data.count >= 11 else { return nil }
        let typeByte = data[0]
        guard let type = FLVDataType(rawValue: typeByte) else { return nil }
        self.type = type

        self.dataSize = (Int(data[1]) << 16) | (Int(data[2]) << 8) | Int(data[3])
        self.timestamp = (Int(data[4]) << 16) | (Int(data[5]) << 8) | Int(data[6])
        let extTS = Int(data[7])
        self.timestamp |= (extTS << 24)
        self.streamID = (Int(data[8]) << 16) | (Int(data[9]) << 8) | Int(data[10])
    }
}

// AAC 音频参数
struct AACConfig {
    let sampleRate: Int
    let channelCount: Int

    // 从 AAC AudioSpecificConfig (2 bytes) 解析
    init?(data: Data) {
        guard data.count >= 2 else { return nil }
        let byte0 = data[0]
        let byte1 = data[1]

        let objecttype = (byte0 >> 3) & 0x1F
        let srIndex = ((byte0 & 0x07) << 1) | (byte1 >> 7)
        let channels = (byte1 >> 3) & 0x0F

        // AAC 采样率表
        let sampleRates = [
            96000, 88200, 64000, 48000,
            44100, 32000, 24000, 22050,
            16000, 12000, 11025, 8000,
            7350
        ]

        if srIndex < sampleRates.count {
            self.sampleRate = sampleRates[Int(srIndex)]
        } else {
            self.sampleRate = 44100
        }

        self.channelCount = channels > 0 ? Int(channels) : 2

        _ = objecttype  // 通常是 2 (AAC-LC)
    }

    init(sampleRate: Int, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

// 音频帧
struct AudioFrame {
    let data: Data          // AAC 原始帧数据（不含 ADTS 头）
    let timestamp: Int64    // PTS (ms)
    let config: AACConfig?
}

// FLV 解析器
class FLVParser {

    // FLV 头（9 字节）
    private struct FLVHeader {
        let hasVideo: Bool
        let hasAudio: Bool

        init?(data: Data) {
            guard data.count >= 9 else { return nil }
            // "FLV" 签名
            guard data[0] == 0x46, data[1] == 0x4C, data[2] == 0x56 else { return nil }
            let flags = data[4]
            self.hasAudio = (flags & 0x04) != 0
            self.hasVideo = (flags & 0x01) != 0
        }
    }

    private var buffer = Data()
    private var parsedHeader = false
    private var aacConfig: AACConfig?
    private var previousTagSize: Int = 0

    // 回调
    var onAudioFrame: ((AudioFrame) -> Void)?
    var onConfigReady: ((AACConfig) -> Void)?
    var onError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    // 统计
    private(set) var totalBytesParsed: Int = 0
    private(set) var totalAudioFrames: Int = 0

    // 音频帧排序缓冲（对应 P.b 中的时间戳排序逻辑）
    private var frameBuffer: [AudioFrame] = []
    private let maxBufferSize = 200

    // 接收新数据
    func feed(_ data: Data) {
        buffer.append(data)
        totalBytesParsed += data.count
        parse()
    }

    // 重置
    func reset() {
        buffer.removeAll()
        parsedHeader = false
        aacConfig = nil
        previousTagSize = 0
        frameBuffer.removeAll()
        totalBytesParsed = 0
        totalAudioFrames = 0
    }

    // 解析循环
    private func parse() {
        if !parsedHeader {
            guard buffer.count >= 9 else { return }
            let header = FLVHeader(data: buffer.prefix(9))
            guard let header = header else {
                onError?("无效的 FLV 头")
                return
            }
            buffer.removeFirst(9)
            parsedHeader = true
            onStatus?("FLV 头已解析，音频: \(header.hasAudio)")

            // 跳过 PreviousTagSize0 (4 bytes)
            guard buffer.count >= 4 else { return }
            buffer.removeFirst(4)
        }

        while buffer.count >= 15 {  // 11 (tag header) + 4 (prev tag size)
            // 解析标签头
            let headerData = buffer.prefix(11)
            guard let tagHeader = FLVTagHeader(data: headerData) else {
                // 无效数据，跳过一个字节
                buffer.removeFirst()
                continue
            }

            let totalTagSize = 11 + tagHeader.dataSize + 4  // header + data + prev size

            if buffer.count < totalTagSize {
                break  // 数据不完整，等待更多数据
            }

            // 提取标签数据
            let tagData = buffer.subdata(in: 11..<(11 + tagHeader.dataSize))

            // 处理音频标签
            if tagHeader.type == .audio {
                processAudioTag(data: tagData, timestamp: Int64(tagHeader.timestamp))
            }

            // 移到下一个标签
            buffer.removeFirst(totalTagSize)
        }
    }

    // 处理音频标签
    private func processAudioTag(data: Data, timestamp: Int64) {
        guard data.count >= 2 else { return }

        // FLV 音频标签头：
        // Byte 0: [SoundFormat(4 bits)][SampleRate(2 bits)][SampleSize(1 bit)][SoundType(1 bit)]
        // 如果是 AAC (SoundFormat=10)，Byte 1: AACPacketType
        let soundFormat = (data[0] >> 4) & 0x0F

        if soundFormat == 10 {  // AAC
            let aacPacketType = data[1]

            if aacPacketType == 0 {
                // AudioSpecificConfig
                let configData = data.subdata(in: 2..<data.count)
                let config = AACConfig(data: configData)
                if let config = config {
                    self.aacConfig = config
                    onConfigReady?(config)
                    onStatus?("AAC 配置已获取: \(config.sampleRate)Hz, \(config.channelCount)ch")
                }
            } else if aacPacketType == 1 {
                // AAC 原始帧数据
                let frameData = data.subdata(in: 2..<data.count)
                let frame = AudioFrame(
                    data: frameData,
                    timestamp: timestamp,
                    config: aacConfig
                )
                totalAudioFrames += 1

                // 排序缓冲（对应 P.b 逻辑）
                addToBuffer(frame)
                flushSortedFrames()
            }
        }
    }

    // 添加到排序缓冲区
    private func addToBuffer(_ frame: AudioFrame) {
        frameBuffer.append(frame)

        // 缓冲区过大时丢弃最旧的帧
        if frameBuffer.count > maxBufferSize {
            // 找到时间戳范围
            if let minTS = frameBuffer.map({ $0.timestamp }).min(),
               let maxTS = frameBuffer.map({ $0.timestamp }).max() {
                let range = maxTS - minTS
                if range > 200 {  // 200ms 以上的延迟，丢弃旧帧
                    let cutoff = maxTS - 80
                    frameBuffer.removeAll { $0.timestamp < cutoff }
                    onStatus?("正在保持实时收听")
                }
            }
        }
    }

    // 按时间戳排序并输出帧
    private func flushSortedFrames() {
        guard frameBuffer.count >= 2 else {
            // 至少需要 2 帧才能判断时间戳连续性
            if frameBuffer.count == 1 {
                onAudioFrame?(frameBuffer.removeFirst())
            }
            return
        }

        // 按时间戳排序
        frameBuffer.sort { $0.timestamp < $1.timestamp }

        // 输出所有帧
        while !frameBuffer.isEmpty {
            let frame = frameBuffer.removeFirst()
            onAudioFrame?(frame)
        }
    }
}
