# 秒听 iOS 版 (MiaoTing iOS)

## 概述

从 Android APK (`miaoting-1.1.3-patched.apk`, 包名 `com.syncrozero.pro`) 反编译重写为 iOS 原生应用。

## 功能

- 支持小红书 / 抖音 / 快手 / 淘宝直播音频收听
- 通过 syncrozero.com API 解析直播流地址
- HTTP-FLV 流解析 + AAC 音频解码
- 实时变速播放 (1.0x / 1.5x / 2.0x / 3.0x)
- 后台音频播放
- 历史记录管理
- API Token 配置

## 项目结构

```
MiaoTing/
├── MiaoTingApp.swift          # App 入口
├── Info.plist                 # 配置文件
├── Models/
│   └── AppState.swift         # 全局状态管理
├── Services/
│   ├── PlatformDetector.swift  # 平台检测 / URL 处理
│   ├── APIClient.swift        # syncrozero API 客户端
│   ├── FLVParser.swift        # FLV 流解析器
│   ├── AudioEngine.swift      # AVAudioEngine 播放引擎
│   ├── StreamClient.swift     # HTTP-FLV 流客户端
│   └── PlayerManager.swift    # 播放管理器
└── Views/
    └── MainView.swift          # 主界面 + 设置 + 历史
```

## 从 Android 到 iOS 的映射

| Android 组件 | iOS 对应 |
|---|---|
| `com.syncrozero.pro.MainActivity` | `MainView` (SwiftUI) |
| `com.syncrozero.pro.PlayerService` | `PlayerManager` + `AudioEngine` |
| `P` 类 (MediaCodec + AudioTrack) | `AVAudioEngine` + `AVAudioConverter` |
| `c` 类 (FLV 解析) | `FLVParser` |
| `g` 类 (网络/工具) | `APIClient` + `PlatformDetector` |
| `HttpURLConnection` 流读取 | `URLSession` (dataTask + delegate) |
| `SharedPreferences` | `UserDefaults` |
| `AndroidManifest` 权限 | `Info.plist` (ATS + Background Modes) |

## 构建

### 方法 1: Xcode

1. 打开 Xcode → File → New → Project → iOS App
2. 产品名: `MiaoTing`
3. Bundle Identifier: `com.syncrozero.pro`
4. 最低版本: iOS 15.0
5. 将 `MiaoTing/` 目录下所有 `.swift` 文件拖入项目
6. 确保 `Info.plist` 已包含在项目中
7. Build (⌘B) → Run (⌘R)

### 方法 2: 命令行

```bash
# 需要 Xcode 命令行工具
xcodebuild -project MiaoTing.xcodeproj \
    -scheme MiaoTing \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    build
```

## 权限配置

### Info.plist 关键项

- **NSAppTransportSecurity**: 允许 HTTP 连接（直播流需要）
- **UIBackgroundModes** → `audio`: 后台音频播放
- **UIStatusBarStyle**: LightContent

### 不需要的权限

与 Android 版对比，iOS 不需要以下权限声明：
- `INTERNET` — iOS 默认允许网络访问
- `POST_NOTIFICATIONS` — iOS 默认允许
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` — iOS 用 Background Modes `audio` 替代

## 技术说明

### FLV 解析
Android 版使用自定义 `c` 类解析 FLV 标签。iOS 版 `FLVParser` 实现了完整的 FLV v1 解析：
- FLV 头解析（9 字节签名 + 类型标志）
- PreviousTagSize 跳过
- FLV Tag 解析（11 字节头 + 数据）
- 音频标签处理（AAC SoundFormat=10）
- AudioSpecificConfig 解析（采样率 + 声道数）
- AAC 原始帧提取
- 时间戳排序缓冲（对应 Android P.b 的实时保持逻辑）

### 音频解码
Android 版使用 `MediaCodec` 解码 AAC-LC，`AudioTrack` 播放 PCM。
iOS 版使用 `AVAudioConverter` 解码 AAC → PCM，`AVAudioPlayerNode` 播放。

### 变速播放
Android 版通过重采样实现变速（P.a 方法中的插值逻辑）。
iOS 版可通过 `AVAudioUnitTimePitch` 实现变速不变调。

### API 请求
Android 版使用 `HttpURLConnection`。iOS 版使用 `URLSession` + `async/await`。

## 版本信息

- 版本: 1.1.3 (113)
- 后端: syncrozero.com
- 最低 iOS: 15.0
- 目标 iOS: 17.0+
