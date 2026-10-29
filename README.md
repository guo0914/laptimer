# 分段计时 · LapTimer（iOS / SwiftUI）

按你选定的方案实现：**方案 A 深色驾驶舱 + 纯 SwiftUI 工程 + 限时到点只提醒不打断**。

- 正计时：分段记录（本段 / 累计 / 与历史平均的偏差 / 最快段高亮）、限时进度、暂停继续、进程重启后恢复、结束可存历史
- 倒计时：预设时长、自定义、开始/暂停/继续/重置、+1 分钟、到点提醒
- 触觉反馈、本地通知、历史记录与分段分享

效果图：`../../shots/scheme-a.png`

## 目录

```
LapTimer/
├─ LapTimer.xcodeproj/          # 双击用 Xcode 打开
├─ LapTimer/
│  ├─ LapTimerApp.swift         # App 入口 + 根视图（模式切换、前后台处理）
│  ├─ Theme.swift               # 配色、渐变
│  ├─ Components.swift          # 分段控件、大时间、限时进度条、圆形按钮
│  ├─ TimeFormatting.swift      # 纯格式化逻辑（可脱离 SwiftUI 编译验证）
│  ├─ TimerModels.swift         # 分段 / 会话 / 落盘快照
│  ├─ SessionStore.swift        # JSON 原子落盘
│  ├─ StopwatchEngine.swift     # 正计时引擎（分段 + 限时 + 恢复）
│  ├─ CountdownEngine.swift     # 倒计时引擎
│  ├─ Feedback.swift            # 震动 / 提示音
│  ├─ Notifier.swift            # 后台到点本地通知
│  ├─ HistoryStore.swift        # 历史记录
│  ├─ StopwatchView.swift       # 方案 A 主界面
│  ├─ CountdownView.swift       # 倒计时界面
│  ├─ LimitSheet.swift          # 限时设置
│  ├─ HistoryView.swift         # 记录列表 / 明细 / 分享
│  ├─ Assets.xcassets/          # AppIcon（已生成 1024×1024）+ AccentColor
│  └─ Info.plist
└─ Scripts/
   ├─ logic-check.swift         # 纯逻辑自检（真 Swift 编译，Mac 上跑）
   ├─ structure-check.py        # 括号平衡 / UTF-8 完整性
   ├─ api-check.py              # 视图引用 vs 引擎 API
   ├─ check-project.py          # pbxproj、Info.plist、资源目录
   └─ make-icon.py              # 重新生成 AppIcon
```

## 在 Mac 上跑起来

1. 把整个 `LapTimer` 目录拷到 Mac（或 `git clone`）。
2. `open LapTimer/LapTimer.xcodeproj`。
3. Xcode → Signing & Capabilities → Team 选你自己的账号（`PRODUCT_BUNDLE_IDENTIFIER` 默认 `com.example.LapTimer`，建议改成 `com.你的域名.LapTimer`）。
4. 选 iPhone 模拟器或真机 → Run。部署目标 iOS 17.0，无第三方依赖，不需要 `pod install`。

> 我这边是 Windows，无法编译 / 跑模拟器。已用三个静态检查脚本确认：括号与 UTF-8 完整、视图里引用的引擎成员全部存在、pbxproj 里 15 个源文件都在 Sources 阶段且资源 / Info.plist 合法。逻辑层另有 `logic-check.swift`，你在 Mac 上编译即可跑断言。

### 逻辑自检（可选）

```bash
swiftc LapTimer/TimeFormatting.swift Scripts/logic-check.swift -o /tmp/logiccheck && /tmp/logiccheck
```

覆盖正计时进位、超一小时、倒计时向上取整、分段格式、偏差符号，以及「暂停后不增长 / 残留下起跳时刻不影响」的时间推算。

## 行为约定

| 场景 | 行为 |
| --- | --- |
| 到限时 | 震动 + 提示音 + 进度条转红、显示「已超时 xx:xx」，**计时继续**；后台由本地通知补提醒 |
| 记一段 | 立刻切分，「本段 / 累计」入表，与**此前各段平均值**比较标 `+n"` / `最快` |
| 撤销 | 长按中间「记段」→ 撤销最近一段 |
| 结束 | 弹确认：保存到「记录」/ 直接丢弃 / 继续计时 |
| 切到后台 | 落盘 + 补一条到点通知；回前台按真实时钟重算，不漂移 |
| 杀进程再开 | 从落盘快照恢复（正在跑就继续跑，暂停就停在暂停） |

## 还没做（可作为下一轮）

- 灵动岛 / 锁屏 Live Activity（`ActivityKit`，iOS 16.1+；需要额外 Widget Extension target）
- HealthKit 写入、Apple Watch 端
- iCloud 同步历史
- 深色/浅色双主题（现在固定深色，与方案 A 一致）

## 需要我继续时直接说

例如：「加灵动岛」「改成 B 的白底配色」「把记段做成可拖动排序」「加导出 CSV」。
