import Foundation

/// 分享文案 → 可播放地址的本地解析。
///
/// 逐条对应 Android 端 `Lg` 里的静态工具：
///   `h()` 抽 URL、`l()` 平台域名判定、`m()` 小红书短链判定、`o()` 挑目标链接、
///   `e()` 标题清洗、`f()` 标题过滤、`j()/k()` FLV/HLS 判定、`d()` 短链展开。
enum LinkExtractor {

    private static let platformHosts = [
        "douyin.com", "kuaishou.com", "xiaohongshu.com",
        "xhslink.com", "tbzb.taobao.com",
        // 抖音短链最终会落到 webcast.amemv.com 的 reflow 页，这一页里直接有 flv
        "amemv.com"
    ]

    // MARK: - URL 抽取

    static func urls(in text: String) -> [String] {
        let normalized = unescape(text)
        guard let regex = try? NSRegularExpression(pattern: "\\bhttps?://[^\\s\"'<>\\\\]+") else { return [] }
        let ns = normalized as NSString
        var result: [String] = []
        var seen = Set<String>()

        regex.enumerateMatches(in: normalized, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            var raw = ns.substring(with: match.range)
            if let decoded = raw.removingPercentEncoding { raw = decoded }
            raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            raw = raw.replacingOccurrences(
                of: "[),.;!?:\\]}\u{FF09}\u{3011}\u{300B}\u{300D}\u{300F}\u{FF0C}\u{3002}\u{FF01}\u{FF1F}\u{FF1B}\u{FF1A}\u{3001}]+$",
                with: "", options: .regularExpression)
            raw = raw.replacingOccurrences(of: "^[\"']+|[\"']+$", with: "", options: .regularExpression)
            if seen.insert(raw).inserted { result.append(raw) }
        }
        return result
    }

    /// `g.n()`：还原被平台转义过的链接。
    static func unescape(_ text: String) -> String {
        var s = text
        for (from, to) in [
            ("\\u002F", "/"), ("\\u002f", "/"),
            ("\\u0026", "&"), ("%5Cu002F", "/"), ("%5cu002f", "/"),
            ("%5Cu0026", "&"), ("%5cu0026", "&"),
            ("\\/", "/"), ("&amp;", "&")
        ] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }

    // MARK: - 判定

    static func host(of url: String) -> String {
        URL(string: url)?.host?.lowercased() ?? ""
    }

    static func isPlatformLink(_ url: String) -> Bool {
        let h = host(of: url)
        guard !h.isEmpty else { return false }
        return platformHosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    static func isXHSShortLink(_ url: String) -> Bool {
        let h = host(of: url)
        return h == "xhslink.com" || h.hasSuffix(".xhslink.com")
    }

    static func isFLV(_ url: String) -> Bool {
        let s = url.lowercased()
        return s.contains(".flv") || s.contains("format=flv") || s.contains("pull-flv")
    }

    static func isHLS(_ url: String) -> Bool {
        let s = url.lowercased()
        return s.contains(".m3u8") || s.contains("pull-hls")
    }

    // MARK: - 选择目标

    /// `g.o()`：优先平台直播间链接，其次 FLV/HLS 直链，最后原串。
    static func pickTarget(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = urls(in: unescape(trimmed))
        if let direct = list.first(where: { isPlatformLink($0) }) { return direct }
        if let stream = list.first(where: { isFLV($0) || isHLS($0) }) { return stream }
        return trimmed
    }

    // MARK: - 标题

    /// `g.e()`：去 HTML 标签、去平台后缀、压空白、截断 80。
    static func cleanTitle(_ text: String) -> String {
        var s = unescape(text)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        s = s.replacingOccurrences(of: "[-_|]\\s*(抖音|快手|小红书|淘宝).*$",
                                   with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > 80 ? String(s.prefix(80)) : s
    }

    /// `g.f()`：过滤掉纯平台名。
    static func usableTitle(_ text: String) -> String {
        let t = cleanTitle(text)
        guard t.count >= 2 else { return "" }
        let banned: Set<String> = ["抖音", "快手", "小红书", "淘宝", "你的生活指南"]
        return banned.contains(t) ? "" : t
    }

    private static let liveTitlePatterns = [
        "#\\s*([^#\\n\\r\u{FF0C}\u{3002}\u{FF01}\u{FF1F}\u{FF1B}]{1,80}?)\\s*正在直播",
        "\u{3010}([^\u{3011}\\n\\r]{1,80}?)\u{3011}\\s*正在直播"
    ]

    /// 从「XX正在直播」的分享文案里取房间名。
    static func titleFromShareText(_ text: String) -> String? {
        let normalized = unescape(text)
        for pattern in liveTitlePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = normalized as NSString
            if let match = regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1 {
                let candidate = usableTitle(ns.substring(with: match.range(at: 1)))
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }

    // MARK: - 小红书短链

    /// `g.d()`：跟随 xhslink.com 跳转，拿到真正的直播间地址。
    static func resolveXHSShortLink(_ url: String) async -> String {
        guard isXHSShortLink(url) else { return url }

        var request = URLRequest(url: URL(string: url)!)
        request.setValue(FLVStreamLoader.mobileUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let finalURL = response.url?.absoluteString else { return url }
            let target = pickTarget(from: finalURL)
            if isPlatformLink(target), !isXHSShortLink(target) { return target }
            return url
        } catch {
            return url
        }
    }

    /// 小红书直播间号 → 官方 CDN 直链（`g.a()` 里的兜底拼法）。
    ///
    /// 形如 https://www.xiaohongshu.com/live/1234567890
    ///   → https://live-source-play-hw.xhscdn.com/live/1234567890_orig.flv
    static func xhsDirectURL(from roomURL: String) -> String? {
        guard let url = URL(string: roomURL), host(of: roomURL).hasSuffix("xiaohongshu.com") else { return nil }
        let parts = url.pathComponents.filter { !$0.isEmpty }
        guard let id = parts.last(where: { $0.range(of: "^\\d+$", options: .regularExpression) != nil }) else {
            return nil
        }
        return "https://live-source-play-hw.xhscdn.com/live/\(id)_orig.flv"
    }
}
