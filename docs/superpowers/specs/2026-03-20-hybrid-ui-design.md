# OhMyVoice 混合架构 UI 重构 — 设计规格

取代 `2026-03-20-settings-ui-design.md`（PyObjC 纯 Python 方案）。

## 背景

V1 的设置面板用 PyObjC 手动像素布局实现，存在以下问题：

- 设置窗口内容不可滚动，界面超出屏幕时被裁切
- 历史记录弹窗（rumps.Window）内容溢出且无法控制滚动
- 缺少 vibrancy/glass 视觉效果，与原生 macOS 应用观感差距大
- 手动坐标布局（NSMakeRect）维护成本高，不支持动态字体

## 核心约束

- **Python 运行时层不动**：hotkey（CGEventTap）、录音（sounddevice）、ASR（mlx-qwen3-asr）、剪贴板、通知、菜单栏（rumps）全部保留
- 原因：之前尝试过纯 Swift 版本，按键检测和辅助功能权限始终有问题。当前 Python 版本 CGEventTap 非常灵敏，甚至不需要权限弹窗
- Swift 只负责 UI 渲染

---

## 1. 架构

```
┌─────────────────────────────────────────────────────────┐
│  Python 主进程（rumps 菜单栏 app，常驻运行）              │
│  ├─ HotkeyManager (CGEventTap)                          │
│  ├─ Recorder (sounddevice)                              │
│  ├─ ASREngine (mlx-qwen3-asr)                          │
│  ├─ HistoryDB (SQLite)                                  │
│  ├─ Settings (JSON)                                     │
│  └─ subprocess.Popen ──┐                                │
└────────────────────────┼────────────────────────────────┘
                         │ stdin/stdout (JSON Lines)
                         ▼
┌─────────────────────────────────────────────────────────┐
│  Swift UI 进程（按需启动，窗口关闭即退出）                │
│  ├─ ohmyvoice-ui preferences --settings <path>         │
│  └─ ohmyvoice-ui history --db <path>                   │
│                                                         │
│  ├─ 读/写 settings.json                                 │
│  ├─ 只读 history.db (SQLite)                            │
│  └─ SwiftUI 窗口（vibrancy, Form, List）                │
└─────────────────────────────────────────────────────────┘
```

### Swift 二进制

- 编译为命令行可执行文件 `ohmyvoice-ui`，不是 .app bundle
- 用 `NSApplication.setActivationPolicy(.accessory)` 运行，无 Dock 图标
- 构建工具：Swift Package Manager（`swift build`）
- Python 打包时将编译好的二进制放入 app bundle

### 二进制发现路径

Python 侧按以下顺序查找 `ohmyvoice-ui` 二进制：

1. 环境变量：`OHMYVOICE_UI_PATH`（调试/测试用覆盖，优先级最高）
2. 开发环境：`<project_root>/ui/.build/release/ohmyvoice-ui`（`swift build -c release` 输出）
3. 打包环境：`<app_bundle>/Contents/MacOS/ohmyvoice-ui`（py2app 打包后）

找不到时向用户显示错误提示，不静默失败。

### 项目结构

```
ohmyvoice-app/
├── src/ohmyvoice/              # Python（不动）
├── ui/                         # Swift 项目（新增）
│   ├── Package.swift
│   └── Sources/
│       ├── main.swift           # 入口：解析参数，启动 NSApp
│       ├── IPCBridge.swift      # stdin/stdout JSON 读写
│       ├── SettingsStore.swift  # 读写 settings.json，ObservableObject
│       ├── HistoryStore.swift   # 只读 history.db，ObservableObject
│       ├── PreferencesView.swift
│       └── HistoryView.swift
└── resources/icons/            # 共享图标
```

### 线程模型

- 主线程：SwiftUI 事件循环（NSApplication.run）
- 后台线程：GCD DispatchQueue 读 stdin，收到消息后 `DispatchQueue.main.async` 派发到主线程
- stdout 写入在主线程（用户操作触发，频率低）

---

## 2. IPC 数据契约

### 协议

