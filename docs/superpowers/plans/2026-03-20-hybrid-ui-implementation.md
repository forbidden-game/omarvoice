# OhMyVoice 混合架构 UI 重构 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 PyObjC 手动布局的设置面板和 rumps.Window 历史弹窗替换为 SwiftUI 原生窗口，通过 subprocess + JSON Lines IPC 与 Python 主进程通信。

**Architecture:** Python 主进程（rumps 菜单栏、hotkey、ASR）保持不动。新增 Swift Package 编译为 `ohmyvoice-ui` 命令行可执行文件，按需启动显示设置或历史窗口。Swift 直接读写 settings.json、只读 history.db，需要 Python 执行动作时通过 stdin/stdout JSON Lines 通信。

**Tech Stack:** Swift 6 + SwiftUI + Swift Package Manager（UI）；Python 3.11+ + rumps + PyObjC（运行时）；SQLite3（历史数据）；JSON Lines（IPC）

**Spec:** `docs/superpowers/specs/2026-03-20-hybrid-ui-design.md`

---

## 文件结构

### 新建

```
ui/
├── Package.swift                          # SPM 配置，macOS 14+
├── Sources/
│   ├── OhMyVoiceUI/                       # 库目标（可测试）
│   │   ├── IPC/
│   │   │   ├── IPCBridge.swift            # stdin/stdout JSON Lines 读写
│   │   │   ├── MessageTypes.swift         # OutgoingMessage / IncomingMessage 枚举
│   │   │   └── Transport.swift            # 协议抽象（StdioTransport / MockTransport）
│   │   ├── Stores/
│   │   │   ├── SettingsStore.swift         # settings.json 读写，ObservableObject
│   │   │   └── HistoryStore.swift          # history.db 只读查询，ObservableObject
│   │   └── Views/
│   │       ├── PreferencesView.swift       # TabView 入口 + 4 tab
│   │       ├── GeneralTab.swift            # 快捷键、行为、数据
│   │       ├── AudioTab.swift              # 输入、反馈、录音
│   │       ├── RecognitionTab.swift         # Prompt 模板、模型
│   │       ├── AboutTab.swift              # 图标、版本、模型状态、链接
│   │       ├── HistoryView.swift           # 搜索列表 + 清空
│   │       └── HotkeyField.swift           # 自定义快捷键录制控件
│   └── CLI/
│       └── main.swift                      # 可执行入口：参数解析、NSApp 启动
└── Tests/
    └── OhMyVoiceUITests/
        ├── IPCBridgeTests.swift
        ├── SettingsStoreTests.swift
        └── HistoryStoreTests.swift

src/ohmyvoice/
    └── ui_bridge.py                        # 新模块：子进程管理 + IPC 消息分发

tests/
    ├── test_settings_reload.py             # Settings.reload() 测试
    └── test_ui_bridge.py                   # UIBridge IPC 消息处理测试
```

### 删除

```
src/ohmyvoice/preferences.py              # 被 SwiftUI 取代
tests/test_preferences.py                  # 对应 preferences.py 的测试（如果存在）
test_preferences_visual.py                 # 根目录下的视觉测试脚本（如果存在）
```

### 修改

```
src/ohmyvoice/app.py          # _on_settings / _on_history 改为启动 Swift 子进程
src/ohmyvoice/settings.py     # 新增 reload() 方法和 path 属性
src/ohmyvoice/history.py      # 暴露 db_path 属性
```

### 删除

```
src/ohmyvoice/preferences.py  # 整个文件，被 SwiftUI 取代
```

### 新建（根目录）

```
Makefile                       # 统一构建入口
```

---

## Task 1: Swift Package 骨架 + 构建验证

**Files:**
- Create: `ui/Package.swift`
- Create: `ui/Sources/CLI/main.swift`
- Create: `ui/Sources/OhMyVoiceUI/Placeholder.swift`
- Create: `ui/Tests/OhMyVoiceUITests/PlaceholderTests.swift`

- [ ] **Step 1: 创建 Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ohmyvoice-ui",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "OhMyVoiceUI",
            path: "Sources/OhMyVoiceUI"
        ),
        .executableTarget(
            name: "ohmyvoice-ui",
            dependencies: ["OhMyVoiceUI"],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "OhMyVoiceUITests",
            dependencies: ["OhMyVoiceUI"],
            path: "Tests/OhMyVoiceUITests"
        ),
    ]
)
```

- [ ] **Step 2: 创建最小源文件**

`ui/Sources/OhMyVoiceUI/Placeholder.swift`:
```swift
import Foundation

public enum OhMyVoiceUI {
    public static let protocolVersion = 1
}
```

`ui/Sources/CLI/main.swift`:
```swift
import Foundation
import OhMyVoiceUI

print("ohmyvoice-ui v0.1 (protocol \(OhMyVoiceUI.protocolVersion))")
```

`ui/Tests/OhMyVoiceUITests/PlaceholderTests.swift`:
```swift
import Testing
@testable import OhMyVoiceUI

@Test func protocolVersionIsOne() {
    #expect(OhMyVoiceUI.protocolVersion == 1)
}
```

- [ ] **Step 3: 构建验证**

Run: `cd ui && swift build 2>&1`
Expected: Build successful

- [ ] **Step 4: 测试验证**

Run: `cd ui && swift test 2>&1`
Expected: All tests passed

- [ ] **Step 5: 运行验证**

Run: `cd ui && swift run ohmyvoice-ui 2>&1`
Expected: `ohmyvoice-ui v0.1 (protocol 1)`

- [ ] **Step 6: Commit**

```bash
git add ui/
git commit -m "feat(ui): scaffold Swift Package with library + executable targets"
```

---

## Task 2: IPC Transport 抽象 + Message 类型

**Files:**
- Create: `ui/Sources/OhMyVoiceUI/IPC/Transport.swift`
- Create: `ui/Sources/OhMyVoiceUI/IPC/MessageTypes.swift`
- Create: `ui/Tests/OhMyVoiceUITests/IPCBridgeTests.swift`

- [ ] **Step 1: 写测试 — OutgoingMessage 序列化**

`ui/Tests/OhMyVoiceUITests/IPCBridgeTests.swift`:
```swift
import Testing
import Foundation
@testable import OhMyVoiceUI

@Test func readyMessageSerializesToJSON() throws {
    let data = OutgoingMessage.ready.toJSONLine()
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "ready")
    #expect(json["protocol"] as? Int == 1)
}

@Test func reloadModelMessageSerializesToJSON() throws {
    let data = OutgoingMessage.reloadModel(quantization: "8bit").toJSONLine()
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "reload_model")
    #expect(json["quantization"] as? String == "8bit")
}

@Test func finishHotkeyCaptureSerializesToJSON() throws {
    let data = OutgoingMessage.finishHotkeyCapture(
        modifiers: ["command", "shift"], key: "space"
    ).toJSONLine()
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "finish_hotkey_capture")
    #expect(json["modifiers"] as? [String] == ["command", "shift"])
    #expect(json["key"] as? String == "space")
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd ui && swift test 2>&1`
Expected: FAIL — `OutgoingMessage` not found

- [ ] **Step 3: 实现 MessageTypes**

`ui/Sources/OhMyVoiceUI/IPC/MessageTypes.swift`:
```swift
import Foundation

public struct MicDevice: Codable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public enum OutgoingMessage: Sendable {
    case ready
    case reloadModel(quantization: String)
    case updateMic(device: String?)
    case toggleAutostart(enabled: Bool)
    case startHotkeyCapture
    case finishHotkeyCapture(modifiers: [String], key: String)
    case cancelHotkeyCapture
    case clearHistory
    case close

