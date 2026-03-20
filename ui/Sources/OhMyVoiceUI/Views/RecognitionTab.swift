import SwiftUI

struct RecognitionTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    @State private var previousQuantization: String = ""

    var isCustomTemplate: Bool {
        settings.activePromptTemplate == "custom"
    }

    var promptText: String {
        if isCustomTemplate {
            return settings.customPrompt
        }
        return settings.promptTemplates[settings.activePromptTemplate] ?? ""
    }

    var body: some View {
        Form {
            Section("Prompt 模板") {
                Picker("模板", selection: $settings.activePromptTemplate) {
                    Text("编程").tag("coding")
                    Text("会议").tag("meeting")
                    Text("日常").tag("general")
                    Text("自定义").tag("custom")
                }
                .onChange(of: settings.activePromptTemplate) {
                    try? settings.save()
                }

                if isCustomTemplate {
                    TextEditor(text: $settings.customPrompt)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 120)
                        .onChange(of: settings.customPrompt) {
                            try? settings.save()
                        }
                } else {
                    TextEditor(text: .constant(promptText))
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 120)
                        .disabled(true)
                        .opacity(0.6)
                }

                Text("Prompt 会附加在每次转写请求之前，帮助模型理解语境。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("模型") {
                Picker("量化精度", selection: $settings.modelQuantization) {
                    Text("4-bit").tag("4bit")
                    Text("8-bit").tag("8bit")
                }
                .disabled(bridge.isModelReloading)
                .onChange(of: settings.modelQuantization) { _, newValue in
                    guard newValue != previousQuantization else { return }
                    try? settings.save()
                    bridge.send(.reloadModel(quantization: newValue))
                }
                .onAppear {
                    previousQuantization = settings.modelQuantization
                }
                .onChange(of: bridge.isModelReloading) { _, isReloading in
                    if !isReloading {
                        if bridge.modelReloadError != nil {
                            // Revert picker to previous value on failure
                            settings.modelQuantization = previousQuantization
                        } else {
                            previousQuantization = settings.modelQuantization
                        }
                    }
                }

                if bridge.isModelReloading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("模型重新加载中…")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }

                if let error = bridge.modelReloadError {
                    Text("加载失败：\(error)")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Text("切换量化精度需要重新加载模型，可能需要数十秒。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}