- 格式：JSON Lines（每行一个完整 JSON 对象，`\n` 分隔）
- Python → Swift：写入 Swift 进程的 stdin
- Swift → Python：从 Swift 进程的 stdout 读取
- 编码：UTF-8
- 所有消息必须有 `"type"` 字段
- `ready` 消息包含 `"protocol": 1`，双方版本不匹配时 Swift 显示升级提示并退出
- IPC 消息使用扁平 key（如 `"quantization": "4bit"`），settings.json 使用嵌套结构（如 `model.quantization`）。两者是不同的接口，Swift 代码需分别处理

### 启动方式

```bash
# 打开设置
ohmyvoice-ui preferences --settings ~/.config/ohmyvoice/settings.json

# 打开历史
ohmyvoice-ui history --db ~/.local/share/ohmyvoice/history.db
```

Python 用 `subprocess.Popen(..., stdin=PIPE, stdout=PIPE)` 启动。文件路径通过命令行参数传入。

### Swift 直接读写的文件

| 文件 | 权限 | 说明 |
|------|------|------|
| settings.json | 读+写 | Swift 读取初始值，修改后直接写回 |
| history.db | 只读 | SQLite，Swift 用只读连接查询。写操作（清空全部）通过 IPC 消息委托 Python 执行 |

### 需要 IPC 通知的设置变更

简单设置（language, notification_on_complete, sound_feedback, max_recording_seconds, active_prompt_template, custom_prompt, history_max_entries）Swift 直接写 settings.json，不发消息。

以下设置变更需要额外发送 IPC 消息，因为 Python 侧要执行动作：

| 设置 | Python 动作 |
|------|------------|
| model_quantization | unload + reload ASR 引擎 |
| input_device | 重建 Recorder 实例 |
| hotkey | HotkeyManager.update_hotkey() + resume() |
| autostart | 创建/删除 LaunchAgent plist |

### Swift → Python 消息类型

```jsonl
{"type": "ready", "protocol": 1}
{"type": "reload_model", "quantization": "4bit"}
{"type": "update_mic", "device": "MacBook Pro Microphone"}
{"type": "update_mic", "device": null}
{"type": "toggle_autostart", "enabled": true}
{"type": "start_hotkey_capture"}
{"type": "finish_hotkey_capture", "modifiers": ["command"], "key": "space"}
{"type": "cancel_hotkey_capture"}
{"type": "clear_history"}
{"type": "close"}
```

### Python → Swift 消息类型

```jsonl
{"type": "state", "model_loaded": true, "model_name": "Qwen3-ASR-0.6B", "quantization": "4bit", "disk_usage": "1.2 GB", "mic_devices": [{"name": "MacBook Pro Microphone"}, {"name": "External USB Mic"}], "version": "0.1.0"}
{"type": "model_reloading"}
{"type": "model_reloaded", "success": true}
{"type": "model_reloaded", "success": false, "error": "Out of memory"}
{"type": "hotkey_paused"}
{"type": "autostart_done", "success": true}
{"type": "history_cleared"}
```

### 生命周期时序

```
用户点击菜单栏"设置..."
  │
  Python: Popen(["ohmyvoice-ui", "preferences", "--settings", path])
  │
  Swift: 启动, 读 settings.json, 显示窗口
  Swift → Python: {"type": "ready"}
  │
  Python → Swift: {"type": "state", ...}
  │
  简单变更（语言/通知/...）:
    Swift: 直接写 settings.json
  │
  需要动作的变更（quantization）:
    Swift: 写 settings.json
    Swift → Python: {"type": "reload_model", "quantization": "8bit"}
    Python → Swift: {"type": "model_reloading"}
    Python → Swift: {"type": "model_reloaded", "success": true}
  │
  Hotkey 录制:
    Swift → Python: {"type": "start_hotkey_capture"}
    Python: HotkeyManager.pause()
    Python → Swift: {"type": "hotkey_paused"}
    Swift: 本地 NSEvent 监听按键组合
    用户按下组合键
    Swift: 写 settings.json
    Swift → Python: {"type": "finish_hotkey_capture", ...}
    Python: HotkeyManager.update_hotkey() + resume()
  │
  用户关闭窗口:
    Swift → Python: {"type": "close"}
    Swift: exit(0)
    Python: 检测子进程退出（exit code 0 = 正常关闭，非 0 = 崩溃）
    Python: 重新读 settings.json 刷新内存状态（无论 exit code）
    Python: 如果有进行中的 model reload，等待完成（不中断）
```

