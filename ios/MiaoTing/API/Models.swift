import Foundation

typealias JSONDictionary = [String: Any]

struct Plan: Identifiable, Equatable {
    let id: String
    let label: String
    let title: String
    let detail: String
    let priceCents: Int
    let originalPriceCents: Int

    init?(json: JSONDictionary) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        label = json["label"] as? String ?? ""
        title = json["title"] as? String ?? ""
        detail = json["description"] as? String ?? ""
        priceCents = json["priceCents"] as? Int ?? 0
        originalPriceCents = json["originalPriceCents"] as? Int ?? 0
    }

    var priceText: String { Self.money(priceCents) }
    var originalPriceText: String { Self.money(originalPriceCents) }
    var hasDiscount: Bool { originalPriceCents > priceCents }

    private static func money(_ cents: Int) -> String {
        let value = Double(cents) / 100
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "¥\(Int(value))"
            : String(format: "¥%.2f", value)
    }
}

struct Room: Identifiable, Equatable {
    let id: String
    let platform: String
    let name: String
    let roomUrl: String
    let likeCount: Int
    let createdAt: String
    let ownedByCurrentUser: Bool
    let priority: Int

    init?(json: JSONDictionary) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        platform = json["platform"] as? String ?? ""
        name = json["name"] as? String ?? "直播间"
        roomUrl = json["roomUrl"] as? String ?? ""
        likeCount = json["likeCount"] as? Int ?? 0
        createdAt = json["createdAt"] as? String ?? ""
        ownedByCurrentUser = json["ownedByCurrentUser"] as? Bool ?? false
        priority = json["priority"] as? Int ?? 0
    }

    /// 对应 Android 端 `LN.onDraw` 里的「抖 / 快 / 薯 / 淘」徽标。
    var platformBadge: String {
        switch platform {
        case "douyin": return "抖"
        case "kuaishou": return "快"
        case "xiaohongshu": return "薯"
        case "taobao": return "淘"
        default: return ""
        }
    }

    var platformName: String {
        switch platform {
        case "douyin": return "抖音"
        case "kuaishou": return "快手"
        case "xiaohongshu": return "小红书"
        case "taobao": return "淘宝"
        default: return "直播间"
        }
    }
}

struct Entitlement: Equatable {
    let state: String
    let isLifetime: Bool
    let expiresAt: String
    let remainingMs: Double
    let orderId: String

    init?(json: JSONDictionary?) {
        guard let json else { return nil }
        state = json["state"] as? String ?? "inactive"
        isLifetime = json["isLifetime"] as? Bool ?? false
        expiresAt = json["expiresAt"] as? String ?? ""
        remainingMs = (json["remainingMs"] as? NSNumber)?.doubleValue ?? 0
        orderId = json["orderId"] as? String ?? ""
    }

    /// 与 Android 端 `MainActivity.B()` 的判定完全一致：
    /// state == active 且（永久 或 remainingMs > 0 或 expiresAt 在未来）。
    var isActive: Bool {
        guard state == "active" else { return false }
        if isLifetime { return true }
        if remainingMs > 0 { return true }
        guard !expiresAt.isEmpty else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date > Date() }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: expiresAt) { return date > Date() }
        return false
    }

    var summary: String {
        guard isActive else { return "未开通" }
        if isLifetime { return "终身授权" }
        if let date = Self.parse(expiresAt) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "yyyy/MM/dd HH:mm"
            return "有效期至 \(f.string(from: date))"
        }
        if remainingMs > 0 {
            let hours = Int(remainingMs / 3_600_000)
            return hours >= 24 ? "剩余 \(hours / 24) 天" : "剩余 \(max(hours, 1)) 小时"
        }
        return "已开通"
    }

    private static func parse(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? {
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: text)
        }()
    }
}

struct UserProfile: Equatable {
    let id: String
    let phoneNumber: String
    let nickname: String

