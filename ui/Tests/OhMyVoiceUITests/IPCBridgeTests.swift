import Testing
import Foundation
@testable import OhMyVoiceUI

// MARK: - Outgoing message serialization

@Test func readyMessageSerializesToJSON() throws {
    let data = OutgoingMessage.ready.toJSONLine()
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "ready")
    #expect(json["protocol"] as? Int == OhMyVoiceUI.protocolVersion)
}

@Test func reloadModelMessageSerializesToJSON() throws {
    let data = OutgoingMessage.reloadModel(quantization: "int8").toJSONLine()
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "reload_model")
    #expect(json["quantization"] as? String == "int8")
}

@Test func finishHotkeyCaptureSerializesToJSON() throws {
    let data = OutgoingMessage.finishHotkeyCapture(modifiers: ["cmd", "shift"], key: "a").toJSONLine()
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "finish_hotkey_capture")
    #expect(json["modifiers"] as? [String] == ["cmd", "shift"])
    #expect(json["key"] as? String == "a")
}

// MARK: - Incoming message parsing

@Test func stateMessageParsesCorrectly() throws {
    let raw = """
    {"type":"state","model_loaded":true,"model_name":"whisper-base","quantization":"int8","disk_usage":120,"mic_devices":[{"name":"Built-in Mic"},{"name":"USB Mic"}],"version":"1.2.3"}
    """
    let msg = IncomingMessage.parse(from: raw.data(using: .utf8)!)
    guard case let .state(payload) = msg else {
        Issue.record("Expected .state, got \(String(describing: msg))")
        return
    }
    #expect(payload.modelLoaded == true)
    #expect(payload.modelName == "whisper-base")
    #expect(payload.quantization == "int8")
    #expect(payload.diskUsage == 120)
    #expect(payload.micDevices.count == 2)
    #expect(payload.micDevices[0].name == "Built-in Mic")
    #expect(payload.version == "1.2.3")
}

@Test func modelReloadedFailureParsesError() throws {
    let raw = """
    {"type":"model_reloaded","success":false,"error":"out of memory"}
    """
    let msg = IncomingMessage.parse(from: raw.data(using: .utf8)!)
    guard case let .modelReloaded(success, error) = msg else {
        Issue.record("Expected .modelReloaded, got \(String(describing: msg))")
        return
    }
    #expect(success == false)
    #expect(error == "out of memory")
}

@Test func unknownTypeReturnsUnknown() {
    let raw = """
    {"type":"totally_unknown_event","extra":"data"}
    """
    let msg = IncomingMessage.parse(from: raw.data(using: .utf8)!)
    guard case .unknown = msg else {
        Issue.record("Expected .unknown, got \(String(describing: msg))")
        return
    }
}

@Test func invalidJSONReturnsNil() {
    let data = "not json at all }{".data(using: .utf8)!
    let msg = IncomingMessage.parse(from: data)
    #expect(msg == nil)
}