历史窗口生命周期：
```
用户点击菜单栏"全部历史"
  │
  Python: Popen(["ohmyvoice-ui", "history", "--db", db_path])
  │
  Swift: 启动, 打开 history.db (只读), 加载前 50 条, 显示窗口
  Swift → Python: {"type": "ready", "protocol": 1}
  │
  (用户浏览/搜索/复制)
  │
  用户点击"清空全部":
    Swift: 弹出确认对话框
    Swift → Python: {"type": "clear_history"}
    Python: HistoryDB.clear()
    Python → Swift: {"type": "history_cleared"}
    Swift: 刷新列表（重新查询 SQLite）
  │
  用户关闭窗口:
    Swift → Python: {"type": "close"}
    Swift: exit(0)
```

### 错误处理

- **Swift 崩溃**：Python 通过 `Popen.poll()` 检测异常退出。如果 hotkey capture 进行中，自动 resume HotkeyManager
- **Python 崩溃**：Swift 检测 stdin EOF，显示提示后退出
- **settings.json 写冲突**：同一时刻只有一方在写（设置窗口打开时 Python 不修改 settings.json），不会冲突
- **消息格式错误**：接收方 log 错误并忽略，不崩溃
- **model reload 期间窗口关闭**：Python 继续完成 reload（不中断），reload 结果正常应用。Swift 进程已退出，Python 发送的 `model_reloaded` 消息写入已关闭的 stdin 会得到 BrokenPipeError，Python 捕获并忽略

---

## 3. SwiftUI 界面设计

### 视觉方向

- 参照物：Xcode Preferences（工具栏 tab 切换），不是 System Settings（侧边栏）
- 4 个 tab 不需要侧边栏，工具栏 tab 是小型工具应用的标准模式
- 窗口背景：`.background(.ultraThinMaterial)` vibrancy 材质
- 布局：SwiftUI `Form` + `.formStyle(.grouped)`
- Tab：SwiftUI `TabView`，macOS 自动渲染为工具栏 tab 样式
- 亮色/暗色模式：SwiftUI 自动适配

### 设置面板 — 通用 Tab

| Section | 控件 | 交互 |
|---------|------|------|
| 快捷键 | 自定义 HotkeyField + "录制" Button | 点击录制 → 发 IPC start_hotkey_capture → 等待 hotkey_paused → 本地监听按键 → 发 IPC finish_hotkey_capture |
| 行为 | Picker（语言偏好）, Toggle（开机自启）, Toggle（完成通知） | 语言和通知直接写文件；自启 Toggle 写文件 + 发 IPC toggle_autostart |
| 数据 | TextField（历史记录上限）+ "条" 后缀 | 直接写文件 |

### 设置面板 — 音频 Tab

| Section | 控件 | 数据来源 |
|---------|------|---------|
| 输入 | Picker（麦克风列表） | 初始 state 消息中的 mic_devices |
| 反馈 | Toggle（提示音）+ 说明文字 | settings.json |
| 录音 | Slider（10-120秒）+ 实时数值标签 | settings.json |

### 设置面板 — 识别 Tab

| Section | 控件 | 说明 |
|---------|------|------|
| Prompt 模板 | Picker（编程/会议/日常/自定义）+ TextEditor | 预设模板只读预览，自定义可编辑 |
| 模型 | Picker（4-bit/8-bit）+ 状态指示 | 切换后 Picker 禁用，显示 ProgressView("重新加载中...") 直到收到 model_reloaded。成功时恢复正常显示；失败时显示错误文字（systemRed），Picker 回退到原值 |

### 设置面板 — 关于 Tab

