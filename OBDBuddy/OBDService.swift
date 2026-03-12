import Foundation
import Observation

/// Defines the data source for OBD-II readings.
enum OBDMode {
    case csvPlayback
    case liveConnection
}

/// OBD-II PIDs used for polling live data.
enum OBDPID: String, CaseIterable {
    case rpm = "010C"
    case speed = "010D"
    case coolantTemp = "0105"
    case throttle = "0111"
}

/// Provides real-time OBD-II gauge data from either CSV playback or a live BLE adapter.
@MainActor
@Observable
final class OBDService {

    var snapshot = GaugeSnapshot()
    var allReadings: [OBDReading] = []
    var isRunning = false
    var isRecording = false

    /// Latest reading for each PID, keyed by PID name.
    var latestValueByPID: [String: OBDReading] {
        var latest: [String: OBDReading] = [:]
        for reading in allReadings {
            latest[reading.pid] = reading
        }
        return latest
    }

    let mode: OBDMode
    var bleManager: BLEManager?
    var driveStore: DriveStore?

    private var pollingTask: Task<Void, Never>?
    private var currentSession: DriveSession?
    private var recordingStartDate: Date?

    init(mode: OBDMode = .csvPlayback) {
        self.mode = mode
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        switch mode {
        case .csvPlayback:
            startCSVPlayback()
        case .liveConnection:
            startLiveConnection()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        stopRecording()
    }

    func startRecording() {
        guard mode == .liveConnection, !isRecording else { return }
        let now = Date()
        recordingStartDate = now
        currentSession = DriveSession(id: UUID(), startDate: now, dataPoints: [])
        isRecording = true
    }

    func stopRecording() {
        guard isRecording, var session = currentSession else { return }
        session.endDate = Date()
        driveStore?.save(session)
        currentSession = nil
        recordingStartDate = nil
        isRecording = false
    }

    private func recordDataPoint(pid: String, value: Double, units: String) {
        guard isRecording, let start = recordingStartDate else { return }
        let point = DriveDataPoint(
            elapsed: Date().timeIntervalSince(start),
            pid: pid,
            value: value,
            units: units
        )
        currentSession?.dataPoints.append(point)
    }

    // MARK: - CSV Playback

    private func startCSVPlayback() {
        pollingTask = Task {
            guard let url = Bundle.main.url(forResource: "obd2_session", withExtension: "csv") else {
                print("CSV file not found in bundle")
                isRunning = false
                return
            }

            let readings: [OBDReading]
            do {
                // Parse all PIDs so advanced stats view has data
                readings = try CSVParser.parse(url: url)
            } catch {
                print("Failed to parse CSV: \(error)")
                isRunning = false
                return
            }

            guard let firstTimestamp = readings.first?.seconds else {
                isRunning = false
                return
            }

            let startTime = Date.now

            for reading in readings {
                guard !Task.isCancelled else { break }

                let targetOffset = reading.seconds - firstTimestamp
                let elapsed = Date.now.timeIntervalSince(startTime)
                let delay = targetOffset - elapsed

                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                }

                guard !Task.isCancelled else { break }

                allReadings.append(reading)
                applyReading(reading)
            }

            isRunning = false
        }
    }

    // MARK: - Live Connection

    private func startLiveConnection() {
        guard let ble = bleManager, ble.connectionState == .ready else {
            print("BLE not connected")
            isRunning = false
            return
        }

        pollingTask = Task {
            // Initialize ELM327
            _ = await ble.sendCommand("ATZ")     // Reset
            _ = await ble.sendCommand("ATE0")    // Echo off
            _ = await ble.sendCommand("ATL0")    // Linefeeds off
            _ = await ble.sendCommand("ATS0")    // Spaces off
            _ = await ble.sendCommand("ATSP0")   // Auto-detect protocol

            // Poll loop
            while !Task.isCancelled && ble.connectionState == .ready {
                for pid in OBDPID.allCases {
                    guard !Task.isCancelled else { break }

                    let response = await ble.sendCommand(pid.rawValue)
                    if let value = Self.parseOBDResponse(response, pid: pid) {
                        applyLiveValue(value, for: pid)
                    }
                }

                // Small delay between polling cycles to avoid flooding the adapter
                try? await Task.sleep(for: .milliseconds(50))
            }

            isRunning = false
        }
    }

    /// Parse the hex response from ELM327 for a given PID.
    /// Responses have the format "41 XX YY [ZZ]" (with spaces stripped by ATS0: "41XXYY[ZZ]").
    static func parseOBDResponse(_ response: String, pid: OBDPID) -> Double? {
        // Strip non-hex characters and find the response bytes
        let hex = response.filter { $0.isHexDigit }

        // Response starts with "41" + PID byte(s), then data bytes
        // With ATS0 (no spaces), e.g. RPM 010C → response "410C1A2B"
        switch pid {
        case .rpm:
            // Response: 41 0C A B → RPM = (A * 256 + B) / 4
            guard hex.count >= 8,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16),
                  let b = UInt8(hex.substring(6, length: 2), radix: 16) else { return nil }
            return Double(Int(a) * 256 + Int(b)) / 4.0

        case .speed:
            // Response: 41 0D A → Speed in km/h, convert to mph
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) * 0.621371

        case .coolantTemp:
            // Response: 41 05 A → Temp in °C = A - 40, convert to °F
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            let celsius = Double(a) - 40.0
            return celsius * 9.0 / 5.0 + 32.0

        case .throttle:
            // Response: 41 11 A → Throttle = A * 100 / 255
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) * 100.0 / 255.0
        }
    }

    private func applyLiveValue(_ value: Double, for pid: OBDPID) {
        let pidName: String
        let units: String

        switch pid {
        case .rpm:
            snapshot.rpm = value
            pidName = "Engine RPM"; units = "rpm"
        case .speed:
            snapshot.speedMPH = value
            pidName = "Vehicle speed"; units = "mph"
        case .coolantTemp:
            snapshot.coolantTempF = value
            pidName = "Engine coolant temperature"; units = "°F"
        case .throttle:
            snapshot.throttlePercent = value
            pidName = "Throttle position"; units = "%"
        }

        // Populate allReadings so latestValueByPID works in live mode
        allReadings.append(OBDReading(
            seconds: Date().timeIntervalSinceReferenceDate,
            pid: pidName, value: value, units: units
        ))
        recordDataPoint(pid: pidName, value: value, units: units)
    }

    // MARK: - Apply Reading

    private func applyReading(_ reading: OBDReading) {
        switch reading.pid {
        case "Engine RPM":
            snapshot.rpm = reading.value
        case "Vehicle speed":
            snapshot.speedMPH = reading.value
        case "Throttle position":
            snapshot.throttlePercent = reading.value
        case "Engine coolant temperature":
            snapshot.coolantTempF = reading.value
        default:
            break
        }
    }
}
// MARK: - String Hex Substring Helper

extension String {
    /// Extract a substring by character offset and length (for fixed-width hex parsing).
    func substring(_ offset: Int, length: Int) -> String {
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: length)
        return String(self[start..<end])
    }
}

