import SwiftUI

struct AboutTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bridge: IPCBridge

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.0f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OhMyVoice")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("版本 \(bridge.appVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("模型") {
                LabeledContent("模型名称") {
                    Text(bridge.modelName.isEmpty ? settings.modelName : bridge.modelName)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("加载状态") {
                    if bridge.modelLoaded {
                        Label("已加载", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未加载", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("磁盘占用") {
                    Text(bridge.diskUsage > 0 ? formatBytes(bridge.diskUsage) : "—")
                        .foregroundStyle(.secondary)
                }
            }

            Section("链接") {
                Link(destination: URL(string: "https://github.com/fgprodigal/ohmyvoice")!) {
                    Label("GitHub 仓库", systemImage: "arrow.up.right.square")
                }

                Link(destination: URL(string: "https://github.com/fgprodigal/ohmyvoice/issues")!) {
                    Label("反馈问题", systemImage: "exclamationmark.bubble")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}
