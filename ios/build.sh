#!/usr/bin/env bash
# 在 macOS + Xcode 上构建秒听 iOS 客户端。
#
#   ./build.sh unsigned          -> build/MiaoTing-unsigned.ipa（未签名，交给 Sideloadly / TrollStore 自签）
#   ./build.sh signed <TEAM_ID>  -> build/export/MiaoTing.ipa（用你的开发者证书签名）
#
# 需要：Xcode 15+（iOS 16 SDK 以上）、命令行工具已 xcode-select 到 Xcode。
set -euo pipefail

cd "$(dirname "$0")"
MODE="${1:-unsigned}"
TEAM="${2:-}"
SCHEME="MiaoTing"
PROJECT="MiaoTing.xcodeproj"
DERIVED="build"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：需要在 macOS 上运行（当前 $(uname -s)）。" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：未找到 xcodebuild，请先安装 Xcode 并执行 xcode-select --install。" >&2
  exit 1
fi

rm -rf "$DERIVED"
mkdir -p "$DERIVED"

if [[ "$MODE" == "signed" ]]; then
  if [[ -z "$TEAM" ]]; then
    echo "用法：./build.sh signed <TEAM_ID>" >&2
    exit 1
  fi

  echo "==> Archive（Team: $TEAM）"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -archivePath "$DERIVED/MiaoTing.xcarchive" \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates archive

  cat > "$DERIVED/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>teamID</key>
  <string>$TEAM</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
PLIST

  echo "==> Export IPA"
  xcodebuild -exportArchive \
    -archivePath "$DERIVED/MiaoTing.xcarchive" \
    -exportOptionsPlist "$DERIVED/ExportOptions.plist" \
    -exportPath "$DERIVED/export" \
    -allowProvisioningUpdates
  echo "完成：$DERIVED/export/MiaoTing.ipa"
else
  echo "==> 构建未签名 .app"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build

  APP="$DERIVED/Build/Products/Release-iphoneos/MiaoTing.app"
  if [[ ! -d "$APP" ]]; then
    echo "错误：未找到构建产物 $APP" >&2
    exit 1
  fi

  rm -rf "$DERIVED/ipa"
  mkdir -p "$DERIVED/ipa/Payload"
  cp -R "$APP" "$DERIVED/ipa/Payload/"
  ( cd "$DERIVED/ipa" && zip -qry ../MiaoTing-unsigned.ipa Payload )
  echo "完成：$DERIVED/MiaoTing-unsigned.ipa"
  echo "提示：该包未签名，需用 Sideloadly / AltStore / TrollStore 自签安装。"
fi