| 区域 | 内容 |
|------|------|
| Header | 应用图标（使用真实 app icon）+ "OhMyVoice" + 版本号 |
| 模型 | 加载状态（已加载/未加载）+ 磁盘占用 |
| 链接 | GitHub 项目主页 + 反馈与建议（真实 URL） |

### 历史记录窗口

独立窗口，不是模态弹窗。

```
┌─────────────────────────────────────────┐
│ 🔍 搜索转写记录...            [清空全部] │
├─────────────────────────────────────────┤
│ 这是一段转写文本的预览内容...            │
│ 2024-03-20 14:32 · 3.2 秒         [复制]│
├─────────────────────────────────────────┤
│ 另一段转写记录预览...                    │
│ 2024-03-20 14:28 · 5.1 秒         [复制]│
├─────────────────────────────────────────┤
│              (可滚动列表)                │
└─────────────────────────────────────────┘
```

- SwiftUI `List` + `.searchable()` 原生搜索栏
- 每行：文本预览（2 行截断）、时间戳、录音时长、复制按钮
- 点击行展开显示完整文本
- "清空全部" 需二次确认（`.confirmationDialog`），确认后发 IPC `clear_history` 消息，Python 执行 `HistoryDB.clear()`，回复 `history_cleared` 后 Swift 刷新列表
- 不支持删除单条记录（明确排除，避免复杂度）
- SQLite 查询分页加载：每页 50 条，滚动到距底部 5 条时加载下一页（offset-based pagination）

---

## 4. 功能对齐与变更清单

### 保留（行为不变）

- 菜单栏 app（rumps）及所有菜单项
- 全局 hotkey 按住说话交互
- ASR 转写 → 清理 → 剪贴板 → 历史记录流程
- 设置持久化（settings.json）
- 历史持久化（history.db SQLite）
- 所有设置项和取值范围

### 新增（审计修复项）

- [C1/C3] 滚动支持 — SwiftUI Form/List 天然支持
- [C2] 历史记录完整 UI — 替换 rumps.Window
- [H2] vibrancy 背景 — `.ultraThinMaterial`
- [M3] 模型 reload 进度反馈 — ProgressView
- [M2] 历史记录搜索 — `.searchable()`
- [L1] 修复占位符 URL
- [L2] 使用真实 app icon

### 删除

- `preferences.py`（整个文件，被 Swift UI 取代）
- `app.py` 中的 `_on_history` 方法（rumps.Window 弹窗，被 Swift 历史窗口取代）

### 修改

- `app.py`：`_on_settings` 和 `_on_history` 改为启动 Swift 子进程
- `app.py`：新增 IPC 消息处理逻辑（读 Swift stdout，写 Swift stdin）
- `settings.py`：新增 `reload()` 方法（子进程退出后重新读取 settings.json）

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| Swift 二进制找不到（路径错误、打包遗漏） | 设置窗口无法打开 | 启动前检查二进制存在，失败时 fallback 到错误提示 |
| stdin/stdout 缓冲导致消息延迟 | UI 响应卡顿 | Swift 侧每次写 stdout 后 fflush；Python 侧逐行读取 |
| hotkey capture 期间 Swift 崩溃 | HotkeyManager 永久暂停 | Python 检测子进程退出后自动 resume |
| settings.json 格式被 Swift 写坏 | Python 启动或读取失败 | Swift 写入前验证 JSON 格式；Python 读取失败时用默认值 |
| macOS 版本兼容性 | SwiftUI API 差异 | 最低支持 macOS 14（Sonoma），覆盖主流用户 |
| 构建系统复杂化 | 开发体验下降 | Makefile 统一入口：`make build` 同时编译 Swift + 打包 Python |

---

## 6. 不做的事（明确排除）

- 不改动 hotkey、录音、ASR、剪贴板、通知等 Python 运行时代码
- 不替换 rumps 菜单栏（保持稳定）
- 不添加审计范围外的新功能
- 不引入 Xcode project（只用 Swift Package Manager）
- 不支持 macOS 13 及更早版本
- 不支持删除单条历史记录（只有"清空全部"）
- 不从设置窗口直接跳转到历史窗口（两者是独立进程，从菜单栏分别打开）
