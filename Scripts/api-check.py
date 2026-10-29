"""Cross-check that every `engine.foo` / `store.foo` reference in the views
exists on the corresponding Swift type. Rough regex-based, but catches typos
and stale names without a Swift compiler.
"""

from __future__ import annotations
from typing import List, Set, Dict, Tuple
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "LapTimer"


def members(path: pathlib.Path) -> Set[str]:
    text = path.read_text(encoding="utf-8")
    names = set()
    names |= set(re.findall(r"(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:", text))
    names |= set(re.findall(r"func\s+([A-Za-z_][A-Za-z0-9_]*)", text))
    names |= set(re.findall(r"case\s+([A-Za-z_][A-Za-z0-9_]*)", text))
    return names


def main() -> int:
    stopwatch = members(ROOT / "StopwatchEngine.swift") | {"snapshot"}
    countdown = members(ROOT / "CountdownEngine.swift") | {"snapshot"}
    history = members(ROOT / "HistoryStore.swift")
    engines = stopwatch | countdown

    problems = []
    for path in sorted(ROOT.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for name in sorted(set(re.findall(r"\bengine\.([A-Za-z_][A-Za-z0-9_]*)", text))):
            if name not in engines:
                problems.append(f"{path.name}: engine.{name} 在任何引擎里都不存在")
        for name in sorted(set(re.findall(r"\bstore\.([A-Za-z_][A-Za-z0-9_]*)", text))):
            if name not in history:
                problems.append(f"{path.name}: store.{name} 在 HistoryStore 里不存在")
        for name in sorted(set(re.findall(r"\bengine\.snapshot\.([A-Za-z_][A-Za-z0-9_]*)", text))):
            model = (ROOT / "TimerModels.swift").read_text(encoding="utf-8")
            if not re.search(r"var " + name + r":", model):
                problems.append(f"{path.name}: snapshot.{name} 在两个快照结构里都找不到")

    print(f"StopwatchEngine 公开成员 {len(stopwatch)} 个")
    print(f"CountdownEngine 公开成员 {len(countdown)} 个")
    print(f"HistoryStore 公开成员 {len(history)} 个")
    print()
    if problems:
        print("发现问题：")
        for item in sorted(set(problems)):
            print("  -", item)
        return 1
    print("视图侧引用检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
