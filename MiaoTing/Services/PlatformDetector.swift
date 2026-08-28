//  PlatformDetector.swift
//  平台检测与 URL 处理
//
//  从 Android g.q / g.l / g.m / g.j / g.k 反编译重写
//

import Foundation

struct PlatformDetector {

    // 检测 URL 属于哪个平台（对应 g.q 方法）
    static func detectPlatform(from url: String) -> LivePlatform {
        let lower = url.lowercased()

        if lower.contains("kuaishou.com") || lower.contains("gifshow.com") || lower.contains("yximgs.com") {
            return .kuaishou
        }
        if lower.contains("xiaohongshu.com") || lower.contains("xhslink.com") || lower.contains("xhscdn.com") {
            return .xiaohongshu
        }
        if lower.contains("douyin.com") || lower.contains("iesdouyin.com") || lower.contains("douyincdn.com") {
            return .douyin
        }
        if lower.contains("taobao.com") || lower.contains("tmall.com") || lower.contains("alicdn.com") || lower.contains("tbzb.taobao.com") {
            return .taobao
        }

        return .unknown
    }

    // 获取平台对应的 Referer（对应 g.q 方法中的域名映射）
    static func referer(for url: String) -> String {
        let platform = detectPlatform(from: url)
        switch platform {
        case .kuaishou:
            return "https://live.kuaishou.com/"
        case .xiaohongshu:
            return "https://www.xiaohongshu.com/"
        case .taobao:
            return "https://tbzb.taobao.com/"
        case .douyin:
            return "https://www.douyin.com/"
        case .unknown:
            return "https://www.xiaohongshu.com/"
        }
    }

    // 获取平台对应的 User-Agent
    static func userAgent(for url: String) -> String {
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile Safari/605.1.15"
    }

    // 检测 URL 是否是已知平台的域名（对应 g.l）
    static func isKnownPlatformDomain(_ url: String) -> Bool {
        let lower = url.lowercased()
        let knownDomains = [
            "douyin.com", ".douyin.com",
            "kuaishou.com", ".kuaishou.com",
            "xiaohongshu.com", ".xiaohongshu.com",
            "xhslink.com", ".xhslink.com",
            "tbzb.taobao.com"
        ]
        return knownDomains.contains { lower.hasSuffix($0) || lower.contains($0) }
    }

    // 检测是否是 xhslink 短链（对应 g.m）
    static func isXHSLink(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("xhslink.com") || lower.contains(".xhslink.com")
    }

    // 清理 URL 中的 unicode 转义字符（对应 g.n）
    static func cleanUnicodeEscapes(_ str: String) -> String {
        var result = str
        let replacements: [(String, String)] = [
            ("\\u002F", "/"), ("\\u002f", "/"),
            ("\\u0026", "&"), ("\\u0026", "&"),
            ("\\/", "/"),
            ("&amp;", "&"),
            ("%5Cu002F", "/"), ("%5cu002f", "/"),
            ("%5Cu0026", "&"), ("%5cu0026", "&")
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    // 从文本中提取 URL（对应 g.h）
    static func extractURLs(from text: String) -> [String] {
        let pattern = "\\bhttps?://[^\\s\"'<>\\\\]+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var urls: [String] = []
        var seen = Set<String>()

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let range = Range(match.range, in: text) else { return }
            var url = String(text[range])
            if let decoded = url.removingPercentEncoding {
                url = decoded
            }
            url = url.trimmingCharacters(in: .whitespacesAndNewlines)
            // 清理尾部标点
            url = url.replacingOccurrences(of: "[),.;!?:\\]})）】》」』，。！？；：、]+$", with: "", options: .regularExpression)
            url = url.replacingOccurrences(of: "^[\"']+|[\"']+$", with: "", options: .regularExpression)
            if !seen.contains(url) {
                seen.insert(url)
                urls.append(url)
            }
        }
        return urls
    }

    // 清理标题中的平台后缀（对应 g.e）
    static func cleanTitle(_ raw: String) -> String {
        var result = cleanUnicodeEscapes(raw)
        // 去除 HTML 标签
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // 去除 HTML 实体引号
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        // 去除平台后缀（抖音|快手|小红书|淘宝）
        result = result.replacingOccurrences(of: "[-_|]\\s*(抖音|快手|小红书|淘宝).*$", with: "", options: .regularExpression)
        // 压缩空格
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // 判断标题是否是平台名称（对应 g.f）
    static func isPlatformName(_ title: String) -> Bool {
        let cleaned = cleanTitle(title)
        let platformNames = ["抖音", "快手", "小红书", "淘宝", "你的生活指南"]
        return platformNames.contains { cleaned == $0 }
    }

    // 为小红书直播构建默认 FLV 地址（对应 g.a 中 xhscdn 逻辑）
    static func buildXHSDefaultFLV(from pageURL: String) -> String? {
        guard let url = URL(string: pageURL),
              let host = url.host?.lowercased(),
              host.hasSuffix("xiaohongshu.com") else { return nil }

        let pathComponents = url.path.split(separator: "/")
        guard let lastComponent = pathComponents.last else { return nil }

        // 检查是否是纯数字房间 ID
        guard lastComponent.range(of: "^\\d+$", options: .regularExpression) != nil else { return nil }

        return "https://live-source-play-hw.xhscdn.com/live/\(lastComponent)_orig.flv"
    }
}
