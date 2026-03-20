import Foundation
import AppKit

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
                if line.isEmpty { continue }
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
