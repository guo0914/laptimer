#!/usr/bin/env bash
# 一键把工程推到 GitHub 并触发云端构建。
#
# 前提：先 gh auth login 登录一次。
# 用法（在 timer-app/ios/LapTimer 目录里）：
#   bash Scripts/publish.sh <仓库名>
# 例：
#   bash Scripts/publish.sh laptimer

set -euo pipefail

REPO_NAME="${1:-laptimer}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> 确认 gh 已登录"
if ! gh auth status >/dev/null 2>&1; then
  echo "!! 还没登录 GitHub。请先运行： gh auth login"
  exit 1
fi

OWNER=$(gh api user --jq .login)
echo "    账号：$OWNER"

echo "==> 初始化 git 仓库"
if [ ! -d .git ]; then
  git init -q
  git add -A
  git commit -qm "LapTimer: SwiftUI 分段计时 iOS 工程" || true
else
  git add -A
  git commit -qm "更新工程" || true
fi

echo "==> 创建公开仓库 $OWNER/$REPO_NAME"
if gh repo view "$OWNER/$REPO_NAME" >/dev/null 2>&1; then
  echo "    仓库已存在，直接推"
else
  gh repo create "$REPO_NAME" --public --source=. --remote=origin --push
fi

echo "==> 推送到 GitHub"
git branch -M main
git push -u origin main --force

echo "==> 触发云端构建"
gh workflow run "iOS Unsigned IPA" --repo "$OWNER/$REPO_NAME" 2>/dev/null || \
  gh workflow run ios-unsigned-ipa.yml --repo "$OWNER/$REPO_NAME"

sleep 5
echo
echo "构建已触发。查看进度："
gh run list --repo "$OWNER/$REPO_NAME" --workflow "iOS Unsigned IPA" --limit 3

echo
echo "跑完后下载 ipa："
echo "  gh run download --repo $OWNER/$REPO_NAME"
echo "或直接在网页 Actions 页面下载 Artifacts："
echo "  https://github.com/$OWNER/$REPO_NAME/actions"
