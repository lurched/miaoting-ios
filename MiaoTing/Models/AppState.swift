//  AppState.swift
//  全局状态管理
//

import SwiftUI
import Combine

enum PlayerStatus: Equatable {
    case idle
    case connecting
    case playing
    case paused
    case error(String)

    static func == (lhs: PlayerStatus, rhs: PlayerStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.connecting, .connecting), (.playing, .playing), (.paused, .paused):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// 直播平台
enum LivePlatform: String, CaseIterable, Identifiable {
    case xiaohongshu = "小红书"
    case douyin = "抖音"
    case kuaishou = "快手"
    case taobao = "淘宝"
    case unknown = "未知"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xiaohongshu: return "红薯"
        case .douyin: return "抖抖"
        case .kuaishou: return "快快"
        case .taobao: return "淘淘"
        case .unknown: return "未知"
        }
    }

    var color: Color {
        switch self {
        case .xiaohongshu: return Color(red: 255/255, green: 46/255, blue: 77/255)
        case .douyin: return Color(red: 37/255, green: 44/255, blue: 66/255)
        case .kuaishou: return Color(red: 255/255, green: 100/255, blue: 30/255)
        case .taobao: return Color(red: 255/255, green: 80/255, blue: 0/255)
        case .unknown: return Color.gray
        }
    }
}

// 流地址类型
struct StreamURL: Identifiable {
    let id = UUID()
    let url: String
    let protocolName: String   // http-flv, hls, lls-sdp
    let protocolLabel: String  // 显示名称
    let playable: Bool
    let latencyTier: String
}

// 房间信息
struct RoomInfo {
    var platform: LivePlatform = .unknown
    var roomTitle: String = ""
    var streamURLs: [StreamURL] = []
    var finalURL: String = ""
    var rawJSON: [String: Any]?
}

class AppState: ObservableObject {
    // 播放状态
    @Published var playerStatus: PlayerStatus = .idle
    @Published var statusText: String = "等待输入"
    @Published var playbackSpeed: Float = 1.0
    @Published var currentRoom: RoomInfo?

    // 输入
    @Published var inputURL: String = ""

    // 用户配置
    @Published var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: "apiToken") }
    }

    // 历史记录
    @Published var history: [HistoryEntry] {
        didSet { saveHistory() }
    }

    init() {
        self.apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        self.history = []
        self.history = Self.loadHistory()
    }

    func reset() {
        playerStatus = .idle
        statusText = "等待输入"
        currentRoom = nil
    }

    // MARK: - 历史记录
    private func saveHistory() {
        let dicts = history.map { ["url": $0.url, "title": $0.title, "date": $0.date.timeIntervalSince1970] }
        UserDefaults.standard.set(dicts, forKey: "history")
    }

    private static func loadHistory() -> [HistoryEntry] {
        guard let dicts = UserDefaults.standard.array(forKey: "history") as? [[String: Any]] else {
            return []
        }
        return dicts.compactMap { dict in
            guard let url = dict["url"] as? String,
                  let title = dict["title"] as? String,
                  let date = dict["date"] as? TimeInterval else { return nil }
            return HistoryEntry(url: url, title: title, date: Date(timeIntervalSince1970: date))
        }
    }

    func addToHistory(url: String, title: String) {
        let entry = HistoryEntry(url: url, title: title, date: Date())
        history.removeAll { $0.url == url }
        history.insert(entry, at: 0)
        if history.count > 50 { history.removeLast() }
    }

    func clearHistory() {
        history.removeAll()
    }
}

struct HistoryEntry: Identifiable {
    let id = UUID()
    let url: String
    let title: String
    let date: Date
}
