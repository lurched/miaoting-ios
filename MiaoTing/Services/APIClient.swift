//  APIClient.swift
//  SyncroZero API 客户端
//
//  从 Android g.r / g.i / g.g / g.c 反编译重写
//  对应 syncrozero.com 后端 API
//

import Foundation

// API 响应模型
struct APIResponse: Codable {
    let roomTitle: String?
    let finalUrl: String?
    let streams: [StreamInfo]?
    let diagnostics: Diagnostics?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case roomTitle
        case finalUrl
        case streams
        case diagnostics
        case error
    }
}

struct StreamInfo: Codable {
    let playable: Bool?
    let protocolName: String?
    let protocolLabel: String?
    let url: String?
    let latencyTier: String?

    enum CodingKeys: String, CodingKey {
        case playable
        case protocolName = "protocol"
        case protocolLabel
        case url
        case latencyTier
    }
}

struct Diagnostics: Codable {
    let platform: String?
    let hasRateLimit: Bool?
    let hasNoLiveStream: Bool?
    let hasAccessChallenge: Bool?
}

// 自定义错误
enum APIError: Error, LocalizedError {
    case invalidURL
    case noResponse
    case httpError(Int, String)
    case parseError(String)
    case rateLimited
    case notLive
    case accessChallenge
    case captchaDetected

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .noResponse: return "服务器无响应"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .parseError(let msg): return "解析错误: \(msg)"
        case .rateLimited: return "请求繁忙，建议稍后重试"
        case .notLive: return "直播间暂未开播"
        case .accessChallenge: return "需要完成平台验证，完成后重新识别"
        case .captchaDetected: return "检测到验证码页面，请稍后重试"
        }
    }
}

class APIClient {
    static let shared = APIClient()

    private let baseURL = "https://syncrozero.com"
    private let session: URLSession
    private let timeout: TimeInterval = 15

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - 解析直播 URL（对应 g.i → g.r）
    func resolveLiveURL(_ inputURL: String, token: String) async throws -> RoomInfo {
        let cleanedURL = PlatformDetector.cleanUnicodeEscapes(inputURL)

        // 构建请求 URL
        let endpoint: String
        if cleanedURL.hasPrefix("http") {
            endpoint = cleanedURL
        } else {
            endpoint = baseURL + cleanedURL
        }

        guard let url = URL(string: endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noResponse
        }

        if httpResponse.statusCode != 200 {
            let msg = httpResponse.value(forHTTPHeaderField: "reason") ?? "未知错误"
            throw APIError.httpError(httpResponse.statusCode, msg)
        }

        // 解析 JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseError("无效的 JSON 响应")
        }

        // 检查错误
        if let error = json["error"] as? String, !error.isEmpty {
            throw APIError.parseError(error)
        }

        // 检查诊断信息（对应 g.g 中的 diagnostics 处理）
        if let diagnostics = json["diagnostics"] as? [String: Any] {
            if let hasRateLimit = diagnostics["hasRateLimit"] as? Bool, hasRateLimit {
                throw APIError.rateLimited
            }
            if let hasNoLive = diagnostics["hasNoLiveStream"] as? Bool, hasNoLive {
                throw APIError.notLive
            }
            if let hasChallenge = diagnostics["hasAccessChallenge"] as? Bool, hasChallenge {
                throw APIError.accessChallenge
            }
        }

        // 检查验证码（对应 g.g 中的正则检测）
        if let finalUrl = json["finalUrl"] as? String {
            let captchaPattern = "验证码|安全验证|验证中间页|中间页|captcha|security verification"
            if let regex = try? NSRegularExpression(pattern: captchaPattern, options: .caseInsensitive),
               regex.firstMatch(in: finalUrl, range: NSRange(finalUrl.startIndex..., in: finalUrl)) != nil {
                throw APIError.captchaDetected
            }
        }

        // 构建房间信息
        var room = RoomInfo()
        room.rawJSON = json
        room.finalURL = json["finalUrl"] as? String ?? ""

