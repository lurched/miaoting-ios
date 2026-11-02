# 秒听 iOS 客户端（复现工程）

这是按 Android 端 1.1.3 的接口契约与播放链路重写的 SwiftUI 客户端，**不是**从 TestFlight 包提取的产物。

## 目录

```
ios/
├── MiaoTing.xcodeproj          # 已生成，可直接 open
├── project.yml                 # XcodeGen 备用描述
├── build.sh                    # 构建脚本（unsigned / signed）
└── MiaoTing/
    ├── Info.plist
    ├── Assets.xcassets
    ├── App/                    # 入口、全局状态
    ├── API/                    # 接口、模型、链接提取、候选打分、本地兜底
    ├── Playback/               # FLV demux、AAC 解码、播放引擎、后台音频
    ├── Support/                # Keychain、设备标识
    └── Views/                  # 首页、登录、付费墙、主题
```

## 构建

需要 macOS + Xcode 15 以上（iOS 16 SDK）。

```bash
cd ios

# 1) 未签名 ipa（用 Sideloadly / AltStore / TrollStore 自签安装）
./build.sh unsigned
# 产物：build/MiaoTing-unsigned.ipa

# 2) 用你自己的开发者证书签名
./build.sh signed <YOUR_TEAM_ID>
# 产物：build/export/MiaoTing.ipa
```

Xcode 里直接跑：打开 `MiaoTing.xcodeproj`，在 Signing & Capabilities 选自己的 Team，真机运行。

## 先改这三个地方

| 位置 | 说明 |
|---|---|
| `API/APIClient.swift` → `deviceType` | 默认 `ios-client`。服务端若只认 `android-client`，改回即可 |
| `API/APIClient.swift` → `baseURL` | 默认 `https://syncrozero.com` |
| `Info.plist` → `CFBundleDisplayName` | 默认「秒听」 |

## 权限与能力

- 后台播放：`UIBackgroundModes = audio` + `AVAudioSession(.playback)`
- 锁屏控制：`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`
- 打开微信小程序支付：`LSApplicationQueriesSchemes` 里已声明 `weixin`

## 补丁对齐

patched APK 的改动只有一处：`MainActivity.B()`（权益门禁）被改成恒返回 true。

iOS 侧用 `Support/PatchFlags.swift` 对齐：

```swift
static let bypassEntitlementGate = true   // 关掉即回到原版行为
```

界面仍按服务端返回的 `state` 显示「未开通」，与 Android 端一致；只有「能不能点播放/识别」这一层被放开。

注意：这只解除**客户端**门禁。`/api/live/discover` 仍需要登录 token，服务端是否二次校验权益未验证。

## 离线自测

```bash
python3 ../tools/flv_selftest.py      # FLV demux / ASC / 打分
python3 ../tools/verify_ios_patch.py  # 补丁点静态校验
python3 ../tools/analyze_patch.py ../analysis/orig.apk ../analysis/patched.apk  # 补丁定位
```

校验 FLV demux、AAC ASC 解析、候选流打分三条纯算法（与 Swift 实现同逻辑）。
