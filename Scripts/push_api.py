#!/usr/bin/env python3
"""用 GitHub Git Data API 提交文件，绕开 git 传输层（本机 git push 不可靠）。

用法：
    python push_api.py <owner/repo> <branch> <commit-message> <file1> [file2 ...]

文件路径相对当前工作目录，远端路径与本地相对路径一致。
"""
from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"


def token() -> str:
    t = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if t:
        return t.strip()
    p = os.path.join(os.environ.get("TEMP", "/tmp"), "ghtok.txt")
    with open(p, "r", encoding="ascii") as f:
        return f.read().strip()


def call(method: str, path: str, body=None, retries: int = 6):
    url = path if path.startswith("http") else API + path
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    last = None
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + token())
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                raw = r.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:400]
            last = f"HTTP {e.code}: {detail}"
            if e.code in (401, 403, 404, 422):
                raise RuntimeError(f"{method} {path} -> {last}") from None
        except Exception as e:  # noqa: BLE001
            last = f"{type(e).__name__}: {e}"
        wait = min(2 ** attempt, 20)
        print(f"  retry {attempt + 1}/{retries} after {wait}s ({last})", flush=True)
        time.sleep(wait)
    raise RuntimeError(f"{method} {path} failed: {last}")


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    repo, branch, message = sys.argv[1], sys.argv[2], sys.argv[3]
    files = sys.argv[4:]

    ref = call("GET", f"/repos/{repo}/git/ref/heads/{branch}")
    head = ref["object"]["sha"]
    commit = call("GET", f"/repos/{repo}/git/commits/{head}")
    base_tree = commit["tree"]["sha"]
    print(f"head={head[:8]} base_tree={base_tree[:8]}")

    entries = []
    for path in files:
        if not os.path.isfile(path):
            raise SystemExit(f"missing file: {path}")
        with open(path, "rb") as f:
            content = f.read()
        blob = call("POST", f"/repos/{repo}/git/blobs", {
            "content": base64.b64encode(content).decode("ascii"),
            "encoding": "base64",
        })
        remote_path = path.replace(os.sep, "/")
        entries.append({
            "path": remote_path,
            "mode": "100755" if remote_path.endswith(".sh") else "100644",
            "type": "blob",
            "sha": blob["sha"],
        })
        print(f"  blob {remote_path} {len(content)}B -> {blob['sha'][:8]}")

    tree = call("POST", f"/repos/{repo}/git/trees", {
        "base_tree": base_tree,
        "tree": entries,
    })
    new_commit = call("POST", f"/repos/{repo}/git/commits", {
        "message": message,
        "tree": tree["sha"],
        "parents": [head],
    })
    call("PATCH", f"/repos/{repo}/git/refs/heads/{branch}", {"sha": new_commit["sha"]})
    print(f"pushed commit {new_commit['sha']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
