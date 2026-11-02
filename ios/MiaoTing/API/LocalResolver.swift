import Foundation

/// 服务端识别失败时的本地兜底：直接抓直播间页面 HTML，从里面抠流地址。
///
/// 对应 Android 端 `Lv`（case 2）里的那段 fallback 与 `Lg.a()`。
enum LocalResolver {

    struct Result {
        let title: String
        var candidates: [StreamCandidate]
    }

    private static let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    static func hunt(pageURL: String) async -> Result {
        guard LinkExtractor.isPlatformLink(pageURL) else {
            return Result(title: "", candidates: [])
        }

        var html = ""
        var finalURL = pageURL
        do {
            var request = URLRequest(url: URL(string: pageURL)!)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                             forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue(referer(for: pageURL), forHTTPHeaderField: "Referer")

            let (data, response) = try await URLSession.shared.data(for: request)
            finalURL = response.url?.absoluteString ?? pageURL
            html = decode(data)
        } catch {
            return Result(title: "", candidates: [])
        }

        var candidates = extractCandidates(from: html)

        // 小红书：直播间号直接拼官方 CDN 的 _orig.flv，比页面里的 HLS 更实时。
        if let direct = LinkExtractor.xhsDirectURL(from: finalURL) {
            candidates.insert(StreamCandidate(url: direct, protocolName: "http-flv", latencyTier: "unknown", playable: true),
                              at: 0)
        }

        let title = extractTitle(from: html) 
        return Result(title: title, candidates: CandidateRanker.dedup(candidates))
    }

    // MARK: - 抽取

    static func extractCandidates(from html: String) -> [StreamCandidate] {
        var result: [StreamCandidate] = []
        for raw in LinkExtractor.urls(in: html) {
            let lower = raw.lowercased()
            if LinkExtractor.isFLV(raw) && lower.contains("only_audio=1") {
                result.append(StreamCandidate(url: raw, protocolName: "http-flv", latencyTier: "unknown", playable: true))
            } else if lower.contains(".sdp") || lower.contains("pull-lls") {
                result.append(StreamCandidate(url: raw, protocolName: "lls-sdp", latencyTier: "unknown", playable: true))
            } else if LinkExtractor.isFLV(raw) {
                result.append(StreamCandidate(url: raw, protocolName: "http-flv", latencyTier: "unknown", playable: true))
            } else if LinkExtractor.isHLS(raw) {
                result.append(StreamCandidate(url: raw, protocolName: "hls", latencyTier: "unknown", playable: true))
            }
        }
        return result
    }

    /// 先找页面内 JSON 的 nickName/nickname/roomTitle/title，再退回 <title>。
    static func extractTitle(from html: String) -> String {
        for key in ["nickName", "nickname", "roomTitle", "title"] {
            let pattern = "\\\\?\"\(key)\\\\?\"\\s*:\\s*\\\\?\"((?:\\\\\\\\.|[^\"\\\\])*)\\\\?\""
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = html as NSString
            if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1 {
                let value = LinkExtractor.usableTitle(ns.substring(with: match.range(at: 1)))
                if !value.isEmpty { return value }
            }
        }
        if let regex = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
           match.numberOfRanges > 1 {
            return LinkExtractor.cleanTitle((html as NSString).substring(with: match.range(at: 1)))
        }
        return ""
    }

    static func referer(for url: String) -> String {
        let host = LinkExtractor.host(of: url)
        if host.contains("kuaishou.com") { return "https://live.kuaishou.com/" }
        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") { return "https://www.xiaohongshu.com/" }
        if host == "tbzb.taobao.com" { return "https://tbzb.taobao.com/" }
        return "https://www.douyin.com/"
    }

    private static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gbk = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gbk)) ?? ""
    }
}

extension CandidateRanker {
    /// 按「协议 + host + path + 是否只要音频」去重，等价 Android 端 `Lg.a()` 里的 key。
    static func dedup(_ candidates: [StreamCandidate]) -> [StreamCandidate] {
        var seen = Set<String>()
        var output: [StreamCandidate] = []
        for candidate in candidates {
            let url = candidate.url.lowercased()
            let host = LinkExtractor.host(of: candidate.url)
            let path = URL(string: candidate.url)?.path ?? ""
            let audio = url.contains("only_audio=1") ? "audio" : "av"
            let key = "\(candidate.protocolName):\(host):\(path):\(audio)"
            if seen.insert(key).inserted {
                output.append(candidate)
            }
        }
        return output.sorted { score($0) > score($1) }
    }
}
