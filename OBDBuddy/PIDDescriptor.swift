import Foundation

/// Format style for gauge display values.
enum GaugeFormatStyle: String, Codable {
    case integer
    case oneDecimal
    case twoDecimal
}

/// Describes a known PID with its default display properties.
struct PIDDescriptor: Identifiable, Hashable {
    let id: String
    let displayTitle: String
    let unit: String
    let range: ClosedRange<Double>
    let warningThreshold: Double?
    let formatStyle: GaugeFormatStyle
    let isTemperature: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PIDDescriptor, rhs: PIDDescriptor) -> Bool {
        lhs.id == rhs.id
    }
}

extension PIDDescriptor {
    /// All known PIDs with their default display properties.
    static let catalog: [String: PIDDescriptor] = {
        let list: [PIDDescriptor] = [
            // Engine
            PIDDescriptor(id: "Engine RPM", displayTitle: "RPM", unit: "rpm",
                          range: 0...7000, warningThreshold: 6500, formatStyle: .integer, isTemperature: false),
            PIDDescriptor(id: "Engine RPM x1000", displayTitle: "RPM x1000", unit: "rpm",
                          range: 0...7, warningThreshold: 6.5, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Engine coolant temperature", displayTitle: "Coolant Temp", unit: "°F",
                          range: 100...230, warningThreshold: 212, formatStyle: .oneDecimal, isTemperature: true),
            PIDDescriptor(id: "Throttle position", displayTitle: "Throttle", unit: "%",
                          range: 0...100, warningThreshold: nil, formatStyle: .integer, isTemperature: false),
            PIDDescriptor(id: "Calculated engine load value", displayTitle: "Engine Load", unit: "%",
                          range: 0...100, warningThreshold: nil, formatStyle: .integer, isTemperature: false),
            PIDDescriptor(id: "Calculated boost", displayTitle: "Boost", unit: "bar",
                          range: -1...1.5, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Timing advance", displayTitle: "Timing Advance", unit: "°",
                          range: -20...60, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Instant engine power (based on fuel consumption)", displayTitle: "Engine Power", unit: "hp",
                          range: 0...150, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),

            // Speed & Position
            PIDDescriptor(id: "Vehicle speed", displayTitle: "Speed", unit: "mph",
                          range: 0...120, warningThreshold: nil, formatStyle: .integer, isTemperature: false),
            PIDDescriptor(id: "Vehicle acceleration", displayTitle: "Acceleration", unit: "g",
                          range: -1...1, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Distance travelled", displayTitle: "Trip Distance", unit: "miles",
                          range: 0...100, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Distance travelled (total)", displayTitle: "Total Distance", unit: "miles",
                          range: 0...200000, warningThreshold: nil, formatStyle: .integer, isTemperature: false),
            PIDDescriptor(id: "Altitude (GPS)", displayTitle: "Altitude", unit: "feet",
                          range: 0...5000, warningThreshold: nil, formatStyle: .integer, isTemperature: false),
            PIDDescriptor(id: "Speed (GPS)", displayTitle: "GPS Speed", unit: "mph",
                          range: 0...120, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Average speed (GPS)", displayTitle: "Avg Speed (GPS)", unit: "mph",
                          range: 0...120, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Average speed", displayTitle: "Avg Speed", unit: "mph",
                          range: 0...120, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),

            // Fuel
            PIDDescriptor(id: "Fuel used", displayTitle: "Fuel Used", unit: "gallon",
                          range: 0...20, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Fuel used (total)", displayTitle: "Total Fuel Used", unit: "gallon",
                          range: 0...100, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Fuel used price", displayTitle: "Fuel Cost", unit: "$",
                          range: 0...100, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Fuel used price (total)", displayTitle: "Total Fuel Cost", unit: "$",
                          range: 0...500, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Calculated instant fuel rate", displayTitle: "Fuel Rate", unit: "gal./h",
                          range: 0...10, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Fuel economizer (based on fuel system status and throttle position)",
                          displayTitle: "Fuel Economizer", unit: "",
                          range: 0...5, warningThreshold: nil, formatStyle: .integer, isTemperature: false),

            // Sensors
            PIDDescriptor(id: "MAF air flow rate", displayTitle: "MAF", unit: "g/sec",
                          range: 0...200, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Power from MAF", displayTitle: "Power (MAF)", unit: "hp",
                          range: 0...150, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Intake air temperature", displayTitle: "Intake Air Temp", unit: "°F",
                          range: 0...250, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: true),
            PIDDescriptor(id: "Oxygen sensor 1 Bank 1 Short term fuel trim", displayTitle: "O2 B1S1 Trim", unit: "%",
                          range: -100...100, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Oxygen sensor 1 Bank 1 Voltage", displayTitle: "O2 B1S1 Voltage", unit: "V",
                          range: 0...1.2, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Oxygen sensor 2 Bank 1 Voltage", displayTitle: "O2 B1S2 Voltage", unit: "V",
                          range: 0...1.2, warningThreshold: nil, formatStyle: .twoDecimal, isTemperature: false),
            PIDDescriptor(id: "Short term fuel % trim - Bank 1", displayTitle: "Short Term Fuel Trim", unit: "%",
                          range: -25...25, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
            PIDDescriptor(id: "Long term fuel % trim - Bank 1", displayTitle: "Long Term Fuel Trim", unit: "%",
                          range: -25...25, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),

            // Electrical
            PIDDescriptor(id: "OBD Module Voltage", displayTitle: "Battery Voltage", unit: "V",
                          range: 10...16, warningThreshold: nil, formatStyle: .oneDecimal, isTemperature: false),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    /// Sorted list for picker UI.
    static let allDescriptors: [PIDDescriptor] = catalog.values.sorted { $0.displayTitle < $1.displayTitle }
}
