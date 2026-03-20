import SwiftUI

struct AudioTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    var body: some View {
        Form {
            Section("输入") {
                Picker("麦克风", selection: $settings.inputDevice) {
                    Text("系统默认").tag(String?.none)
                    ForEach(bridge.micDevices, id: \.name) { device in
                        Text(device.name).tag(String?.some(device.name))
                    }
                }
                .onChange(of: settings.inputDevice) { _, newValue in
                    try? settings.save()
                    bridge.send(.updateMic(deviceName: newValue ?? ""))
                }
            }

            Section("反馈") {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("音效反馈", isOn: $settings.soundFeedback)
                        .onChange(of: settings.soundFeedback) {
                            try? settings.save()
                        }
                    Text("录音开始和转写完成时播放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("录音") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("最长录音时长")
                        Spacer()
                        Text("\(settings.maxRecordingSeconds) 秒")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxRecordingSeconds) },
                            set: { settings.maxRecordingSeconds = Int($0) }
                        ),
                        in: 10...120,
                        step: 5
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("10").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("120").font(.caption).foregroundStyle(.secondary)
                    }
                    .onChange(of: settings.maxRecordingSeconds) {
                        try? settings.save()
                    }
                    Text("超时自动停止转写")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}
