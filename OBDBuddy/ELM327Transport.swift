import Foundation

/// Transport-agnostic connection states for any ELM327 adapter.
enum TransportState: Equatable {
    case disconnected
    case connecting
    case ready
}

/// Protocol for any ELM327-compatible transport (BLE, TCP, etc.).
/// Conforming types must be @Observable classes for SwiftUI integration.
@MainActor
protocol ELM327Transport: AnyObject, Observable {
    /// Current connection state of the transport.
    var transportState: TransportState { get }

    /// Human-readable name of the connected device/endpoint, or nil.
    var connectedDeviceName: String? { get }

    /// Optional error message from the transport layer.
    var transportError: String? { get set }

    /// Send an AT or OBD-II command and await the complete response
    /// (everything up to the ">" prompt, with the prompt stripped).
    func sendCommand(_ command: String) async -> String

    /// Disconnect and clean up resources.
    func disconnect()
}
