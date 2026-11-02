import Foundation

struct APIError: LocalizedError {
    let message: String
    let statusCode: Int

    var errorDescription: String? { message }
}

/// 后端接口客户端。路径与字段全部来自 Android 端 `Lg.r()` / `Lv` / `Lw` / `Lx` / `Lz`。
///
/// 服务端为 https://syncrozero.com，鉴权走 `Authorization: Bearer <sessionToken>`。
final class APIClient {

    static let shared = APIClient()

    /// 服务端在登录/下单请求里会校验 deviceType。Android 端固定发 "android-client"；
    /// 这里默认发 "ios-client"，若服务端白名单未放行，切回 android-client 即可（服务端不校验设备真实类型）。
    var deviceType = "ios-client"

    let baseURL = URL(string: "https://syncrozero.com")!

    private let session: URLSession
    private(set) var token: String?

    /// 最近一次请求的诊断信息，界面上可展开查看。
    struct Trace {
        let method: String
        let path: String
        let status: Int
        let body: String
        let at: Date
    }
    private(set) var traces: [Trace] = []
    var lastTrace: Trace? { traces.last }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            // 与 Android 端 HttpURLConnection 的默认 UA 对齐。
            // 服务端如果按 UA 判断「是不是自家客户端」，这能保证走同一条放行路径。
            "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 14; Pixel 7 Build/UQ1A.240205.004)"
        ]
        session = URLSession(configuration: config)
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    // MARK: - 通用请求

    @discardableResult
    func request(_ method: String,
                 _ path: String,
                 body: JSONDictionary? = nil,
                 authorized: Bool = true,
                 tolerateFailureStatus: Bool = false,
                 timeout: TimeInterval = 20) async throws -> JSONDictionary {

        let url: URL
        if path.hasPrefix("http"), let absolute = URL(string: path) {
            url = absolute
        } else {
            url = URL(string: path, relativeTo: baseURL)!.absoluteURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            let data = try JSONSerialization.data(withJSONObject: body, options: [])
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let raw = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes non-utf8>"
        traces.append(Trace(method: method, path: path, status: status,
                            body: String(raw.prefix(600)), at: Date()))
        if traces.count > 10 { traces.removeFirst(traces.count - 10) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONDictionary ?? [:]

        if status >= 200, status < 300 {
            if json.isEmpty, !raw.isEmpty {
                throw APIError(message: "响应不是 JSON（HTTP \(status)）：\(raw.prefix(120))", statusCode: status)
            }
            return json
        }
        if tolerateFailureStatus {
            return json
        }
        let message = json["error"] as? String
            ?? "请求失败（HTTP \(status)）：\(raw.prefix(120))"
        throw APIError(message: message, statusCode: status)
    }

    func get(_ path: String, authorized: Bool = true, timeout: TimeInterval = 20) async throws -> JSONDictionary {
        try await request("GET", path, authorized: authorized, timeout: timeout)
    }

    func post(_ path: String, body: JSONDictionary?, authorized: Bool = true, timeout: TimeInterval = 20) async throws -> JSONDictionary {
        try await request("POST", path, body: body, authorized: authorized, timeout: timeout)
    }

    // MARK: - 账号

    func requestSMS(phone: String) async throws {
        try await request("POST", "/api/auth/request-code",
                          body: ["phoneNumber": phone], authorized: false)
    }

    func verifySMS(phone: String, code: String, machineId: String) async throws -> SessionPayload {
        let json = try await request("POST", "/api/auth/verify-code", body: [
            "phoneNumber": phone,
            "code": code,
            "machineId": machineId,
            "deviceType": deviceType
        ], authorized: false)

        let sessionJson = json["session"] as? JSONDictionary ?? [:]
        let newToken = sessionJson["sessionToken"] as? String ?? ""
        guard !newToken.isEmpty else {
            throw APIError(message: json["error"] as? String ?? "登录失败，请重试。", statusCode: 0)
        }
        setToken(newToken)

        return SessionPayload(
            token: newToken,
            user: UserProfile(json: json["user"] as? JSONDictionary),
            entitlement: Entitlement(json: json["entitlement"] as? JSONDictionary),
            isNewUser: json["isNewUser"] as? Bool ?? false
        )
    }

    func logout() async {
        _ = try? await request("POST", "/api/auth/logout", body: [:], tolerateFailureStatus: true)
        setToken(nil)
    }

    // MARK: - 权益

    func entitlement(machineId: String) async throws -> (user: UserProfile?, entitlement: Entitlement?) {
        let path = "/api/account/entitlement?machineId=\(Self.encode(machineId))"
        // Android 端这里是 tolerateFailureStatus = true，401 也当成正常 JSON 处理
        let json = try await request("GET", path, tolerateFailureStatus: true)
        return (UserProfile(json: json["user"] as? JSONDictionary),
                Entitlement(json: json["entitlement"] as? JSONDictionary))
    }

    func redeem(serial: String, machineId: String) async throws -> Entitlement? {
        let json = try await request("POST", "/api/account/redeem", body: [
            "serialNumber": serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            "machineId": machineId
        ])
        return Entitlement(json: json["entitlement"] as? JSONDictionary)
    }

    // MARK: - 计费

    func plans() async throws -> [Plan] {
        let json = try await request("GET", "/api/billing/plans", authorized: false)
        let raw = json["plans"] as? [JSONDictionary] ?? []
        return raw.compactMap(Plan.init)
    }

    struct Checkout: Equatable {
        let orderId: String
        let launchURL: String
        let handoff: String
    }

    func checkout(plan: String, machineId: String) async throws -> Checkout {
        let json = try await request("POST", "/api/billing/checkout", body: [
            "plan": plan,
            "machineId": machineId,
            "deviceType": deviceType,
            "provider": "wechat_mini_program"
        ])
        let orderId = json["orderId"] as? String ?? ""
        let launchURL = json["miniProgramLaunchUrl"] as? String ?? ""
        let handoff = json["miniProgramHandoff"] as? String ?? ""
        guard !orderId.isEmpty, !launchURL.isEmpty, !handoff.isEmpty else {
            throw APIError(message: json["error"] as? String ?? "微信小程序支付暂未配置，请联系客服。", statusCode: 0)
        }
        return Checkout(orderId: orderId, launchURL: launchURL, handoff: handoff)
    }

    // MARK: - 直播间

    func rooms() async throws -> [Room] {
        // 未登录也能拿到公共列表；带 token 时服务端会补 likedByCurrentUser 等个人字段。
        let json = try await request("GET", "/api/live/rooms", authorized: true)
        let raw = json["rooms"] as? [JSONDictionary] ?? []
        return raw.compactMap(Room.init)
    }

    func addRoom(name: String, roomUrl: String) async throws {
        try await request("POST", "/api/live/rooms", body: ["name": name, "roomUrl": roomUrl])
    }

    func deleteRoom(id: String) async throws {
        try await request("DELETE", "/api/live/rooms/\(Self.encode(id))")
    }

    /// 服务端识别直播间 → 候选流地址。
    func discover(url: String) async throws -> DiscoverResult {
        let path = "/api/live/discover?url=\(Self.encode(url))"
        let json = try await request("GET", path, tolerateFailureStatus: true)
        return DiscoverResult(json: json)
    }

    // MARK: - 社区 / 更新

    func recoveryGroup() async throws -> CommunityGroup? {
        let json = try await request("GET", "/api/community/recovery-group", authorized: false)
        return CommunityGroup(json: json)
    }

    func recoveryGroupMeta() async throws -> String {
        let json = try await request("GET", "/api/community/recovery-group?metadata=1", authorized: false)
        return json["version"] as? String ?? ""
    }

    func newUserWelcome() async throws -> WelcomeMessage? {
        let json = try await request("GET", "/api/community/new-user-welcome", authorized: false, timeout: 5)
        guard json["ok"] as? Bool == true else { return nil }
        return WelcomeMessage(json: json)
    }

    func checkUpdate(versionCode: Int, versionName: String) async throws -> UpdateInfo {
        let path = "/api/android/update?versionCode=\(versionCode)&versionName=\(Self.encode(versionName))"
        let json = try await request("GET", path, authorized: false)
        return UpdateInfo(json: json)
    }

    // MARK: - 工具

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
