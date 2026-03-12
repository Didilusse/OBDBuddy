import Foundation

/// A single sensor reading parsed from an OBD-II data source.
struct OBDReading {
    let seconds: Double
    let pid: String
    let value: Double
    let units: String
}

/// The four gauge values displayed on the dashboard.
struct GaugeSnapshot {
    var rpm: Double = 0
    var speedMPH: Double = 0
    var throttlePercent: Double = 0
    var coolantTempF: Double = 100
}

/// Parses the semicolon-delimited CSV format exported by OBD-II logging apps.
enum CSVParser {

    /// PID strings we care about for the 4 main gauges.
    static let gaugePIDs: Set<String> = [
        "Engine RPM",
        "Vehicle speed",
        "Throttle position",
        "Engine coolant temperature"
    ]

    /// Parse all rows from the CSV, optionally filtering to a set of PIDs.
    static func parse(url: URL, pidFilter: Set<String>? = nil) throws -> [OBDReading] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var readings: [OBDReading] = []

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let fields = trimmed.components(separatedBy: ";").map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }

            guard fields.count >= 4,
                  let seconds = Double(fields[0]),
                  let value = Double(fields[2]) else {
                continue
            }

            let pid = fields[1]
            if let filter = pidFilter, !filter.contains(pid) { continue }

            readings.append(OBDReading(
                seconds: seconds,
                pid: pid,
                value: value,
                units: fields[3]
            ))
        }

        return readings.sorted { $0.seconds < $1.seconds }
    }
}
