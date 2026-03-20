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
                .tabItem { Label("通用", systemImage: "gearshape") }
            AudioTab(settings: settings, bridge: bridge)
                .tabItem { Label("音频", systemImage: "waveform") }
            RecognitionTab(settings: settings, bridge: bridge)
                .tabItem { Label("识别", systemImage: "sparkles") }
            AboutTab(settings: settings, bridge: bridge)
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .onAppear { bridge.send(.ready) }
    }
}