        // 房间标题（对应 g.g 中 roomTitle 提取）
        if let roomTitle = json["roomTitle"] as? String {
            room.roomTitle = PlatformDetector.cleanTitle(roomTitle)
        }

        // 解析流地址列表（对应 g.c / g.g）
        if let streams = json["streams"] as? [[String: Any]] {
            for stream in streams {
                let playable = stream["playable"] as? Bool ?? false
                let proto = stream["protocol"] as? String ?? ""
                let protoLabel = stream["protocolName"] as? String ?? proto
                let url = stream["url"] as? String ?? ""
                let latency = stream["latencyTier"] as? String ?? "unknown"

                if !url.isEmpty {
                    room.streamURLs.append(StreamURL(
                        url: url,
                        protocolName: proto,
                        protocolLabel: protoLabel,
                        playable: playable,
                        latencyTier: latency
                    ))
                }
            }
        }

        // 平台检测
        let platform = PlatformDetector.detectPlatform(from: cleanedURL)
        room.platform = platform

        // 如果没有从 API 获取到流地址，尝试构建默认 FLV（对应 g.a 中的 xhscdn fallback）
        if room.streamURLs.isEmpty {
            if let defaultFLV = PlatformDetector.buildXHSDefaultFLV(from: cleanedURL) {
                room.streamURLs.append(StreamURL(
                    url: defaultFLV,
                    protocolName: "http-flv",
                    protocolLabel: "http-flv",
                    playable: true,
                    latencyTier: "unknown"
                ))
            }
        }

        // 排序流地址：优先 http-flv，其次 hls（对应 g.s 排序逻辑）
        room.streamURLs.sort { a, b in
            return StreamSorter.priority(a) < StreamSorter.priority(b)
        }

        return room
    }

    // MARK: - 跟随重定向获取最终 URL（对应 g.d）
    func resolveRedirects(for url: String) async throws -> String {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(PlatformDetector.userAgent(for: url.absoluteString), forHTTPHeaderField: "User-Agent")
        request.setValue(PlatformDetector.referer(for: url.absoluteString), forHTTPHeaderField: "Referer")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)

        let (_, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           let finalURL = httpResponse.url?.absoluteString {
            return PlatformDetector.cleanUnicodeEscapes(finalURL)
        }

        return url.absoluteString
    }

    // MARK: - 从 HTML 页面提取标题（对应 g.a 中的 title 正则提取）
    func extractTitleFromHTML(_ html: String) -> String? {
        // 尝试 roomTitle / nickName 正则提取
        let patterns: [(String, String)] = [
            ("\"roomTitle\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"", "$1"),
            ("\"nickName\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"", "$1"),
            ("<title[^>]*>([\\s\\S]*?)</title>", "$1")
        ]

        for (pattern, _) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, range: range),
                   match.numberOfRanges > 1,
                   let r = Range(match.range(at: 1), in: html) {
                    let title = String(html[r])
                    let cleaned = PlatformDetector.cleanTitle(title)
                    if !cleaned.isEmpty && !PlatformDetector.isPlatformName(cleaned) {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }
}

// 流地址排序优先级（对应 g.s）
struct StreamSorter {
    static func priority(_ stream: StreamURL) -> Int {
        // 优先级：http-flv > hls > lls-sdp > 其他
        // 额外：only_audio=1 的流优先
        let proto = stream.protocolName.lowercased()
        let url = stream.url.lowercased()

        var base: Int
        switch proto {
        case "http-flv": base = 0
        case "hls": base = 1
        case "lls-sdp": base = 2
        default: base = 3
        }

        // 含 only_audio=1 的优先
        if url.contains("only_audio=1") {
            base -= 5
        }

        // xhscdn.com/live/ 且 _orig.flv 优先
        if url.contains("xhscdn.com/live/") && url.contains("_orig.flv") {
            base -= 3
        }

        return base
    }
}