    public func toJSONLine() -> Data {
        var dict: [String: Any] = [:]
        switch self {
        case .ready:
            dict["type"] = "ready"
            dict["protocol"] = OhMyVoiceUI.protocolVersion
        case .reloadModel(let q):
            dict["type"] = "reload_model"
            dict["quantization"] = q
        case .updateMic(let device):
            dict["type"] = "update_mic"
            dict["device"] = device as Any
        case .toggleAutostart(let enabled):
            dict["type"] = "toggle_autostart"
            dict["enabled"] = enabled
        case .startHotkeyCapture:
            dict["type"] = "start_hotkey_capture"
        case .finishHotkeyCapture(let mods, let key):
            dict["type"] = "finish_hotkey_capture"
            dict["modifiers"] = mods
            dict["key"] = key
        case .cancelHotkeyCapture:
            dict["type"] = "cancel_hotkey_capture"
        case .clearHistory:
            dict["type"] = "clear_history"
        case .close:
            dict["type"] = "close"
        }
        return try! JSONSerialization.data(withJSONObject: dict)
    }
}

public enum IncomingMessage: Sendable {
    case state(modelLoaded: Bool, modelName: String, quantization: String,
               diskUsage: String, micDevices: [MicDevice], version: String?)
    case modelReloading
    case modelReloaded(success: Bool, error: String?)
    case hotkeyPaused
    case autostartDone(success: Bool)
    case historyCleared
    case unknown(type: String)

    public static func parse(from data: Data) -> IncomingMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        switch type {
        case "state":
            let devicesRaw = json["mic_devices"] as? [[String: Any]] ?? []
            let devices = devicesRaw.compactMap { d in
                (d["name"] as? String).map { MicDevice(name: $0) }
            }
            return .state(
                modelLoaded: json["model_loaded"] as? Bool ?? false,
                modelName: json["model_name"] as? String ?? "",
                quantization: json["quantization"] as? String ?? "",
                diskUsage: json["disk_usage"] as? String ?? "",
                micDevices: devices,
                version: json["version"] as? String
            )
        case "model_reloading":
            return .modelReloading
        case "model_reloaded":
            return .modelReloaded(
                success: json["success"] as? Bool ?? false,
                error: json["error"] as? String
            )
        case "hotkey_paused":
            return .hotkeyPaused
        case "autostart_done":
            return .autostartDone(success: json["success"] as? Bool ?? false)
        case "history_cleared":
            return .historyCleared
        default:
            return .unknown(type: type)
        }
    }
}
```

- [ ] **Step 4: 写测试 — IncomingMessage 反序列化**

追加到 `IPCBridgeTests.swift`:
```swift
@Test func stateMessageParsesCorrectly() throws {
    let json = """
    {"type":"state","model_loaded":true,"model_name":"Qwen3-ASR-0.6B","quantization":"4bit","disk_usage":"1.2 GB","mic_devices":[{"name":"MacBook Pro Mic"}],"version":"0.1.0"}
    """.data(using: .utf8)!
    let msg = IncomingMessage.parse(from: json)
    guard case .state(let loaded, let name, let quant, let disk, let mics, let version) = msg else {
        Issue.record("Expected .state, got \(String(describing: msg))")
        return
    }
    #expect(loaded == true)
    #expect(name == "Qwen3-ASR-0.6B")
    #expect(quant == "4bit")
    #expect(disk == "1.2 GB")
    #expect(mics.count == 1)
    #expect(mics[0].name == "MacBook Pro Mic")
    #expect(version == "0.1.0")
}

@Test func modelReloadedFailureParsesError() {
    let json = """
    {"type":"model_reloaded","success":false,"error":"Out of memory"}
    """.data(using: .utf8)!
    let msg = IncomingMessage.parse(from: json)
    guard case .modelReloaded(let success, let error) = msg else {
        Issue.record("Expected .modelReloaded")
        return
    }
    #expect(success == false)
    #expect(error == "Out of memory")
}

@Test func unknownTypeReturnsUnknown() {
    let json = """
    {"type":"future_message","data":123}
    """.data(using: .utf8)!
    let msg = IncomingMessage.parse(from: json)
    guard case .unknown(let type) = msg else {
        Issue.record("Expected .unknown")
        return
    }
    #expect(type == "future_message")
}

@Test func invalidJSONReturnsNil() {
    let data = "not json".data(using: .utf8)!
    #expect(IncomingMessage.parse(from: data) == nil)
}
```

- [ ] **Step 5: 运行测试**

Run: `cd ui && swift test 2>&1`
Expected: All tests passed

- [ ] **Step 6: 实现 Transport 协议**

`ui/Sources/OhMyVoiceUI/IPC/Transport.swift`:
```swift
import Foundation

public protocol MessageTransport: Sendable {
    func send(_ data: Data)
    func startReading(handler: @escaping @Sendable (Data) -> Void)
}

public final class StdioTransport: MessageTransport, @unchecked Sendable {
    public init() {}

