import Foundation
import Observation

/// Defines the data source for OBD-II readings.
enum OBDMode {
    case csvPlayback
    case live
}

/// OBD-II PIDs used for polling live data.
enum OBDPID: String, CaseIterable {
    case rpm         = "010C"
    case speed       = "010D"
    case coolantTemp = "0105"
    case throttle    = "0111"
    case load        = "0104"
    case iat         = "010F"
    case map         = "010B"
    case timing      = "010E"
    case stft        = "0106"
    case ltft        = "0107"
    case battery     = "0142"
    case o2b1s1      = "0114"
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
    var transport: (any ELM327Transport)?
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
        case .live:
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
        guard mode == .live, !isRecording else { return }
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
        guard let transport, transport.transportState == .ready else {
            print("Transport not connected")
            isRunning = false
            return
        }

        pollingTask = Task {
            // Initialize ELM327
            _ = await transport.sendCommand("ATZ")     // Reset
            _ = await transport.sendCommand("ATE0")    // Echo off
            _ = await transport.sendCommand("ATL0")    // Linefeeds off
            _ = await transport.sendCommand("ATS0")    // Spaces off
            _ = await transport.sendCommand("ATSP0")   // Auto-detect protocol

            // Poll loop
            while !Task.isCancelled && transport.transportState == .ready {
                for pid in OBDPID.allCases {
                    guard !Task.isCancelled else { break }

                    let response = await transport.sendCommand(pid.rawValue)
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

        // Header length depends on PID code length:
        //   Mode 01 PIDs (01XX) → response "41XX..." → 4 hex chars header
        //   Mode 01 PIDs (01XXYY, e.g. 0142) → response "4142..." → 4 hex chars header
        // Data bytes start after "41" + PID byte(s).

        switch pid {
        case .rpm:
            // 41 0C A B → RPM = (A*256 + B) / 4
            guard hex.count >= 8,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16),
                  let b = UInt8(hex.substring(6, length: 2), radix: 16) else { return nil }
            return Double(Int(a) * 256 + Int(b)) / 4.0

        case .speed:
            // 41 0D A → A km/h, convert to mph
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) * 0.621371

        case .coolantTemp:
            // 41 05 A → A - 40 °C, convert to °F
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            let celsius = Double(a) - 40.0
            return celsius * 9.0 / 5.0 + 32.0

        case .throttle:
            // 41 11 A → A / 2.55 %
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) * 100.0 / 255.0

        case .load:
            // 41 04 A → A / 2.55 %
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) * 100.0 / 255.0

        case .iat:
            // 41 0F A → A - 40 °C, convert to °F
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            let celsius = Double(a) - 40.0
            return celsius * 9.0 / 5.0 + 32.0

        case .map:
            // 41 0B A → A kPa
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a)

        case .timing:
            // 41 0E A → A/2 - 64 degrees BTDC
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) / 2.0 - 64.0

        case .stft:
            // 41 06 A → A/1.28 - 100 %
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) / 1.28 - 100.0

        case .ltft:
            // 41 07 A → A/1.28 - 100 %
            guard hex.count >= 6,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) / 1.28 - 100.0

        case .battery:
            // 41 42 A B → (A*256 + B) / 1000 V
            guard hex.count >= 8,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16),
                  let b = UInt8(hex.substring(6, length: 2), radix: 16) else { return nil }
            return Double(Int(a) * 256 + Int(b)) / 1000.0

        case .o2b1s1:
            // 41 14 A B → Voltage = A/200 V (we return voltage; trim = B/1.28 - 100)
            guard hex.count >= 8,
                  let a = UInt8(hex.substring(4, length: 2), radix: 16) else { return nil }
            return Double(a) / 200.0
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
        case .load:
            pidName = "Calculated engine load"; units = "%"
        case .iat:
            pidName = "Intake air temperature"; units = "°F"
        case .map:
            pidName = "Intake manifold pressure"; units = "kPa"
        case .timing:
            pidName = "Ignition timing advance"; units = "° BTDC"
        case .stft:
            pidName = "Short term fuel trim"; units = "%"
        case .ltft:
            pidName = "Long term fuel trim"; units = "%"
        case .battery:
            pidName = "Control module voltage"; units = "V"
        case .o2b1s1:
            pidName = "O2 Sensor B1S1 voltage"; units = "V"
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

