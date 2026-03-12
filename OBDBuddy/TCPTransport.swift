import Foundation
import Network
import Observation

/// ELM327 transport over a TCP socket, for use with emulators during development.
@MainActor
@Observable
final class TCPTransport: ELM327Transport {

    var transportState: TransportState = .disconnected
    var connectedDeviceName: String?
    var transportError: String?

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?

    /// Buffer for incoming TCP data (ELM327 responses end with ">").
    private var responseBuffer = ""

    /// Continuation for the current pending command response.
    private var responseContinuation: CheckedContinuation<String, Never>?

    init(host: String = "127.0.0.1", port: UInt16 = 35000) {
        self.host = host
        self.port = port
    }

    /// Initiate a TCP connection to the configured host and port.
    func connect() {
        guard transportState == .disconnected else { return }

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            transportError = "Invalid port: \(port)"
            return
        }

        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = connection
        transportState = .connecting
        connectedDeviceName = "\(host):\(port)"

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.transportState = .ready
                    self.transportError = nil
                    self.startReceiving()
                case .failed(let error):
                    self.transportError = "Connection failed: \(error.localizedDescription)"
                    self.cleanup()
                case .cancelled:
                    self.cleanup()
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        cleanup()
    }

    func sendCommand(_ command: String) async -> String {
        guard let connection, transportState == .ready else { return "" }

        responseBuffer = ""

        let response = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            responseContinuation = continuation
            let data = Data((command + "\r").utf8)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.transportError = "Send failed: \(error.localizedDescription)"
                        self.responseContinuation?.resume(returning: "")
                        self.responseContinuation = nil
                    }
                }
            })
        }

        return response
    }

    // MARK: - Private

    private func startReceiving() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let data, let chunk = String(data: data, encoding: .utf8) {
                    self.responseBuffer += chunk

                    // ELM327 signals end of response with ">"
                    if self.responseBuffer.contains(">") {
                        let response = self.responseBuffer
                            .replacingOccurrences(of: ">", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        self.responseContinuation?.resume(returning: response)
                        self.responseContinuation = nil
                        self.responseBuffer = ""
                    }
                }

                if let error {
                    self.transportError = "Receive error: \(error.localizedDescription)"
                    self.responseContinuation?.resume(returning: "")
                    self.responseContinuation = nil
                    return
                }

                if isComplete {
                    self.cleanup()
                    return
                }

                // Continue receiving next chunk
                self.startReceiving()
            }
        }
    }

    private func cleanup() {
        transportState = .disconnected
        connectedDeviceName = nil
        responseContinuation?.resume(returning: "")
        responseContinuation = nil
        responseBuffer = ""
        connection = nil
    }
}
