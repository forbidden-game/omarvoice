import SwiftUI
import AppKit

private let keyCodeMap: [UInt16: String] = [
    49: "space", 0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h",
    34: "i", 38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q",
    15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    36: "return", 48: "tab", 53: "escape",
    122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
]

struct HotkeyField: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    @State private var isCapturing = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("按住说话")
                Text("按住录音，松开转写")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isCapturing {
                Text("请按下快捷键…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Button("取消") {
                    stopCapture(cancelled: true)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } else {
                Text(settings.hotkeyDisplay)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Button("录制") {
                    startCapture()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    private func startCapture() {
        isCapturing = true
        bridge.send(.startHotkeyCapture)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event)
            return nil  // Consume the event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard let keyName = keyCodeMap[event.keyCode] else {
            stopCapture(cancelled: true)
            return
        }

        var modifiers: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.append("control") }
        if flags.contains(.option)  { modifiers.append("option") }
        if flags.contains(.shift)   { modifiers.append("shift") }
        if flags.contains(.command) { modifiers.append("command") }

        // Require at least one modifier
        guard !modifiers.isEmpty else { return }

        settings.hotkeyModifiers = modifiers
        settings.hotkeyKey = keyName
        try? settings.save()
        bridge.send(.finishHotkeyCapture(modifiers: modifiers, key: keyName))
        stopCapture(cancelled: false)
    }

    private func stopCapture(cancelled: Bool) {
        isCapturing = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if cancelled {
            bridge.send(.cancelHotkeyCapture)
        }
    }
}