    init?(json: JSONDictionary?) {
        guard let json else { return nil }
        id = json["id"] as? String ?? ""
        phoneNumber = json["phoneNumber"] as? String ?? ""
        nickname = json["nickname"] as? String ?? ""
    }

    var display: String {
        if !nickname.isEmpty { return nickname }
        guard phoneNumber.count == 11 else { return "已登录" }
        return String(phoneNumber.prefix(3)) + "****" + String(phoneNumber.suffix(4))
    }
}

struct StreamCandidate {
    let url: String
    let protocolName: String
    let latencyTier: String
    let playable: Bool

    init?(json: JSONDictionary) {
        guard let url = json["url"] as? String, !url.isEmpty else { return nil }
        self.url = url
        protocolName = json["protocolName"] as? String ?? json["protocol"] as? String ?? ""
        latencyTier = json["latencyTier"] as? String ?? "unknown"
        playable = json["playable"] as? Bool ?? true
    }
}

struct DiscoverResult {
    let platform: String
    let roomTitle: String
    let finalUrl: String
    let candidates: [StreamCandidate]
    let hasRateLimit: Bool
    let hasNoLiveStream: Bool
    let hasAccessChallenge: Bool
    let error: String

    init(json: JSONDictionary) {
        platform = json["platform"] as? String ?? ""
        roomTitle = json["roomTitle"] as? String ?? ""
        finalUrl = json["finalUrl"] as? String ?? ""

        let result = json["result"] as? JSONDictionary
        let rawCandidates = result?["candidates"] as? [JSONDictionary] ?? []
        candidates = rawCandidates.compactMap(StreamCandidate.init)

        let diagnostics = json["diagnostics"] as? JSONDictionary ?? [:]
        hasRateLimit = diagnostics["hasRateLimit"] as? Bool ?? false
        hasNoLiveStream = diagnostics["hasNoLiveStream"] as? Bool ?? false
        hasAccessChallenge = diagnostics["hasAccessChallenge"] as? Bool ?? false
        error = json["error"] as? String ?? ""
    }

    /// 对应 Android 端 `g.g()`：诊断优先于错误文案。
    var failureMessage: String? {
        let prefix = Self.badge(platform)
        if hasRateLimit { return "\(prefix)请求繁忙，建议稍后重试。" }
        if hasNoLiveStream { return "直播间暂未开播。" }
        if hasAccessChallenge { return "\(prefix)需要完成平台验证，完成后重新识别。" }
        if !error.isEmpty { return error }
        return nil
    }

    static func badge(_ platform: String) -> String {
        switch platform {
        case "douyin": return "抖抖"
        case "kuaishou": return "快快"
        case "xiaohongshu": return "红薯"
        case "taobao": return "淘淘"
        default: return "直播间"
        }
    }
}

struct CommunityGroup {
    let version: String
    let qrDataURL: String

    init?(json: JSONDictionary) {
        version = json["version"] as? String ?? ""
        qrDataURL = json["qrCodeDataUrl"] as? String ?? ""
        if version.isEmpty && qrDataURL.isEmpty { return nil }
    }
}

struct WelcomeMessage {
    let title: String
    let message: String
    let primaryLabel: String
    let secondaryLabel: String
    let guideURL: String

    init?(json: JSONDictionary) {
        title = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        message = (json["message"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        primaryLabel = (json["primaryLabel"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        secondaryLabel = (json["secondaryLabel"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guideURL = (json["guideUrl"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if title.isEmpty || message.isEmpty { return nil }
    }
}

struct UpdateInfo {
    let hasUpdate: Bool
    let versionName: String
    let downloadURL: String
    let notes: String

    init(json: JSONDictionary) {
        hasUpdate = json["hasUpdate"] as? Bool ?? false
        versionName = json["versionName"] as? String ?? ""
        downloadURL = json["downloadUrl"] as? String ?? ""
        notes = json["releaseNotes"] as? String ?? json["notes"] as? String ?? ""
    }
}

struct SessionPayload {
    let token: String
    let user: UserProfile?
    let entitlement: Entitlement?
    let isNewUser: Bool
}
