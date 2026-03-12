import Foundation
import CoreBluetooth
import Observation

/// Known BLE service/characteristic UUIDs for common ELM327 OBD-II adapters (e.g. Veepeak BLE+).
enum ELM327BLE {
    static let serviceUUID = CBUUID(string: "FFF0")
    static let writeCharacteristicUUID = CBUUID(string: "FFF1")
    static let notifyCharacteristicUUID = CBUUID(string: "FFF2")
}

/// Represents a discovered BLE peripheral.
struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

/// Connection state of the BLE manager.
enum BLEConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case discoveringServices
    case ready
}

/// Manages CoreBluetooth interactions for ELM327-based OBD-II adapters.
@Observable
final class BLEManager: NSObject, ELM327Transport {

    var connectionState: BLEConnectionState = .disconnected
    var discoveredPeripherals: [DiscoveredPeripheral] = []
    var connectedPeripheralName: String?
    var errorMessage: String?

    // MARK: - ELM327Transport Conformance

    var transportState: TransportState {
        switch connectionState {
        case .disconnected: return .disconnected
        case .scanning, .connecting, .discoveringServices: return .connecting
        case .ready: return .ready
        }
    }

    var connectedDeviceName: String? { connectedPeripheralName }

    var transportError: String? {
        get { errorMessage }
        set { errorMessage = newValue }
    }

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    /// Buffer for incoming BLE data (ELM327 responses end with ">")
    private var responseBuffer = ""

    /// Continuation for the current pending command response.
    private var responseContinuation: CheckedContinuation<String, Never>?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScan() {
        guard centralManager.state == .poweredOn else {
            errorMessage = "Bluetooth is not available"
            return
        }
        discoveredPeripherals.removeAll()
        errorMessage = nil
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScan() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(to discovered: DiscoveredPeripheral) {
        stopScan()
        connectionState = .connecting
        connectedPeripheral = discovered.peripheral
        connectedPeripheral?.delegate = self
        centralManager.connect(discovered.peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    /// Send an AT/OBD command and await the full response (up to the ">" prompt).
    func sendCommand(_ command: String) async -> String {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral,
              connectionState == .ready else {
            return ""
        }

        responseBuffer = ""

        let response = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            responseContinuation = continuation
            let data = Data((command + "\r").utf8)
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }

        return response
    }

    // MARK: - Private

    private func cleanup() {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedPeripheralName = nil
        connectionState = .disconnected
        responseBuffer = ""
        responseContinuation?.resume(returning: "")
        responseContinuation = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            errorMessage = "Bluetooth is not powered on"
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let displayName = name, !displayName.isEmpty else { return }

        // Avoid duplicates
        if discoveredPeripherals.contains(where: { $0.id == peripheral.identifier }) { return }

        let discovered = DiscoveredPeripheral(
            id: peripheral.identifier,
            name: displayName,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )
        discoveredPeripherals.append(discovered)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .discoveringServices
        connectedPeripheralName = peripheral.name
        peripheral.discoverServices([ELM327BLE.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        errorMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
        cleanup()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        cleanup()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == ELM327BLE.serviceUUID }) else {
            errorMessage = "OBD service not found on device"
            disconnect()
            return
        }
        peripheral.discoverCharacteristics(
            [ELM327BLE.writeCharacteristicUUID, ELM327BLE.notifyCharacteristicUUID],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == ELM327BLE.writeCharacteristicUUID {
                writeCharacteristic = characteristic
            } else if characteristic.uuid == ELM327BLE.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        if writeCharacteristic != nil && notifyCharacteristic != nil {
            connectionState = .ready
        } else {
            errorMessage = "Required characteristics not found"
            disconnect()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == ELM327BLE.notifyCharacteristicUUID,
              let data = characteristic.value,
              let chunk = String(data: data, encoding: .utf8) else { return }

        responseBuffer += chunk

        // ELM327 signals end of response with ">"
        if responseBuffer.contains(">") {
            let response = responseBuffer
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            responseContinuation?.resume(returning: response)
            responseContinuation = nil
            responseBuffer = ""
        }
    }
}
