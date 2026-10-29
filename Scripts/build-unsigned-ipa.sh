#!/bin/bash
# 在云端 macOS 上编出「未签名 ipa」，不需要任何 Apple 账号。
# 产物拿回 Windows，用 Sideloadly / AltStore 用你自己的 Apple ID 现场签名安装。
#
# 用法（在仓库根，也就是包含 LapTimer.xcodeproj 的那层）：
#   bash Scripts/build-unsigned-ipa.sh
#
# 产物：build/LapTimer-unsigned.ipa

set -euo pipefail

SCHEME="${XCODE_SCHEME:-LapTimer}"
PROJECT="${XCODE_PROJECT:-LapTimer.xcodeproj}"
ARCHIVE="build/LapTimer.xcarchive"
OUT="build/LapTimer-unsigned.ipa"

echo "==> 环境"
xcodebuild -version

echo "==> 自检"
python3 Scripts/structure-check.py
python3 Scripts/api-check.py
python3 Scripts/check-project.py
swiftc LapTimer/TimeFormatting.swift Scripts/logic-check.swift -o /tmp/logiccheck
/tmp/logiccheck

echo "==> 归档（关闭签名）"
rm -rf build
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates 2>/dev/null || \
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER=""

APP="$ARCHIVE/Products/Applications/LapTimer.app"
if [ ! -d "$APP" ]; then
  echo "!! 归档里找不到 $APP"
  exit 1
fi

echo "==> 打包成 ipa"
WORK=$(mktemp -d)
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
cd "$WORK"
zip -qry "$OLDPWD/$OUT" Payload
cd - > /dev/null
rm -rf "$WORK"

echo "==> 完成：$(ls -lh "$OUT" | awk '{print $5, $9}')"
echo
echo "把这个 .ipa 拷到 Windows，用 Sideloadly 签名安装："
echo "  1. Windows 装 Microsoft Store 里的「Apple 设备」App（iTunes 的替代品）"
echo "  2. 装 Sideloadly（sideloadly.io）"
echo "  3. 数据线连 iPhone → Sideloadly 选这个 ipa → 填 Apple ID → Start"
echo "  4. iPhone 设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID"
echo "  5. 每 7 天到期前用 Sideloadly 重装一次"
