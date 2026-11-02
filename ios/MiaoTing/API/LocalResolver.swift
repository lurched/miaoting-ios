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

        var candidates: [StreamCandidate] = []
        var title = ""

        for url in candidatePageURLs(pageURL) {
            guard let page = await fetch(url) else { continue }

            var list = extractCandidates(from: page.html)
            if let direct = LinkExtractor.xhsDirectURL(from: page.finalURL) {
                list.insert(StreamCandidate(url: direct, protocolName: "http-flv", latencyTier: "unknown"), at: 0)
            }
            if let t = extractTitle(from: page.html), !t.isEmpty, title.isEmpty {
                title = t
            }
            candidates.append(contentsOf: list)
            if CandidateRanker.hasPlayable(candidates) { break }
        }

        return Result(title: title, candidates: CandidateRanker.dedup(candidates))
    }

    /// 抖音的「关注页直播」链接是 `www.douyin.com/follow/live/<id>`，
    /// 真正的直播间页在 `live.douyin.com/<id>`，两个都试一次。
    static func candidatePageURLs(_ pageURL: String) -> [String] {
        var urls = [pageURL]
        guard LinkExtractor.host(of: pageURL).contains("douyin.com") else { return urls }
        let parts = URL(string: pageURL)?.pathComponents.filter { !$0.isEmpty } ?? []
        if let index = parts.firstIndex(of: "live"), index + 1 < parts.count {
            let roomId = parts[index + 1]
            if roomId.range(of: "^\\d+$", options: .regularExpression) != nil {
                urls.append("https://live.douyin.com/\(roomId)")
            }
        }
        return urls
    }

    static func fetch(_ url: String) async -> (html: String, finalURL: String)? {
        guard let target = URL(string: url) else { return nil }
        var request = URLRequest(url: target)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(referer(for: url), forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let finalURL = response.url?.absoluteString ?? url
            return (decode(data), finalURL)
        } catch {
            return nil
        }
    }

    // MARK: - 抽取

    static func extractCandidates(from html: String) -> [StreamCandidate] {
        var result: [StreamCandidate] = []
        // 抖音把直播数据塞在 RENDER_DATA 里，整段是 percent-encoded 的 JSON，
        // 不解码的话正则根本匹配不到 https://。
        for raw in LinkExtractor.urls(in: percentDecoded(html)) {
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

    /// 把 `%3A%2F%2F` 这类整体编码的片段还原，最多解两轮（有的页面会二次编码）。
    static func percentDecoded(_ html: String) -> String {
        var text = html
        for _ in 0..<2 {
            guard text.contains("%3A") || text.contains("%3a") || text.contains("%2F") || text.contains("%2f") else {
                return text
            }
            guard let decoded = text.removingPercentEncoding, decoded != text else { return text }
            text = decoded
        }
        return text
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
