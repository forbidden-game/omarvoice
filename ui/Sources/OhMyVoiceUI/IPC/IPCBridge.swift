import Foundation
import Combine

public final class IPCBridge: ObservableObject, @unchecked Sendable {
    @Published public private(set) var lastMessage: IncomingMessage?
    @Published public private(set) var modelLoaded: Bool = false
    @Published public private(set) var modelName: String = ""
    @Published public private(set) var quantization: String = ""
    @Published public private(set) var diskUsage: Int = 0
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
        case .state(let payload):
            modelLoaded = payload.modelLoaded
            modelName = payload.modelName
            quantization = payload.quantization
            diskUsage = payload.diskUsage
            micDevices = payload.micDevices
            appVersion = payload.version
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
