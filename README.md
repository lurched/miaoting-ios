# 秒听 1.1.3 逆向 + iOS 复现

| 目录 | 内容 |
|---|---|
| [`report/REPORT.md`](report/REPORT.md) | 主报告：原理、链路、算法、iOS 复现路径、验证状态 |
| [`analysis/`](analysis/) | Android 反编译产物（48 个类的 Java 伪码 + manifest） |
| [`ios/`](ios/) | SwiftUI 客户端工程（19 个 Swift 文件，可直接 xcodebuild） |
| [`docs/INSTALL-IOS.md`](docs/INSTALL-IOS.md) | **没有 Mac 怎么装到 iPhone**（CI 编译 + 自签） |
| [`.github/workflows/`](.github/workflows/) | GitHub Actions 构建（未签名 / 已签名两套） |
| [`tools/flv_selftest.py`](tools/flv_selftest.py) | FLV demux / ASC 解析 / 候选打分的离线自测（已通过） |
| [`tools/gen_xcodeproj.py`](tools/gen_xcodeproj.py) | 生成 Xcode 工程文件 |
| [`tools/analyze_patch.py`](tools/analyze_patch.py) | 定位 patched APK 的补丁点 |
| [`tools/verify_ios_patch.py`](tools/verify_ios_patch.py) | iOS 补丁点静态校验 |
| [`tools/check_ci_ready.py`](tools/check_ci_ready.py) | 检查工程能否直接丢进 CI |

快速验证：

```bash
python3 tools/flv_selftest.py
```

构建 iOS：

- 有 Mac：`cd ios && ./build.sh unsigned`
- **没有 Mac**：走 GitHub Actions，见 [docs/INSTALL-IOS.md](docs/INSTALL-IOS.md)
