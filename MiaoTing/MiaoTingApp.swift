//  MiaoTingApp.swift
//  秒听 iOS 版
//
//  直播音频收听工具 - 支持小红书、抖音、快手、淘宝直播
//

import SwiftUI

@main
struct MiaoTingApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
