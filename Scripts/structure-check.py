"""Rough structural sanity checks for the Swift sources.

Not a compiler — catches unbalanced braces/parens/brackets, stray
non-UTF8 bytes, and unmatched string interpolation.
"""

from __future__ import annotations
from typing import List, Set, Dict, Tuple
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "LapTimer"

BRACES = {"{": "}", "(": ")", "[": "]"}


def strip_strings_and_comments(text: str) -> str:
    out = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        # line comment
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        # block comment (nestable in Swift)
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            depth = 1
            out.append("  ")
            i += 2
            while i < n and depth > 0:
                if text[i] == "/" and i + 1 < n and text[i + 1] == "*":
                    depth += 1
                    out.append("  ")
                    i += 2
                elif text[i] == "*" and i + 1 < n and text[i + 1] == "/":
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
            continue
        # triple-quoted string
        if text.startswith('"""', i):
            end = text.find('"""', i + 3)
            end = n if end == -1 else end + 3
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
            continue
        # normal string
        if ch == '"':
            out.append(" ")
            i += 1
            depth = 0
            while i < n:
                c = text[i]
                if c == "\\":
                    # Swift 字符串插值写作 \( ... )，\ 后面跟 ( 时不是转义
                    if i + 1 < n and text[i + 1] == "(" and depth == 0:
                        depth += 1
                        out.append("(")
                        i += 2
                        continue
                    out.append("  ")
                    i += 2
                    continue
                if c == "(":
                    depth += 1
                    out.append("(")
                elif c == ")":
                    depth = max(0, depth - 1)
                    out.append(")")
                elif c == '"' and depth == 0:
                    out.append(" ")
                    i += 1
                    break
                else:
                    out.append("\n" if c == "\n" else " ")
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check(name: str, text: str) -> List[str]:
    problems = []
    cleaned = strip_strings_and_comments(text)
    stack = []
    line = 1
    for ch in cleaned:
        if ch == "\n":
            line += 1
        if ch in BRACES:
            stack.append((ch, line))
        elif ch in BRACES.values():
            if not stack:
                problems.append(f"{name}:{line} 多余的 {ch}")
                continue
            opener, opened_at = stack.pop()
            if BRACES[opener] != ch:
                problems.append(f"{name}:{line} {opener}（第 {opened_at} 行）与 {ch} 不匹配")
    for opener, opened_at in stack:
        problems.append(f"{name}:{opened_at} 未闭合的 {opener}")
    return problems


def main() -> int:
    problems = []
    for path in sorted(ROOT.rglob("*.swift")):
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            problems.append(f"{path.name}: 非 UTF-8 字节（{exc}）")
            continue
        if "\ufffd" in text:
            problems.append(f"{path.name}: 含替换字符 U+FFFD（编码损坏）")
        problems.extend(check(path.name, text))
        print(f"  checked {path.name} ({len(text.splitlines())} 行)")

    print()
    if problems:
        print("发现结构问题：")
        for item in problems:
            print("  -", item)
        return 1
    print("Swift 源码结构检查通过（平衡括号、UTF-8 完整）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
