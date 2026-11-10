#!/usr/bin/env python3
"""把签名好的 ipa 发布到 OTA 安装页，手机 Safari 打开网页即可安装。

用法：
    python publish_signed_ipa.py <签名后的 ipa 路径>

流程：复制到 docs/LapTimer-signed.ipa → 用 Git Data API 推送 → 等 Pages 构建 → 打印安装页地址。
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
import urllib.request

REPO = "guo0914/laptimer"
BRANCH = "main"
PAGE = "https://guo0914.github.io/laptimer/"
IPA_URL = PAGE + "LapTimer-signed.ipa"
DOCS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")


def pages_status() -> str:
    gh = os.environ.get("GH_EXE", r"C:\Program Files\GitHub CLI\gh.exe")
    out = subprocess.run(
        [gh, "api", f"repos/{REPO}/pages", "--jq", ".status"],
        capture_output=True, text=True,
    )
    return out.stdout.strip()


def wait_built(timeout: float = 300) -> bool:
    start = time.time()
    while time.time() - start < timeout:
        s = pages_status()
        print(f"  pages: {s}", flush=True)
        if s == "built":
            return True
        if s == "errored":
            return False
        time.sleep(10)
    return False


def head_ok(url: str) -> bool:
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status == 200
    except Exception:
        return False


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = sys.argv[1]
    if not os.path.isfile(src):
        raise SystemExit(f"找不到文件: {src}")
    size = os.path.getsize(src)
    with open(src, "rb") as f:
        head = f.read(4)
    if head[:2] != b"PK":
        raise SystemExit("这不是 ipa（不是 zip 结构）")
    print(f"源文件 {src}  {size} 字节")

    dst = os.path.join(DOCS, "LapTimer-signed.ipa")
    shutil.copyfile(src, dst)
    print(f"已复制到 {dst}")

    py = sys.executable
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "push_api.py")
    cmd = [py, script, REPO, BRANCH, "更新签名后的 ipa", "docs/LapTimer-signed.ipa"]
    print("推送中…")
    r = subprocess.run(cmd, cwd=os.path.dirname(DOCS))
    if r.returncode != 0:
        raise SystemExit("推送失败")

    print("等待 Pages 构建…")
    if not wait_built():
        raise SystemExit("Pages 构建失败，去仓库 Actions 看详情")

    for i in range(12):
        if head_ok(IPA_URL):
            print(f"\n✅ 就绪：{PAGE}")
            print(f"   ipa: {IPA_URL}")
            return 0
        print("  等 CDN 生效…", flush=True)
        time.sleep(10)
    print(f"\n⚠️ 文件已推送但 CDN 还没生效，稍后再试：{PAGE}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
