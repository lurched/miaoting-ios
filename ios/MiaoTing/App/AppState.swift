import Foundation
import UIKit

@MainActor
final class AppState: ObservableObject {

    enum SortMode: String, CaseIterable, Identifiable {
        case overall = "综合排序"
        case likes = "收藏最多"
        case newest = "最新添加"
        var id: String { rawValue }
    }

    // 账号
    @Published private(set) var user: UserProfile?
    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var isLoggedIn = false
    @Published var showLogin = false
    @Published var showPaywall = false

    enum Tab: Int, CaseIterable, Identifiable {
        case listen, rooms, account
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .listen: return "收听"
            case .rooms: return "直播间"
            case .account: return "账号"
            }
        }
        var icon: String {
            switch self {
            case .listen: return "waveform"
            case .rooms: return "list.bullet.rectangle"
            case .account: return "person.crop.circle"
            }
        }
    }

    @Published var tab: Tab = .listen
    @Published var searchText: String = ""

    // 数据
    @Published private(set) var rooms: [Room] = []
    @Published private(set) var plans: [Plan] = []
    @Published var sortMode: SortMode = .overall

    // 输入与播放
    @Published var input: String = ""
    @Published private(set) var roomTitle: String = ""
    @Published private(set) var platformName: String = ""
    @Published private(set) var statusText: String = "未播放"
    @Published private(set) var isPlaying = false
    @Published var speed: Float = 1.3
    @Published var preservesPitch = true

    // 反馈
    @Published var toast: String?
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var banner: String?

    var machineId: String { DeviceIdentity.machineId }

    private let api = APIClient.shared
    private let playback = PlaybackController.shared
    private var pollTask: Task<Void, Never>?

    init() {
        playback.onStatus = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.statusText = Self.describe(status, speed: self.speed)
                self.isPlaying = (status == .playing || status == .preparing)
                if case .failed(let message) = status { self.errorMessage = message }
            }
        }
        playback.onTitle = { [weak self] title in
            Task { @MainActor in self?.roomTitle = title }
        }
        restore()
    }

    // MARK: - 启动

    func restore() {
        if let token = Keychain.read("token"), !token.isEmpty {
            api.setToken(token)
            isLoggedIn = true
        }

        Task {
            await refreshPlans()
            await refreshRooms()
            if isLoggedIn { await refreshEntitlement() }
            await checkUpdate()
            await loadWelcome()
        }
    }

    // MARK: - 账号

    func sendCode(_ phone: String) async throws {
        try await api.requestSMS(phone: phone)
    }

    func verify(phone: String, code: String) async throws {
        let payload = try await api.verifySMS(phone: phone, code: code, machineId: machineId)
        Keychain.save(payload.token, for: "token")
        Keychain.save(phone, for: "phone")
        user = payload.user
        entitlement = payload.entitlement
        isLoggedIn = true
        showLogin = false
        await refreshRooms()
        await refreshPlans()
        await refreshEntitlement()
    }

    func logout() async {
        await api.logout()
        Keychain.delete("token")
        user = nil
        entitlement = nil
        isLoggedIn = false
        rooms = []
        stop()
    }

    func refreshEntitlement() async {
        do {
            let result = try await api.entitlement(machineId: machineId)
            if let u = result.user { user = u }
            entitlement = result.entitlement
        } catch {
            // 401 等错误由接口层吞掉，这里静默
        }
    }

    // MARK: - 权益

    /// 服务端权益的真实状态，只用于界面展示（与 Android 端 UI 一致）。
    var hasActiveEntitlement: Bool {
        entitlement?.isActive ?? false
    }

    /// 客户端权益门禁。对应 Android `MainActivity.B()`。
    ///
    /// patched APK 把这个方法改成了 `return true`，这里用 PatchFlags 对齐；
    /// 关掉 PatchFlags 就退回原版行为。
    var isEntitlementGateOpen: Bool {
        PatchFlags.bypassEntitlementGate || hasActiveEntitlement
    }

    func redeem(_ serial: String) async throws {
        _ = try await api.redeem(serial: serial, machineId: machineId)
        await refreshEntitlement()
        toast = "绑定成功"
    }

    func purchase(_ plan: Plan) async {
        guard isLoggedIn else { showLogin = true; return }
        isBusy = true
        defer { isBusy = false }
        do {
            let checkout = try await api.checkout(plan: plan.id, machineId: machineId)
            Keychain.save(checkout.orderId, for: "pendingOrderId")
            if let url = URL(string: checkout.launchURL), UIApplication.shared.canOpenURL(url) {
                _ = await UIApplication.shared.open(url)
                toast = "已打开兔兔爪子，请完成支付后返回秒听。"
                pollAfterPayment(orderId: checkout.orderId)
            } else {
                errorMessage = "未检测到可打开小程序的微信，请先安装并登录微信。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 支付回来后轮询权益（对应 Android 端 `LB`：10 次 × 3s）。
    private func pollAfterPayment(orderId: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<10 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
                if Task.isCancelled { return }
                await self.refreshEntitlement()
                if self.entitlement?.orderId == orderId, self.hasActiveEntitlement {
                    self.toast = "支付成功，权益已生效。"
                    Keychain.delete("pendingOrderId")
                    return
                }
            }
            self.banner = "支付结果处理中，请稍后刷新权益。"
        }
    }

    // MARK: - 直播间列表

    var sortedRooms: [Room] {
        let list = rooms
        switch sortMode {
        case .overall:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .likes:
            return list.sorted { a, b in
                if a.ownedByCurrentUser != b.ownedByCurrentUser { return a.ownedByCurrentUser }
                if a.likeCount != b.likeCount { return a.likeCount > b.likeCount }
                return a.name < b.name
            }
        case .newest:
            return list.sorted { a, b in
                if a.ownedByCurrentUser != b.ownedByCurrentUser { return a.ownedByCurrentUser }
                return a.createdAt > b.createdAt
            }
        }
    }

    func refreshRooms() async {
        do {
            rooms = try await api.rooms()
        } catch {
            // 列表接口未登录也可读，失败就保持现状
        }
    }

    func addRoom(name: String, url: String) async throws {
        guard isLoggedIn else { showLogin = true; return }
        try await api.addRoom(name: name, roomUrl: url)
        await refreshRooms()
    }

    func deleteRoom(_ room: Room) async {
        do {
            try await api.deleteRoom(id: room.id)
            rooms.removeAll { $0.id == room.id }
            toast = "已从我的直播间中删除。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 识别 + 播放

    func resolveAndPlay(_ text: String? = nil) {
        let raw = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            errorMessage = "请先粘贴直播链接或播放直链。"
            return
        }
        guard isLoggedIn else {
            showLogin = true
            return
        }
        guard isEntitlementGateOpen else {
            showPaywall = true
            return
        }

        isBusy = true
        errorMessage = nil
        banner = nil

        Task {
            defer { isBusy = false }
            var shareTitle = LinkExtractor.titleFromShareText(raw) ?? ""
            var target = LinkExtractor.pickTarget(from: raw)

            if LinkExtractor.isXHSShortLink(target) {
                target = await LinkExtractor.resolveXHSShortLink(target)
            }

            // 直链：直接播
            if LinkExtractor.isFLV(target) || LinkExtractor.isHLS(target) {
                play(url: target, title: shareTitle.isEmpty ? "直播音频" : shareTitle, platform: "")
                return
            }

            guard LinkExtractor.isPlatformLink(target) else {
                errorMessage = "未识别直播间链接或播放直链。"
                return
            }

            statusText = "正在识别直播间"
            roomTitle = shareTitle

            // webcast.amemv.com/.../reflow/xxx 是抖音短链的落地页，
            // 页面上直接写着 flv 地址，不需要再问服务端（那边一律 403）。
            if LinkExtractor.host(of: target).contains("amemv.com") {
                let local = await LocalResolver.hunt(pageURL: target)
                if !local.title.isEmpty { roomTitle = local.title }
                if let best = CandidateRanker.best(from: local.candidates) {
                    errorMessage = nil
                    play(url: best.url, title: roomTitle, platform: "抖音")
                    return
                }
                errorMessage = "直播间暂未开播。"
                return
            }

            input = target

            // 1) 服务端识别。失败原因先记下来，不要立刻弹给用户——
            //    Android 端在 discover 异常时也会继续走本地解析，只有两条路都失败才提示。
            var serverMessage: String?

            do {
                let result = try await api.discover(url: target)
                if let message = result.failureMessage { serverMessage = message }
                if !result.roomTitle.isEmpty { shareTitle = result.roomTitle }
                platformName = platformLabel(result.platform)
                roomTitle = shareTitle.isEmpty ? "直播间" : shareTitle

                if let best = CandidateRanker.best(from: result.candidates) {
                    errorMessage = nil
                    play(url: best.url, title: roomTitle, platform: result.platform)
                    return
                }
                banner = "服务器识别失败，尝试本地解析"
            } catch {
                serverMessage = error.localizedDescription
                banner = "服务器识别失败，尝试本地解析"
            }

            // 2) 本地兜底：直接抓直播间页面抠流地址
            let local = await LocalResolver.hunt(pageURL: target)
            if !local.title.isEmpty { roomTitle = local.title }
            if let best = CandidateRanker.best(from: local.candidates) {
                errorMessage = nil
                play(url: best.url, title: roomTitle, platform: platformName)
                return
            }

            // 3) 两条路都失败：此时才把服务端的原话给用户
            if let serverMessage {
                errorMessage = serverMessage
            } else {
                errorMessage = "直播间暂未开播。"
            }
        }
    }

    private func platformLabel(_ platform: String) -> String {
        switch platform {
        case "douyin": return "抖音"
        case "kuaishou": return "快手"
        case "xiaohongshu": return "小红书"
        case "taobao": return "淘宝"
        default: return ""
        }
    }

    private func play(url: String, title: String, platform: String) {
        guard let streamURL = URL(string: url) else {
            errorMessage = "播放地址无效。"
            return
        }
        roomTitle = title
        platformName = platform
        playback.speed = speed
        playback.preservesPitch = preservesPitch
        playback.play(url: streamURL, title: title)
        statusText = "正在连接直播音频 \(String(format: "%.1f", speed))x"
        isPlaying = true
        BackgroundAudio.shared.activate()
    }

    func stop() {
        playback.stop()
        isPlaying = false
        statusText = "未播放"
    }

    func togglePlay() {
        if isPlaying { stop() } else { resolveAndPlay() }
    }

    func setSpeed(_ value: Float) {
        speed = value
        playback.speed = value
        if isPlaying { statusText = "正在播放 \(String(format: "%.1f", value))x" }
    }

    func setPreservesPitch(_ value: Bool) {
        preservesPitch = value
        playback.preservesPitch = value
    }

    var filteredRooms: [Room] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return sortedRooms }
        return sortedRooms.filter {
            $0.name.lowercased().contains(keyword) || $0.platformName.contains(keyword)
        }
    }

    var traces: [APIClient.Trace] { api.traces }
    var lastTrace: APIClient.Trace? { api.lastTrace }

    var machineIdOverride: String {
        get { DeviceIdentity.override ?? "" }
        set {
            DeviceIdentity.override = newValue.isEmpty ? nil : newValue
            objectWillChange.send()
        }
    }

    /// 当前实际播放/尝试连接的地址，贴在诊断面板里。
    var activeStreamURL: String { playback.activeStreamURL }
    var diagnosticsLine: String { playback.diagnosticsLine }

    // MARK: - 其它

    func refreshPlans() async {
        if let list = try? await api.plans(), !list.isEmpty { plans = list }
    }

    func checkUpdate() async {
        guard let info = try? await api.checkUpdate(versionCode: AppVersion.code,
                                                    versionName: AppVersion.name) else { return }
        if info.hasUpdate {
            banner = "发现新版本 \(info.versionName)"
        }
    }

    func loadWelcome() async {
        guard let welcome = try? await api.newUserWelcome() else { return }
        banner = welcome.title + "：" + welcome.message
    }

    func openLegal(_ kind: LegalDocument) {
        guard let url = URL(string: kind.url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    enum LegalDocument {
        case terms, privacy
        var url: String {
            switch self {
            case .terms: return "https://syncrozero.com/legal/terms"
            case .privacy: return "https://syncrozero.com/legal/privacy"
            }
        }
    }


    private static func describe(_ status: PlaybackController.Status, speed: Float) -> String {
        switch status {
        case .idle: return "未播放"
        case .preparing: return "正在连接直播音频 \(String(format: "%.1f", speed))x"
        case .playing: return "正在播放 \(String(format: "%.1f", speed))x"
        case .failed(let message): return message
        }
    }
}

/// 版本号常量放在类型外，避免被 @MainActor 隔离，界面与网络层都能直接读。
enum AppVersion {
    static let name = "1.1.3"
    static let code = 113
}
