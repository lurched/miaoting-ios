import Foundation

/// 候选流打分与择优，逐行对应 Android 端 `Lg.s()` 与 `Lg.b()`。
///
/// 打分 = 协议分 × 100 + 延迟档分 × 10000 + 地址特征分
/// 目的：在有 http-flv / hls / lls-sdp 混合候选时，优先拿**最实时、且只要音频**的那条。
enum CandidateRanker {

    static func latencyScore(_ tier: String) -> Int {
        switch tier {
        case "fastest-signal": return 5
        case "source-hunt": return 4
        case "usable": return 3
        case "compatible": return 2
        case "unknown": return 1
        default: return 0
        }
    }

    static func protocolScore(_ name: String) -> Int {
        switch name {
        case "lls-sdp": return 4
        case "http-flv": return 3
        case "hls": return 2
        default: return 0
        }
    }

    static func score(_ candidate: StreamCandidate) -> Int {
        let base = protocolScore(candidate.protocolName) * 100 + latencyScore(candidate.latencyTier) * 10_000
        return base + urlBonus(candidate)
    }

    private static func urlBonus(_ candidate: StreamCandidate) -> Int {
        let url = candidate.url.lowercased()

        // 小红书官方 CDN 的 _orig.flv：最干净的纯音频/原始流
        if url.contains("xhscdn.com/live/") && url.contains("_orig.flv") { return 90 }
        // 抖音 only_audio=1：明确只要音频，省流量且延迟最低
        if candidate.protocolName == "http-flv" && url.contains("only_audio=1") { return 80 }
        if url.contains("_or4.") { return 70 }

        let hasQualityMarker = url.contains("_stage0t000")
            || url.range(of: "_(hd5|md|sd5|ld5|hd|sd|ld)\\.", options: .regularExpression) != nil
        guard hasQualityMarker else { return 65 }

        if url.contains("_stage0t000hd.") || url.contains("_hd5.") { return 60 }
        if url.contains("_md.") { return 50 }
        if url.contains("_stage0t000sd5.") || url.contains("_stage0t000sd.") { return 40 }
        if url.contains("_stage0t000ld5.") || url.contains("_stage0t000ld.") { return 30 }
        return 0
    }

    /// 排序 + 择优。
    ///
    /// 和 Android 不同：**HLS 优先**。
    /// Android 用 MediaCodec 自己解 FLV 里的 AAC，很稳；
    /// iOS 只能靠 AudioConverter，裸 AAC 喂进去很容易整片失败。
    /// 而抖音同时提供 m3u8（我实测过，200 + 标准 HLS 列表，且不需要 Referer），
    /// 交给系统 AVPlayer 播是最稳的。
    static func best(from candidates: [StreamCandidate]) -> StreamCandidate? {
        let playable = candidates.filter { $0.playable && !$0.url.isEmpty }
        if let hls = playable.first(where: { $0.protocolName == "hls" }) { return hls }
        let sorted = playable.sorted { score($0) > score($1) }

        if let c = sorted.first(where: { $0.protocolName == "http-flv" && $0.url.lowercased().contains("only_audio=1") }) {
            return c
        }
        if let c = sorted.first(where: { $0.protocolName == "http-flv" && $0.url.lowercased().contains("_orig.flv") }) {
            return c
        }
        if let c = sorted.first(where: { $0.protocolName == "http-flv" }) { return c }
        if let c = sorted.first(where: { $0.protocolName == "hls" }) { return c }
        return sorted.first
    }

    /// 服务端返回的候选里，是否一条可播的都没有（`g.g()` 用来判断“暂未开播”）。
    static func hasPlayable(_ candidates: [StreamCandidate]) -> Bool {
        candidates.contains { $0.playable && !$0.url.isEmpty }
    }
}
