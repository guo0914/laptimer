"""Validate the Xcode project file and bundled resources without Xcode.

Checks performed:
- project.pbxproj is structurally balanced (`{ }` / `( )`)
- every 24-char object id referenced anywhere is also defined
- every PBXBuildFile has a fileRef that is a PBXFileReference
- every Swift file on disk is in the Sources build phase, and vice versa
- Info.plist is well-formed XML with the expected keys
- asset catalog Contents.json files are valid JSON and referenced files exist
"""

import json
import pathlib
import plistlib
import re
import sys

PROJECT = pathlib.Path(__file__).resolve().parent.parent
PBX = PROJECT / "LapTimer.xcodeproj" / "project.pbxproj"
SRC = PROJECT / "LapTimer"

ID = r"AA[0-9A-F]{22}"
RE_ID = re.compile(r"\b" + ID + r"\b")
RE_DEFINED = re.compile(r"\b(" + ID + r")\s*(?:/\*[^*]*\*/)?\s*=\s*\{")
RE_BUILD_FILE = re.compile(
    r"\b(" + ID + r")\b[^\n]*= \{isa = PBXBuildFile; fileRef = \b(" + ID + r")\b"
)
RE_FILE_REF = re.compile(
    r"\b(" + ID + r")\b[^\n]*= \{isa = PBXFileReference; [^\n]*?path = [\"]?([^\";]+)[\"]?;"
)


def check_balance(text: str) -> list[str]:
    problems = []
    pairs = {"{": "}", "(": ")"}
    stack = []
    line = 1
    in_string = False
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
        if in_string:
            if ch == '"' and text[i - 1] != "\\":
                in_string = False
            i += 1
            continue
        if text[i : i + 2] == "/*":
            end = text.find("*/", i + 2)
            end = n if end == -1 else end + 2
            line += text.count("\n", i, end)
            i = end
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch in pairs:
            stack.append((ch, line))
        elif ch in pairs.values():
            if not stack:
                problems.append(f"第 {line} 行多余的 {ch}")
                continue
            opener, opened = stack.pop()
            if pairs[opener] != ch:
                problems.append(f"第 {line} 行 {opener}（第 {opened} 行）与 {ch} 不匹配")
        i += 1
    for opener, opened in stack:
        problems.append(f"第 {opened} 行 {opener} 未闭合")
    if in_string:
        problems.append("字符串未闭合")
    return problems


def main() -> int:
    problems = []

    if not PBX.exists():
        print("缺少 project.pbxproj")
        return 1
    text = PBX.read_text(encoding="utf-8")
    problems.extend(f"project.pbxproj: {p}" for p in check_balance(text))

    defined = set(RE_DEFINED.findall(text))
    referenced = set(RE_ID.findall(text))
    missing = sorted(referenced - defined)
    if missing:
        problems.append(f"project.pbxproj: 引用了未定义的对象 {missing}")

    build_files = dict(RE_BUILD_FILE.findall(text))
    file_refs = {ref: name.strip() for ref, name in RE_FILE_REF.findall(text)}
    if not build_files:
        problems.append("project.pbxproj: 没找到 PBXBuildFile 段")

    # Sources 构建阶段列出的 buildFile
    phase = re.search(
        r"\b" + ID + r"\b[^\n]*= \{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask[^;]*;[^}]*?files = \(([^)]*)\);",
        text,
        re.S,
    )
    if not phase:
        problems.append("project.pbxproj: 找不到 Sources 构建阶段")
        listed = []
    else:
        listed = re.findall(r"\b(" + ID + r")\b", phase.group(1))

    in_sources = set()
    for bf in listed:
        ref = build_files.get(bf)
        if ref is None:
            problems.append(f"project.pbxproj: {bf} 在 Sources 里但没有 PBXBuildFile 定义")
            continue
        name = file_refs.get(ref)
        if name is None:
            problems.append(f"project.pbxproj: {bf} 的 fileRef {ref} 不是 PBXFileReference")
            continue
        in_sources.add(name)

    on_disk = {p.name for p in SRC.glob("*.swift")}
    for name in sorted(on_disk - in_sources):
        problems.append(f"project.pbxproj: 源码 {name} 没有加入 Sources 构建阶段")
    for name in sorted(in_sources - on_disk):
        if name.endswith(".swift"):
            problems.append(f"project.pbxproj: Sources 里列出的 {name} 不存在")
    print(f"  Sources 收录 {len(in_sources)} 个文件，目录里有 {len(on_disk)} 个 Swift 文件")

    # Resources 阶段
    res = re.search(
        r"\b" + ID + r"\b[^\n]*= \{\s*isa = PBXResourcesBuildPhase;\s*buildActionMask[^;]*;[^}]*?files = \(([^)]*)\);",
        text,
        re.S,
    )
    if not res or not re.findall(r"\b(" + ID + r")\b", res.group(1)):
        problems.append("project.pbxproj: Resources 阶段为空（缺少 Assets.xcassets）")
    else:
        res_refs = [build_files.get(bf) for bf in re.findall(r"\b(" + ID + r")\b", res.group(1))]
        res_names = {file_refs.get(ref) for ref in res_refs if ref}
        expected = {"Assets.xcassets", "PrivacyInfo.xcprivacy"}
        if res_names != expected:
            problems.append(f"project.pbxproj: Resources 里应为 {expected}，实际 {res_names}")

    # 隐私清单（上架必需）
    privacy = SRC / "PrivacyInfo.xcprivacy"
    if not privacy.exists():
        problems.append("缺少 PrivacyInfo.xcprivacy（上架需要）")
    else:
        try:
            with open(privacy, "rb") as fh:
                data = plistlib.load(fh)
            for key in ("NSPrivacyTracking", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"):
                if key not in data:
                    problems.append(f"PrivacyInfo.xcprivacy: 缺少 {key}")
            print(f"  隐私清单已就绪（接入 API {len(data.get('NSPrivacyAccessedAPITypes', []))} 项）")
        except Exception as exc:  # noqa: BLE001
            problems.append(f"PrivacyInfo.xcprivacy: 解析失败 {exc}")

    # Info.plist
    info = SRC / "Info.plist"
    if not info.exists():
        problems.append("缺少 Info.plist")
    else:
        try:
            with open(info, "rb") as fh:
                data = plistlib.load(fh)
            for key in ("CFBundleDisplayName", "CFBundleIdentifier",
                        "UILaunchScreen", "UISupportedInterfaceOrientations"):
                if key not in data:
                    problems.append(f"Info.plist: 缺少 {key}")
            print(f"  Info.plist 显示名 = {data.get('CFBundleDisplayName')}")
        except Exception as exc:  # noqa: BLE001
            problems.append(f"Info.plist: 解析失败 {exc}")

    # 资源目录
    assets = SRC / "Assets.xcassets"
    contents_files = sorted(assets.rglob("Contents.json"))
    for path in contents_files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{path.parent.name}/Contents.json: JSON 解析失败 {exc}")
            continue
        for image in data.get("images", []):
            filename = image.get("filename")
            if filename and not (path.parent / filename).exists():
                problems.append(f"{path.parent.name}: 缺 {filename}")
    print(f"  资源目录检查 {len(contents_files)} 个 Contents.json")

    print()
    if problems:
        print("发现问题：")
        for item in sorted(set(problems)):
            print("  -", item)
        return 1
    print("工程文件与资源检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
