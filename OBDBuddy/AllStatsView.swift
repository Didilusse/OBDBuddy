import SwiftUI

/// Groups PIDs into logical categories for the advanced stats view.
enum PIDCategory: String, CaseIterable {
    case engine = "Engine"
    case speed = "Speed & Position"
    case fuel = "Fuel"
    case sensors = "Sensors"
    case electrical = "Electrical"

    static func category(for pid: String) -> PIDCategory {
        switch pid {
        case let p where p.contains("RPM") || p.contains("coolant") || p.contains("Throttle")
            || p.contains("engine load") || p.contains("Timing") || p.contains("boost")
            || p.contains("engine power"):
            return .engine
        case let p where p.contains("speed") || p.contains("Speed") || p.contains("Altitude")
            || p.contains("acceleration") || p.contains("Distance"):
            return .speed
        case let p where p.contains("Fuel") || p.contains("fuel"):
            return .fuel
        case let p where p.contains("Oxygen") || p.contains("MAF") || p.contains("Intake")
            || p.contains("trim"):
            return .sensors
        default:
            return .electrical
        }
    }
}

/// Displays the latest value for one PID.
struct StatRow: View {
    let pid: String
    let value: Double
    let units: String
    var settingsStore: SettingsStore

    private var isTemp: Bool {
        PIDDescriptor.catalog[pid]?.isTemperature ?? false
    }

    private var displayValue: Double {
        isTemp ? settingsStore.convertTemperature(value) : value
    }

    private var displayUnits: String {
        isTemp ? settingsStore.temperatureUnitSymbol : units
    }

    private var formattedValue: String {
        if displayValue == displayValue.rounded() && abs(displayValue) < 100_000 {
            return String(format: "%.0f", displayValue)
        }
        return String(format: "%.2f", displayValue)
    }

    var body: some View {
        HStack {
            Text(pid)
                .font(.subheadline)
            Spacer()
            Text("\(formattedValue) \(displayUnits)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Advanced stats view showing all PIDs from a set of readings, grouped by category.
struct AllStatsView: View {
    let readings: [OBDReading]
    var settingsStore: SettingsStore

    private var latestByPID: [(pid: String, value: Double, units: String)] {
        var latest: [String: OBDReading] = [:]
        for reading in readings {
            latest[reading.pid] = reading
        }
        return latest.values
            .map { (pid: $0.pid, value: $0.value, units: $0.units) }
            .sorted { $0.pid < $1.pid }
    }

    private var grouped: [(category: PIDCategory, stats: [(pid: String, value: Double, units: String)])] {
        let byCategory = Dictionary(grouping: latestByPID) { PIDCategory.category(for: $0.pid) }
        return PIDCategory.allCases.compactMap { cat in
            guard let stats = byCategory[cat], !stats.isEmpty else { return nil }
            return (category: cat, stats: stats)
        }
    }

    var body: some View {
        List {
            if readings.isEmpty {
                ContentUnavailableView {
                    Label("No Data", systemImage: "gauge.with.dots.needle.0percent")
                } description: {
                    Text("Start playback to see all sensor data.")
                }
            } else {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category.rawValue) {
                        ForEach(group.stats, id: \.pid) { stat in
                            StatRow(pid: stat.pid, value: stat.value, units: stat.units, settingsStore: settingsStore)
                        }
                    }
                }
            }
        }
        .navigationTitle("All Stats")
    }
}
