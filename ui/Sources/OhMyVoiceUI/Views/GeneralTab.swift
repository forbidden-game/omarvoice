import SwiftUI

struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    @State private var historyText: String = ""

    var body: some View {
        Form {
            Section("快捷键") {
                HotkeyField(settings: settings, bridge: bridge)
            }

            Section("行为") {
                Picker("语言", selection: $settings.language) {
                    Text("自动检测").tag("auto")
                    Text("中文为主").tag("zh")
                    Text("英文为主").tag("en")
                }
                .onChange(of: settings.language) {
                    try? settings.save()
                }

                Toggle("开机启动", isOn: $settings.autostart)
                    .onChange(of: settings.autostart) { _, newValue in
                        try? settings.save()
                        bridge.send(.toggleAutostart(enabled: newValue))
                    }

                Toggle("转写完成时通知", isOn: $settings.notificationOnComplete)
                    .onChange(of: settings.notificationOnComplete) {
                        try? settings.save()
                    }
            }

            Section("数据") {
                HStack {
                    Text("历史记录上限")
                    Spacer()
                    TextField("", value: $settings.historyMaxEntries, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .onChange(of: settings.historyMaxEntries) {
                            try? settings.save()
                        }
                    Text("条")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}