    public func send(_ data: Data) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        fflush(stdout)
    }

    public func startReading(handler: @escaping @Sendable (Data) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine(strippingNewline: true) {
                if line.isEmpty { continue }  // skip empty lines, only nil = EOF
                if let data = line.data(using: .utf8) {
                    handler(data)
                }
            }
            // stdin closed (nil from readLine) — Python process exited
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

public final class MockTransport: MessageTransport, @unchecked Sendable {
    public private(set) var sentMessages: [Data] = []
    private var handler: ((Data) -> Void)?

    public init() {}

    public func send(_ data: Data) {
        sentMessages.append(data)
    }

    public func startReading(handler: @escaping @Sendable (Data) -> Void) {
        self.handler = handler
    }

    public func feedMessage(_ json: String) {
        if let data = json.data(using: .utf8) {
            handler?(data)
        }
    }
}
```

- [ ] **Step 7: Commit**

```bash
git add ui/Sources/OhMyVoiceUI/IPC/ ui/Tests/
git commit -m "feat(ui): IPC message types, serialization, transport abstraction"
```

---

## Task 3: IPCBridge — 消息收发中心

**Files:**
- Create: `ui/Sources/OhMyVoiceUI/IPC/IPCBridge.swift`
- Modify: `ui/Tests/OhMyVoiceUITests/IPCBridgeTests.swift`

- [ ] **Step 1: 写测试 — Bridge 收发消息**

追加到 `IPCBridgeTests.swift`:
```swift
@Test func bridgeSendsReadyOnStart() throws {
    let transport = MockTransport()
    let bridge = IPCBridge(transport: transport)
    bridge.send(.ready)
    #expect(transport.sentMessages.count == 1)
    let json = try JSONSerialization.jsonObject(with: transport.sentMessages[0]) as! [String: Any]
    #expect(json["type"] as? String == "ready")
}

@Test func bridgeDispatchesIncomingState() async throws {
    let transport = MockTransport()
    let bridge = IPCBridge(transport: transport)
    bridge.startListening()

    transport.feedMessage("""
    {"type":"state","model_loaded":true,"model_name":"Qwen3","quantization":"4bit","disk_usage":"1 GB","mic_devices":[]}
    """)

    // Give main queue time to dispatch
    try await Task.sleep(for: .milliseconds(100))

    guard case .state(let loaded, _, _, _, _, _) = bridge.lastMessage else {
        Issue.record("Expected .state")
        return
    }
    #expect(loaded == true)
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd ui && swift test 2>&1`
Expected: FAIL — `IPCBridge` not found

- [ ] **Step 3: 实现 IPCBridge**

`ui/Sources/OhMyVoiceUI/IPC/IPCBridge.swift`:
```swift
import Foundation
import Combine

public final class IPCBridge: ObservableObject, @unchecked Sendable {
    @Published public private(set) var lastMessage: IncomingMessage?
    @Published public private(set) var modelLoaded: Bool = false
    @Published public private(set) var modelName: String = ""
    @Published public private(set) var quantization: String = ""
    @Published public private(set) var diskUsage: String = ""
    @Published public private(set) var micDevices: [MicDevice] = []
    @Published public private(set) var isModelReloading: Bool = false
    @Published public private(set) var modelReloadError: String?
    @Published public private(set) var isHotkeyPaused: Bool = false
    @Published public private(set) var appVersion: String = "0.1.0"

    private let transport: MessageTransport

    public init(transport: MessageTransport) {
        self.transport = transport
    }

    public func send(_ message: OutgoingMessage) {
        transport.send(message.toJSONLine())
    }

    public func startListening() {
        transport.startReading { [weak self] data in
            guard let message = IncomingMessage.parse(from: data) else { return }
            Task { @MainActor [weak self] in
                self?.handleMessage(message)
            }
        }
    }

    @MainActor
    private func handleMessage(_ message: IncomingMessage) {
        lastMessage = message
        switch message {
        case .state(let loaded, let name, let quant, let disk, let mics, let version):
            modelLoaded = loaded
            modelName = name
            quantization = quant
            diskUsage = disk
            micDevices = mics
            if let version { appVersion = version }
        case .modelReloading:
            isModelReloading = true
            modelReloadError = nil
        case .modelReloaded(let success, let error):
            isModelReloading = false
            if !success {
                modelReloadError = error ?? "Unknown error"
            }
        case .hotkeyPaused:
            isHotkeyPaused = true
        case .autostartDone:
            break
        case .historyCleared:
            break
        case .unknown:
            break
        }
    }
}
```

- [ ] **Step 4: 运行测试**

Run: `cd ui && swift test 2>&1`
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add ui/Sources/OhMyVoiceUI/IPC/IPCBridge.swift ui/Tests/
git commit -m "feat(ui): IPCBridge with ObservableObject state management"
```

---

## Task 4: SettingsStore — settings.json 读写

**Files:**
- Create: `ui/Sources/OhMyVoiceUI/Stores/SettingsStore.swift`
- Create: `ui/Tests/OhMyVoiceUITests/SettingsStoreTests.swift`

- [ ] **Step 1: 写测试**

`ui/Tests/OhMyVoiceUITests/SettingsStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import OhMyVoiceUI

@Test func loadsDefaultsWhenFileDoesNotExist() {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("settings.json").path
    let store = SettingsStore(path: path)
    #expect(store.language == "auto")
    #expect(store.autostart == false)
    #expect(store.soundFeedback == true)
    #expect(store.maxRecordingSeconds == 60)
    #expect(store.activePromptTemplate == "coding")
    #expect(store.modelQuantization == "4bit")
    #expect(store.historyMaxEntries == 1000)
}

@Test func loadsFromExistingFile() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let path = tmp.appendingPathComponent("settings.json").path
    let json: [String: Any] = [
        "language": "zh",
        "autostart": true,
        "hotkey": ["modifiers": ["command", "shift"], "key": "r"],
        "audio": ["sound_feedback": false, "max_recording_seconds": 30, "input_device": "USB Mic"],
        "model": ["quantization": "8bit", "name": "Qwen3-ASR-0.6B", "path": "~/.cache"],
        "prompt": ["active_template": "custom", "custom_prompt": "hello",
                   "templates": ["coding": "c", "meeting": "m", "general": ""]],
        "notification_on_complete": true,
        "history_max_entries": 500,
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    try data.write(to: URL(fileURLWithPath: path))

    let store = SettingsStore(path: path)
    #expect(store.language == "zh")
    #expect(store.autostart == true)
    #expect(store.soundFeedback == false)
    #expect(store.maxRecordingSeconds == 30)
    #expect(store.modelQuantization == "8bit")
    #expect(store.hotkeyModifiers == ["command", "shift"])
    #expect(store.hotkeyKey == "r")
    #expect(store.activePromptTemplate == "custom")
    #expect(store.customPrompt == "hello")
    #expect(store.historyMaxEntries == 500)
}

@Test func savesChangesToFile() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let path = tmp.appendingPathComponent("settings.json").path

    let store = SettingsStore(path: path)
    store.language = "en"
    store.save()

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["language"] as? String == "en")
}

@Test func hotkeyDisplayFormatsCorrectly() {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + "/settings.json").path
    let store = SettingsStore(path: tmp)
    store.hotkeyModifiers = ["command", "shift"]
    store.hotkeyKey = "space"
    #expect(store.hotkeyDisplay == "⌘⇧SPACE")
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd ui && swift test 2>&1`
Expected: FAIL — `SettingsStore` not found

- [ ] **Step 3: 实现 SettingsStore**

`ui/Sources/OhMyVoiceUI/Stores/SettingsStore.swift`:
```swift
import Foundation
import Combine

public final class SettingsStore: ObservableObject {
    private let filePath: String
    private var data: [String: Any]

    // --- Published properties (flat, for SwiftUI binding) ---
    @Published public var language: String
    @Published public var autostart: Bool
    @Published public var notificationOnComplete: Bool
    @Published public var historyMaxEntries: Int
    @Published public var soundFeedback: Bool
    @Published public var maxRecordingSeconds: Int
    @Published public var inputDevice: String?
    @Published public var modelQuantization: String
    @Published public var activePromptTemplate: String
    @Published public var customPrompt: String
    @Published public var hotkeyModifiers: [String]
    @Published public var hotkeyKey: String

    // Read-only (from file, not user-editable in preferences)
    public let modelName: String
    public let promptTemplates: [String: String]

    private static let defaults: [String: Any] = [
        "language": "auto",
        "autostart": false,
        "notification_on_complete": false,
        "history_max_entries": 1000,
        "hotkey": ["modifiers": ["option"], "key": "space"],
        "audio": [
            "input_device": NSNull(),
            "sound_feedback": true,
            "max_recording_seconds": 60,
        ],
        "model": [
            "name": "Qwen3-ASR-0.6B",
            "quantization": "4bit",
            "path": "~/.cache/ohmyvoice/models/",
        ],
        "prompt": [
            "active_template": "coding",
            "custom_prompt": "",
            "templates": [
                "coding": "这是一位程序员对 coding agent 的口述指令。",
                "meeting": "这是一段会议讨论录音，可能涉及多人发言。",
                "general": "",
            ],
        ],
    ]

    public init(path: String) {
        self.filePath = path
        let loaded = Self.loadJSON(path: path)
        self.data = Self.deepMerge(base: Self.defaults, override: loaded)

        let hotkey = data["hotkey"] as? [String: Any] ?? [:]
        let audio = data["audio"] as? [String: Any] ?? [:]
        let model = data["model"] as? [String: Any] ?? [:]
        let prompt = data["prompt"] as? [String: Any] ?? [:]

        self.language = data["language"] as? String ?? "auto"
        self.autostart = data["autostart"] as? Bool ?? false
        self.notificationOnComplete = data["notification_on_complete"] as? Bool ?? false
        self.historyMaxEntries = data["history_max_entries"] as? Int ?? 1000
        self.hotkeyModifiers = hotkey["modifiers"] as? [String] ?? ["option"]
        self.hotkeyKey = hotkey["key"] as? String ?? "space"
        self.soundFeedback = audio["sound_feedback"] as? Bool ?? true
        self.maxRecordingSeconds = audio["max_recording_seconds"] as? Int ?? 60
        self.inputDevice = audio["input_device"] as? String
        self.modelQuantization = model["quantization"] as? String ?? "4bit"
        self.modelName = model["name"] as? String ?? "Qwen3-ASR-0.6B"
        self.activePromptTemplate = prompt["active_template"] as? String ?? "coding"
        self.customPrompt = prompt["custom_prompt"] as? String ?? ""
        self.promptTemplates = prompt["templates"] as? [String: String] ?? [:]
    }

    public func save() {
        data["language"] = language
        data["autostart"] = autostart
        data["notification_on_complete"] = notificationOnComplete
        data["history_max_entries"] = historyMaxEntries
        var hotkey = data["hotkey"] as? [String: Any] ?? [:]
        hotkey["modifiers"] = hotkeyModifiers
        hotkey["key"] = hotkeyKey
        data["hotkey"] = hotkey
        var audio = data["audio"] as? [String: Any] ?? [:]
        audio["sound_feedback"] = soundFeedback
        audio["max_recording_seconds"] = maxRecordingSeconds
        audio["input_device"] = inputDevice as Any
        data["audio"] = audio
        var model = data["model"] as? [String: Any] ?? [:]
        model["quantization"] = modelQuantization
        data["model"] = model
        var prompt = data["prompt"] as? [String: Any] ?? [:]
        prompt["active_template"] = activePromptTemplate
        prompt["custom_prompt"] = customPrompt
        data["prompt"] = prompt

        let url = URL(fileURLWithPath: filePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let jsonData = try? JSONSerialization.data(
            withJSONObject: data,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? jsonData.write(to: url)
        }
    }

    public var hotkeyDisplay: String {
        let symbols: [String: String] = [
            "command": "⌘", "option": "⌥", "control": "⌃", "shift": "⇧"
        ]
        let mods = hotkeyModifiers.map { symbols[$0] ?? $0 }.joined()
        return "\(mods)\(hotkeyKey.uppercased())"
    }

    public func activePromptText() -> String {
        if activePromptTemplate == "custom" {
            return customPrompt
        }
        return promptTemplates[activePromptTemplate] ?? ""
    }

    // --- Private helpers ---

    private static func loadJSON(path: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func deepMerge(base: [String: Any], override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let baseDict = result[key] as? [String: Any],
               let overDict = value as? [String: Any] {
                result[key] = deepMerge(base: baseDict, override: overDict)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
```

- [ ] **Step 4: 运行测试**

Run: `cd ui && swift test 2>&1`
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add ui/Sources/OhMyVoiceUI/Stores/SettingsStore.swift ui/Tests/
git commit -m "feat(ui): SettingsStore reads/writes settings.json with defaults"
```

---

## Task 5: HistoryStore — SQLite 只读查询

**Files:**
- Create: `ui/Sources/OhMyVoiceUI/Stores/HistoryStore.swift`
- Create: `ui/Tests/OhMyVoiceUITests/HistoryStoreTests.swift`

- [ ] **Step 1: 写测试**

`ui/Tests/OhMyVoiceUITests/HistoryStoreTests.swift`:
```swift
import Testing
import Foundation
import SQLite3
@testable import OhMyVoiceUI

/// Creates a temp SQLite DB with test data, returns path
func makeTempDB(records: [(String, Double, String)]) throws -> String {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".db").path
    var db: OpaquePointer?
    sqlite3_open(path, &db)
    sqlite3_exec(db, """
        CREATE TABLE transcriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            duration_seconds REAL NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX idx_id ON transcriptions(id DESC);
    """, nil, nil, nil)
    for (text, duration, date) in records {
        let sql = "INSERT INTO transcriptions (text, duration_seconds, created_at) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, (text as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, duration)
        sqlite3_bind_text(stmt, 3, (date as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
    sqlite3_close(db)
    return path
}

@Test func loadsRecentRecords() throws {
    let path = try makeTempDB(records: [
        ("hello world", 2.5, "2024-03-20 10:00:00"),
        ("second record", 3.1, "2024-03-20 10:01:00"),
    ])
    let store = HistoryStore(dbPath: path)
    store.loadPage()
    #expect(store.records.count == 2)
    // Most recent first (ORDER BY id DESC)
    #expect(store.records[0].text == "second record")
    #expect(store.records[1].text == "hello world")
}

@Test func searchFiltersResults() throws {
    let path = try makeTempDB(records: [
        ("hello world", 2.5, "2024-03-20 10:00:00"),
        ("goodbye world", 3.1, "2024-03-20 10:01:00"),
        ("something else", 1.0, "2024-03-20 10:02:00"),
    ])
    let store = HistoryStore(dbPath: path)
    store.search(query: "world")
    #expect(store.records.count == 2)
}

@Test func paginationLoads50PerPage() throws {
    var records: [(String, Double, String)] = []
    for i in 0..<75 {
        records.append(("record \(i)", 1.0, "2024-03-20 10:\(String(format: "%02d", i / 60)):\(String(format: "%02d", i % 60))"))
    }
    let path = try makeTempDB(records: records)
    let store = HistoryStore(dbPath: path)
    store.loadPage()
    #expect(store.records.count == 50)
    store.loadNextPage()
    #expect(store.records.count == 75)
    #expect(store.hasMore == false)
}

@Test func emptyDatabaseReturnsEmptyList() throws {
    let path = try makeTempDB(records: [])
    let store = HistoryStore(dbPath: path)
    store.loadPage()
    #expect(store.records.isEmpty)
    #expect(store.hasMore == false)
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd ui && swift test 2>&1`
Expected: FAIL — `HistoryStore` not found

- [ ] **Step 3: 实现 HistoryStore**

`ui/Sources/OhMyVoiceUI/Stores/HistoryStore.swift`:
```swift
import Foundation
import SQLite3

public struct TranscriptionRecord: Identifiable, Sendable {
    public let id: Int
    public let text: String
    public let durationSeconds: Double
    public let createdAt: String

    public var durationDisplay: String {
        String(format: "%.1f 秒", durationSeconds)
    }

    public var preview: String {
        let lines = text.components(separatedBy: .newlines)
            .prefix(2).joined(separator: " ")
        if lines.count > 100 {
            return String(lines.prefix(100)) + "..."
        }
        return lines
    }
}

public final class HistoryStore: ObservableObject {
    @Published public private(set) var records: [TranscriptionRecord] = []
    @Published public private(set) var hasMore: Bool = true

    private nonisolated(unsafe) var db: OpaquePointer?
    private let pageSize = 50
    private var currentOffset = 0
    private let dbPath: String

    public init(dbPath: String) {
        self.dbPath = dbPath
        sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    public func loadPage() {
        records = []
        currentOffset = 0
        hasMore = true
        loadNextPage()
    }

    public func loadNextPage() {
        guard hasMore, let db else { return }
        let sql = """
            SELECT id, text, duration_seconds, created_at
            FROM transcriptions ORDER BY id DESC
            LIMIT ? OFFSET ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int(stmt, 1, Int32(pageSize))
        sqlite3_bind_int(stmt, 2, Int32(currentOffset))

        var newRecords: [TranscriptionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let record = TranscriptionRecord(
                id: Int(sqlite3_column_int(stmt, 0)),
                text: String(cString: sqlite3_column_text(stmt, 1)),
                durationSeconds: sqlite3_column_double(stmt, 2),
                createdAt: String(cString: sqlite3_column_text(stmt, 3))
            )
            newRecords.append(record)
        }
        sqlite3_finalize(stmt)

        records.append(contentsOf: newRecords)
        currentOffset += newRecords.count
        hasMore = newRecords.count == pageSize
    }

    public func search(query: String) {
        guard let db else { return }
        records = []
        currentOffset = 0

        let sql = """
            SELECT id, text, duration_seconds, created_at
            FROM transcriptions WHERE text LIKE ?
            ORDER BY id DESC LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, ("%\(query)%" as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(pageSize))

        while sqlite3_step(stmt) == SQLITE_ROW {
            let record = TranscriptionRecord(
                id: Int(sqlite3_column_int(stmt, 0)),
                text: String(cString: sqlite3_column_text(stmt, 1)),
                durationSeconds: sqlite3_column_double(stmt, 2),
                createdAt: String(cString: sqlite3_column_text(stmt, 3))
            )
            records.append(record)
        }
        sqlite3_finalize(stmt)
        hasMore = false // search doesn't paginate
    }

    public func refresh() {
        loadPage()
    }
}
```

- [ ] **Step 4: 运行测试**

Run: `cd ui && swift test 2>&1`
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add ui/Sources/OhMyVoiceUI/Stores/HistoryStore.swift ui/Tests/
git commit -m "feat(ui): HistoryStore with SQLite read-only queries and pagination"
```

---

## Task 6: SwiftUI 设置面板 — 4 Tab 视图

**Files:**
- Create: `ui/Sources/OhMyVoiceUI/Views/PreferencesView.swift`
- Create: `ui/Sources/OhMyVoiceUI/Views/GeneralTab.swift`
- Create: `ui/Sources/OhMyVoiceUI/Views/AudioTab.swift`
- Create: `ui/Sources/OhMyVoiceUI/Views/RecognitionTab.swift`
- Create: `ui/Sources/OhMyVoiceUI/Views/AboutTab.swift`
- Create: `ui/Sources/OhMyVoiceUI/Views/HotkeyField.swift`

**注意：** SwiftUI 视图不做单元测试。通过 `swift build` 编译验证 + 后续手动验证。

- [ ] **Step 1: 实现 PreferencesView 入口**

`ui/Sources/OhMyVoiceUI/Views/PreferencesView.swift`:
```swift
import SwiftUI

public struct PreferencesView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    public init(settings: SettingsStore, bridge: IPCBridge) {
        self.settings = settings
        self.bridge = bridge
    }

    public var body: some View {
        TabView {
            GeneralTab(settings: settings, bridge: bridge)
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }
            AudioTab(settings: settings, bridge: bridge)
                .tabItem {
                    Label("音频", systemImage: "waveform")
                }
            RecognitionTab(settings: settings, bridge: bridge)
                .tabItem {
                    Label("识别", systemImage: "sparkles")
                }
            AboutTab(settings: settings, bridge: bridge)
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .onAppear {
            bridge.send(.ready)
        }
    }
}
```

- [ ] **Step 2: 实现 GeneralTab**

`ui/Sources/OhMyVoiceUI/Views/GeneralTab.swift`:
```swift
import SwiftUI

struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    var body: some View {
        Form {
            Section("快捷键") {
                HotkeyField(settings: settings, bridge: bridge)
            }
            Section("行为") {
                Picker("语言偏好", selection: $settings.language) {
                    Text("自动检测").tag("auto")
                    Text("中文为主").tag("zh")
                    Text("英文为主").tag("en")
                }
                .onChange(of: settings.language) { _, _ in settings.save() }

                Toggle("开机自启", isOn: $settings.autostart)
                    .onChange(of: settings.autostart) { _, newValue in
                        settings.save()
                        bridge.send(.toggleAutostart(enabled: newValue))
                    }

                Toggle("完成通知", isOn: $settings.notificationOnComplete)
                    .onChange(of: settings.notificationOnComplete) { _, _ in settings.save() }
            }
            Section("数据") {
                HStack {
                    Text("历史记录上限")
                    Spacer()
                    TextField("", value: $settings.historyMaxEntries, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("条")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: settings.historyMaxEntries) { _, _ in settings.save() }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: 实现 AudioTab**

`ui/Sources/OhMyVoiceUI/Views/AudioTab.swift`:
```swift
import SwiftUI

struct AudioTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    var body: some View {
        Form {
            Section("输入") {
                Picker("麦克风", selection: Binding(
                    get: { settings.inputDevice ?? "" },
                    set: { newValue in
                        let device = newValue.isEmpty ? nil : newValue
                        settings.inputDevice = device
                        settings.save()
                        bridge.send(.updateMic(device: device))
                    }
                )) {
                    Text("系统默认").tag("")
                    ForEach(bridge.micDevices, id: \.name) { device in
                        Text(device.name).tag(device.name)
                    }
                }
            }
            Section("反馈") {
                Toggle(isOn: $settings.soundFeedback) {
                    VStack(alignment: .leading) {
                        Text("提示音")
                        Text("录音开始和转写完成时播放")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: settings.soundFeedback) { _, _ in settings.save() }
            }
            Section("录音") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("最长录音时间")
                        Spacer()
                        Text("\(settings.maxRecordingSeconds) 秒")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxRecordingSeconds) },
                            set: { settings.maxRecordingSeconds = Int($0) }
                        ),
                        in: 10...120,
                        step: 5
                    )
                    Text("超时自动停止转写")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: settings.maxRecordingSeconds) { _, _ in settings.save() }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 4: 实现 RecognitionTab**

`ui/Sources/OhMyVoiceUI/Views/RecognitionTab.swift`:
```swift
import SwiftUI

struct RecognitionTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge
    @State private var previousQuantization: String = ""

    private var isCustom: Bool { settings.activePromptTemplate == "custom" }

    var body: some View {
        Form {
            Section("Prompt 模板") {
                Picker("当前模板", selection: $settings.activePromptTemplate) {
                    Text("编程").tag("coding")
                    Text("会议").tag("meeting")
                    Text("日常").tag("general")
                    Text("自定义").tag("custom")
                }
                .onChange(of: settings.activePromptTemplate) { _, _ in settings.save() }

                TextEditor(text: isCustom
                    ? $settings.customPrompt
                    : .constant(settings.activePromptText())
                )
                .font(.system(.body, design: .monospaced))
                .frame(height: 90)
                .disabled(!isCustom)
                .opacity(isCustom ? 1.0 : 0.6)
                .onChange(of: settings.customPrompt) { _, _ in
                    if isCustom { settings.save() }
                }

                Text("选择"自定义"后可编辑内容，预设模板仅供预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("模型") {
                Picker("量化精度", selection: $settings.modelQuantization) {
                    Text("4-bit").tag("4bit")
                    Text("8-bit").tag("8bit")
                }
                .disabled(bridge.isModelReloading)
                .onChange(of: settings.modelQuantization) { oldValue, newValue in
                    if oldValue != newValue && !oldValue.isEmpty {
                        previousQuantization = oldValue
                        settings.save()
                        bridge.send(.reloadModel(quantization: newValue))
                    }
                }
                .onAppear { previousQuantization = settings.modelQuantization }

                if bridge.isModelReloading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("重新加载中...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = bridge.modelReloadError {
                    Text("加载失败: \(error)")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .onAppear {
                            // Revert picker to previous value
                            settings.modelQuantization = previousQuantization
                            settings.save()
                        }
                }

                Text("⚠ 切换精度需要重新加载模型（约 5 秒）")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 5: 实现 AboutTab**

`ui/Sources/OhMyVoiceUI/Views/AboutTab.swift`:
```swift
import SwiftUI

struct AboutTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    Text("OhMyVoice")
                        .font(.title2.bold())
                    Text("版本 \(bridge.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("模型") {
                LabeledContent("名称") {
                    Text(bridge.modelName.isEmpty ? settings.modelName : bridge.modelName)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("状态") {
                    Text(bridge.modelLoaded ? "已加载" : "未加载")
                        .foregroundStyle(bridge.modelLoaded ? .green : .secondary)
                }
                LabeledContent("磁盘占用") {
                    Text(bridge.diskUsage.isEmpty ? "—" : bridge.diskUsage)
                        .foregroundStyle(.secondary)
                }
            }

            Section("链接") {
                Link("GitHub 项目主页", destination: URL(string: "https://github.com/user/ohmyvoice")!)
                Link("反馈与建议", destination: URL(string: "https://github.com/user/ohmyvoice/issues")!)
            }
        }
        .formStyle(.grouped)
    }
}
```

> **注意**：About tab 中的 GitHub URL 仍为占位符。在确定真实 repo URL 后更新。

- [ ] **Step 6: 实现 HotkeyField**

`ui/Sources/OhMyVoiceUI/Views/HotkeyField.swift`:
```swift
import SwiftUI
import AppKit

struct HotkeyField: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge
    @State private var isCapturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("按住说话")
                Text("按住录音，松开转写")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(settings.hotkeyDisplay)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button(isCapturing ? "按下新组合..." : "录制") {
                startCapture()
            }
            .disabled(isCapturing)
        }
    }

    private func startCapture() {
        isCapturing = true
        bridge.send(.startHotkeyCapture)
        // Wait for hotkey_paused confirmation, then start local monitoring
        // In practice, we start monitoring immediately — the slight race is acceptable
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = parseModifiers(event.modifierFlags)
            let key = keyName(for: event.keyCode)
            if let key, !mods.isEmpty {
                finishCapture(modifiers: mods, key: key)
            }
            return nil // consume the event
        }
    }

    private func finishCapture(modifiers: [String], key: String) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isCapturing = false
        settings.hotkeyModifiers = modifiers
        settings.hotkeyKey = key
        settings.save()
        bridge.send(.finishHotkeyCapture(modifiers: modifiers, key: key))
    }

    private func parseModifiers(_ flags: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.command) { result.append("command") }
        if flags.contains(.shift) { result.append("shift") }
        if flags.contains(.option) { result.append("option") }
        if flags.contains(.control) { result.append("control") }
        return result
    }

    private func keyName(for keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            49: "space", 0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f",
            5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
            45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t",
            32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
            36: "return", 48: "tab", 53: "escape",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        ]
        return map[keyCode]
    }
}
```

- [ ] **Step 7: 构建验证**

Run: `cd ui && swift build 2>&1`
Expected: Build succeeded

- [ ] **Step 8: Commit**

```bash
git add ui/Sources/OhMyVoiceUI/Views/
git commit -m "feat(ui): SwiftUI preferences views — 4 tabs with vibrancy and grouped forms"
```

---

## Task 7: SwiftUI 历史记录窗口

**Files:**
- Create: `ui/Sources/OhMyVoiceUI/Views/HistoryView.swift`

- [ ] **Step 1: 实现 HistoryView**

`ui/Sources/OhMyVoiceUI/Views/HistoryView.swift`:
```swift
import SwiftUI
import AppKit

public struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var bridge: IPCBridge
    @State private var searchText = ""
    @State private var expandedID: Int?
    @State private var showClearConfirmation = false

    public init(store: HistoryStore, bridge: IPCBridge) {
        self.store = store
        self.bridge = bridge
    }

    public var body: some View {
        VStack(spacing: 0) {
            if store.records.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "暂无转写记录",
                    systemImage: "mic.slash",
                    description: Text("按住快捷键说话后，记录会出现在这里")
                )
            } else {
                List {
                    ForEach(store.records) { record in
                        RecordRow(record: record, isExpanded: expandedID == record.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    expandedID = expandedID == record.id ? nil : record.id
                                }
                            }
                            .onAppear {
                                // Pagination: load more when near bottom
                                if record.id == store.records.last?.id && store.hasMore {
                                    store.loadNextPage()
                                }
                            }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索转写记录...")
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                store.loadPage()
            } else {
                store.search(query: newValue)
            }
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("清空全部") {
                    showClearConfirmation = true
                }
                .disabled(store.records.isEmpty)
            }
        }
        .confirmationDialog("确定要清空所有转写记录吗？", isPresented: $showClearConfirmation) {
            Button("清空全部", role: .destructive) {
                bridge.send(.clearHistory)
            }
            Button("取消", role: .cancel) {}
        }
        .frame(width: 520, minHeight: 400)
        .background(.ultraThinMaterial)
        .onAppear {
            bridge.send(.ready)
            store.loadPage()
        }
    }
}

struct RecordRow: View {
    let record: TranscriptionRecord
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isExpanded ? record.text : record.preview)
                .lineLimit(isExpanded ? nil : 2)
            HStack {
                Text(record.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(record.durationDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("复制到剪贴板")
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: 构建验证**

Run: `cd ui && swift build 2>&1`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add ui/Sources/OhMyVoiceUI/Views/HistoryView.swift
git commit -m "feat(ui): HistoryView with search, pagination, copy, and clear-all"
```

---

## Task 8: Swift 入口 — 参数解析 + 窗口管理

**Files:**
- Modify: `ui/Sources/CLI/main.swift`

- [ ] **Step 1: 实现 main.swift**

`ui/Sources/CLI/main.swift`:
```swift
import AppKit
import SwiftUI
import OhMyVoiceUI

// --- Argument parsing ---
let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: ohmyvoice-ui <preferences|history> [--settings PATH | --db PATH]\n", stderr)
    exit(1)
}

let command = args[1]

func argValue(for flag: String) -> String? {
    if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
        return args[idx + 1]
    }
    return nil
}

// --- App setup ---
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let transport = StdioTransport()

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch command {
        case "preferences":
            let settingsPath = argValue(for: "--settings")
                ?? NSHomeDirectory() + "/.config/ohmyvoice/settings.json"
            showPreferences(settingsPath: settingsPath)
        case "history":
            let dbPath = argValue(for: "--db")
                ?? NSHomeDirectory() + "/.local/share/ohmyvoice/history.db"
            showHistory(dbPath: dbPath)
        default:
            fputs("Unknown command: \(command)\n", stderr)
            exit(1)
        }
    }

    func showPreferences(settingsPath: String) {
        let bridge = IPCBridge(transport: transport)
        let settings = SettingsStore(path: settingsPath)
        let view = PreferencesView(settings: settings, bridge: bridge)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OhMyVoice 设置"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window

        bridge.startListening()
        app.activate(ignoringOtherApps: true)
    }

    func showHistory(dbPath: String) {
        let bridge = IPCBridge(transport: transport)
        let store = HistoryStore(dbPath: dbPath)
        let view = HistoryView(store: store, bridge: bridge)

        // Listen for history_cleared to refresh
        let observation = bridge.$lastMessage.sink { message in
            if case .historyCleared = message {
                store.refresh()
            }
        }
        // Keep observation alive
        objc_setAssociatedObject(self, "historySink", observation, .OBJC_ASSOCIATION_RETAIN)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "转写历史"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window

        bridge.startListening()
        app.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Send close message and exit
        transport.send(OutgoingMessage.close.toJSONLine())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: 构建验证**

Run: `cd ui && swift build 2>&1`
Expected: Build succeeded

- [ ] **Step 3: 快速启动验证**（仅 preferences，不连 Python）

Run: `cd ui && echo '{"type":"state","model_loaded":false,"model_name":"","quantization":"","disk_usage":"","mic_devices":[]}' | swift run ohmyvoice-ui preferences 2>&1 &; sleep 3; kill %1 2>/dev/null`

Expected: 窗口短暂出现，无崩溃

- [ ] **Step 4: 删除 Placeholder.swift，移动常量**

删除 `ui/Sources/OhMyVoiceUI/Placeholder.swift`。在 `ui/Sources/OhMyVoiceUI/IPC/MessageTypes.swift` 顶部添加：

```swift
public enum OhMyVoiceUI {
    public static let protocolVersion = 1
}
```

确保 `swift build` 仍然通过。

- [ ] **Step 5: Commit**

```bash
git add ui/Sources/CLI/main.swift
git rm ui/Sources/OhMyVoiceUI/Placeholder.swift 2>/dev/null || true
git commit -m "feat(ui): app entry point with argument parsing and window management"
```

---

## Task 9: Python — Settings.reload() + History.db_path

**Files:**
- Modify: `src/ohmyvoice/settings.py`
- Modify: `src/ohmyvoice/history.py`
- Create: `tests/test_settings_reload.py`

- [ ] **Step 1: 写测试**

`tests/test_settings_reload.py`:
```python
import json
import tempfile
from pathlib import Path

from ohmyvoice.settings import Settings


def test_reload_picks_up_file_changes():
    with tempfile.TemporaryDirectory() as d:
        s = Settings(config_dir=Path(d))
        assert s.language == "auto"

        # Simulate Swift writing to settings.json
        data = json.loads(s.path.read_text())
        data["language"] = "zh"
        s.path.write_text(json.dumps(data))

        s.reload()
        assert s.language == "zh"


def test_path_property():
    with tempfile.TemporaryDirectory() as d:
        s = Settings(config_dir=Path(d))
        assert s.path == Path(d) / "settings.json"
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && python -m pytest tests/test_settings_reload.py -v`
Expected: FAIL — `reload` / `path` not found

- [ ] **Step 3: 实现 reload() 和 path 属性**

在 `src/ohmyvoice/settings.py` 的 `Settings` 类中添加：

```python
@property
def path(self) -> Path:
    return self._path

def reload(self):
    """Re-read settings.json from disk (called after Swift UI closes)."""
    self._data = _deep_copy(_DEFAULTS)
    self._load()
```

在 `src/ohmyvoice/history.py` 的 `HistoryDB` 类中添加 `db_path` 属性：

```python
@property
def db_path(self) -> Path:
    return self._db_path
```

同时在 `__init__` 中保存路径：

```python
def __init__(self, db_path: Path | None = None):
    if db_path is None:
        db_path = Path.home() / ".local" / "share" / "ohmyvoice" / "history.db"
    self._db_path = db_path  # 新增
    db_path.parent.mkdir(parents=True, exist_ok=True)
    ...
```

- [ ] **Step 4: 运行测试**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && python -m pytest tests/test_settings_reload.py -v`
Expected: All passed

- [ ] **Step 5: Commit**

```bash
git add src/ohmyvoice/settings.py src/ohmyvoice/history.py tests/test_settings_reload.py
git commit -m "feat: Settings.reload() and path properties for UI bridge"
```

---

## Task 10: Python — UIBridge 子进程管理

**Files:**
- Create: `src/ohmyvoice/ui_bridge.py`
- Create: `tests/test_ui_bridge.py`

- [ ] **Step 1: 写测试**

`tests/test_ui_bridge.py`:
```python
import json
from unittest.mock import MagicMock, patch
from ohmyvoice.ui_bridge import UIBridge


def test_build_state_message():
    app = MagicMock()
    app._settings.model_name = "Qwen3-ASR-0.6B"
    app._settings.model_quantization = "4bit"
    app._engine.is_loaded = True

    bridge = UIBridge(app)
    msg = bridge._build_state_message()

    assert msg["type"] == "state"
    assert msg["model_loaded"] is True
    assert msg["model_name"] == "Qwen3-ASR-0.6B"
    assert msg["quantization"] == "4bit"
    assert isinstance(msg["mic_devices"], list)
    assert "disk_usage" in msg


def test_handle_reload_model():
    app = MagicMock()
    app._settings.model_quantization = "4bit"
    bridge = UIBridge(app)
    bridge._process = MagicMock()
    bridge._process.stdin = MagicMock()
    bridge._process.poll.return_value = None  # process still running

    bridge._handle_message({"type": "reload_model", "quantization": "8bit"})
    # Verify quantization updated in memory immediately
    assert app._settings.model_quantization == "8bit"


def test_handle_toggle_autostart():
    app = MagicMock()
    bridge = UIBridge(app)
    bridge._process = MagicMock()
    bridge._process.stdin = MagicMock()

    bridge._handle_message({"type": "toggle_autostart", "enabled": True})
    # autostart module should be called


def test_handle_start_hotkey_capture():
    app = MagicMock()
    bridge = UIBridge(app)
    bridge._process = MagicMock()
    bridge._process.stdin = MagicMock()

    bridge._handle_message({"type": "start_hotkey_capture"})
    app._hotkey.pause.assert_called_once()


def test_handle_finish_hotkey_capture():
    app = MagicMock()
    bridge = UIBridge(app)
    bridge._process = MagicMock()
    bridge._process.stdin = MagicMock()

    bridge._handle_message({
        "type": "finish_hotkey_capture",
        "modifiers": ["command"],
        "key": "space",
    })
    app._hotkey.update_hotkey.assert_called_once_with(["command"], "space")
    app._hotkey.resume.assert_called_once()


def test_handle_clear_history():
    app = MagicMock()
    bridge = UIBridge(app)
    bridge._process = MagicMock()
    bridge._process.stdin = MagicMock()

    bridge._handle_message({"type": "clear_history"})
    app._history.clear.assert_called_once()


def test_handle_close():
    app = MagicMock()
    bridge = UIBridge(app)
    bridge._process = MagicMock()
    bridge._process.stdin = MagicMock()

    bridge._handle_message({"type": "close"})
    app._settings.reload.assert_called_once()
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && python -m pytest tests/test_ui_bridge.py -v`
Expected: FAIL — `ui_bridge` module not found

- [ ] **Step 3: 实现 UIBridge**

`src/ohmyvoice/ui_bridge.py`:
```python
"""Subprocess management for Swift UI."""

import json
import os
import subprocess
import threading
from pathlib import Path


class UIBridge:
    def __init__(self, app):
        self._app = app
        self._process = None
        self._reader_thread = None

    def open_preferences(self):
        self._launch(
            "preferences",
            "--settings", str(self._app._settings.path),
        )

    def open_history(self):
        self._launch(
            "history",
            "--db", str(self._app._history.db_path),
        )

    @property
    def is_running(self):
        return self._process is not None and self._process.poll() is None

    def _launch(self, *args):
        if self.is_running:
            return  # already open
        binary = self._find_binary()
        if binary is None:
            import rumps
            rumps.alert("OhMyVoice", "UI 组件未找到，请重新安装应用。")
            return
        self._process = subprocess.Popen(
            [str(binary)] + list(args),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,  # line-buffered
        )
        self._reader_thread = threading.Thread(
            target=self._read_loop, daemon=True
        )
        self._reader_thread.start()

    def _find_binary(self) -> Path | None:
        # 1. Environment override
        env_path = os.environ.get("OHMYVOICE_UI_PATH")
        if env_path:
            p = Path(env_path)
            if p.exists():
                return p

        # 2. Development: <project>/ui/.build/release/ohmyvoice-ui
        project_root = Path(__file__).parent.parent.parent
        dev_path = project_root / "ui" / ".build" / "release" / "ohmyvoice-ui"
        if dev_path.exists():
            return dev_path

        # 3. App bundle: <bundle>/Contents/MacOS/ohmyvoice-ui
        import sys
        if getattr(sys, 'frozen', False):
            bundle_path = Path(sys.executable).parent / "ohmyvoice-ui"
            if bundle_path.exists():
                return bundle_path

        return None

    def _read_loop(self):
        try:
            for line in self._process.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    self._handle_message(msg)
                except json.JSONDecodeError:
                    continue
        except Exception:
            pass
        finally:
            self._on_process_exit()

    def _send(self, msg: dict):
        if not self.is_running:
            return
        try:
            self._process.stdin.write(json.dumps(msg, ensure_ascii=False) + "\n")
            self._process.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def _handle_message(self, msg: dict):
        msg_type = msg.get("type")
        if msg_type == "ready":
            proto = msg.get("protocol", 0)
            if proto != 1:
                print(f"Protocol mismatch: Swift={proto}, Python=1")
                # Proceed anyway — Swift side handles its own version check
            self._send(self._build_state_message())
        elif msg_type == "reload_model":
            self._handle_reload_model(msg)
        elif msg_type == "update_mic":
            self._handle_update_mic(msg)
        elif msg_type == "toggle_autostart":
            self._handle_toggle_autostart(msg)
        elif msg_type == "start_hotkey_capture":
            if self._app._hotkey:
                self._app._hotkey.pause()
            self._send({"type": "hotkey_paused"})
        elif msg_type == "finish_hotkey_capture":
            mods = msg.get("modifiers", [])
            key = msg.get("key", "")
            s = self._app._settings
            s.hotkey_modifiers = mods
            s.hotkey_key = key
            s.save()
            if self._app._hotkey:
                self._app._hotkey.update_hotkey(mods, key)
                self._app._hotkey.resume()
        elif msg_type == "cancel_hotkey_capture":
            if self._app._hotkey:
                self._app._hotkey.resume()
        elif msg_type == "clear_history":
            self._app._history.clear()
            self._send({"type": "history_cleared"})
        elif msg_type == "close":
            self._app._settings.reload()
            # _update_recent_menu touches rumps menu, must run on main thread
            import rumps
            rumps.Timer(lambda t: (self._app._update_recent_menu(), t.stop()), 0).start()

    def _build_state_message(self) -> dict:
        try:
            from ohmyvoice.recorder import Recorder
            devices = Recorder.list_input_devices()
            mic_list = [{"name": d["name"]} for d in devices]
        except Exception:
            mic_list = []
        try:
            from ohmyvoice.asr import _cache_dir_for
            bits = int(self._app._settings.model_quantization.replace("bit", ""))
            cache_path = _cache_dir_for(self._app._settings.model_name, bits)
            disk_usage = _dir_size_str(cache_path)
        except Exception:
            disk_usage = "—"
        from ohmyvoice import __version__
        return {
            "type": "state",
            "model_loaded": getattr(self._app._engine, "is_loaded", False),
            "model_name": self._app._settings.model_name,
            "quantization": self._app._settings.model_quantization,
            "disk_usage": disk_usage,
            "mic_devices": mic_list,
            "version": __version__,
        }

    def _handle_reload_model(self, msg):
        quantization = msg.get("quantization", "4bit")
        # Update in-memory settings immediately (Swift already wrote settings.json)
        self._app._settings.model_quantization = quantization
        self._send({"type": "model_reloading"})

        def _reload():
            try:
                engine = self._app._engine
                engine.unload()
                bits = int(quantization.replace("bit", ""))
                engine.load(quantize_bits=bits)
                self._send({"type": "model_reloaded", "success": True})
            except Exception as e:
                self._send({
                    "type": "model_reloaded",
                    "success": False,
                    "error": str(e),
                })

        threading.Thread(target=_reload, daemon=True).start()

    def _handle_update_mic(self, msg):
        device = msg.get("device")
        self._app._settings.input_device = device
        self._app._settings.save()
        try:
            from ohmyvoice.recorder import Recorder
            self._app._recorder = Recorder(sample_rate=16000, device=device)
        except Exception:
            pass

    def _handle_toggle_autostart(self, msg):
        enabled = msg.get("enabled", False)
        self._app._settings.autostart = enabled
        self._app._settings.save()
        try:
            from ohmyvoice import autostart
            if enabled:
                autostart.enable()
            else:
                autostart.disable()
            self._send({"type": "autostart_done", "success": True})
        except Exception:
            self._send({"type": "autostart_done", "success": False})

    def _on_process_exit(self):
        if self._process:
            self._process.wait()  # ensure returncode is set
        exit_code = self._process.returncode if self._process else -1
        # Safety: resume hotkey if it was paused
        if self._app._hotkey:
            self._app._hotkey.resume()
        # Refresh settings from file
        self._app._settings.reload()
        # Update menu on main thread (rumps requires it)
        import rumps
        rumps.Timer(lambda t: (self._app._update_recent_menu(), t.stop()), 0).start()
        self._process = None
        if exit_code != 0:
            print(f"ohmyvoice-ui exited with code {exit_code}")


def _dir_size_str(path):
    if not path.exists():
        return "—"
    total = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
    if total < 1024:
        return f"{total} B"
    if total < 1024 ** 2:
        return f"{total / 1024:.0f} KB"
    if total < 1024 ** 3:
        return f"{total / 1024 ** 2:.0f} MB"
    return f"{total / 1024 ** 3:.1f} GB"
```

- [ ] **Step 4: 运行测试**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && python -m pytest tests/test_ui_bridge.py -v`
Expected: All passed

- [ ] **Step 5: Commit**

```bash
git add src/ohmyvoice/ui_bridge.py tests/test_ui_bridge.py
git commit -m "feat: UIBridge subprocess manager with IPC message handling"
```

---

## Task 11: Python — app.py 集成 + 清理

**Files:**
- Modify: `src/ohmyvoice/app.py`
- Delete: `src/ohmyvoice/preferences.py`

- [ ] **Step 1: 修改 app.py — 替换 imports 和 init**

在 `src/ohmyvoice/app.py` 中：

移除：
```python
from ohmyvoice.preferences import PreferencesWindow
```

添加：
```python
from ohmyvoice.ui_bridge import UIBridge
```

在 `__init__` 中，将：
```python
self._prefs_window = None
```
替换为：
```python
self._ui_bridge = UIBridge(self)
```

- [ ] **Step 2: 替换 _on_settings 方法**

将：
```python
def _on_settings(self, _):
    if self._prefs_window is None:
        self._prefs_window = PreferencesWindow(self)
    self._prefs_window.show()
```

替换为：
```python
def _on_settings(self, _):
    self._ui_bridge.open_preferences()
```

- [ ] **Step 3: 替换 _on_history 方法**

将整个 `_on_history` 方法替换为：
```python
def _on_history(self, _):
    self._ui_bridge.open_history()
```

- [ ] **Step 4: 删除 preferences.py 及其测试文件**

```bash
git rm src/ohmyvoice/preferences.py
git rm tests/test_preferences.py 2>/dev/null || true
git rm test_preferences_visual.py 2>/dev/null || true
```

- [ ] **Step 5: 验证 Python 模块无导入错误**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && python -c "from ohmyvoice.ui_bridge import UIBridge; print('OK')"`
Expected: `OK`（注意：不导入 OhMyVoiceApp，因为它的构造函数会尝试初始化 Recorder/ASR）

- [ ] **Step 6: 运行全部 Python 测试**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && python -m pytest tests/ -v`
Expected: All passed

- [ ] **Step 7: Commit**

```bash
git add src/ohmyvoice/app.py
git commit -m "feat: wire UIBridge to app, remove PyObjC preferences window"
```

---

## Task 12: Makefile + 构建验证

**Files:**
- Create: `Makefile`

- [ ] **Step 1: 创建 Makefile**

```makefile
.PHONY: build build-swift build-python test test-swift test-python clean run

build: build-swift

build-swift:
	cd ui && swift build -c release

build-python:
	pip install -e ".[dev]"

test: test-swift test-python

test-swift:
	cd ui && swift test

test-python:
	python -m pytest tests/ -v

clean:
	cd ui && swift package clean
	rm -rf ui/.build

run: build-swift
	python -m ohmyvoice
```

- [ ] **Step 2: 运行 make build**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && make build 2>&1`
Expected: Build succeeded

- [ ] **Step 3: 运行 make test**

Run: `cd /Users/fg/work/oss/ohmyvoice-app && make test 2>&1`
Expected: All Swift + Python tests passed

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "build: Makefile for unified Swift + Python build and test"
```

---

## 总结

| Task | 内容 | 关键验证 |
|------|------|---------|
| 1 | Swift Package 骨架 | `swift build` + `swift test` |
| 2 | IPC Message Types + Transport | 序列化/反序列化单元测试 |
| 3 | IPCBridge ObservableObject | Mock transport 状态更新测试 |
| 4 | SettingsStore | 读/写/默认值单元测试 |
| 5 | HistoryStore + SQLite | 查询/搜索/分页单元测试 |
| 6 | SwiftUI 设置面板 (4 tabs) | `swift build` 编译通过 |
| 7 | SwiftUI 历史记录窗口 | `swift build` 编译通过 |
| 8 | Swift main.swift 入口 | `swift build` + 快速启动验证 |
| 9 | Python Settings.reload() | pytest 单元测试 |
| 10 | Python UIBridge | pytest mock 测试 |
| 11 | Python app.py 集成 + 清理 | 模块导入验证 + pytest 全量 |
| 12 | Makefile | `make build` + `make test` |
