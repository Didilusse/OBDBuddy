import SwiftUI

struct DriveDetailView: View {
    let session: DriveSession
    var settingsStore: SettingsStore

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Date", value: session.formattedDate)
                LabeledContent("Duration", value: session.formattedDuration)
                LabeledContent("Data Points", value: "\(session.dataPoints.count)")
                LabeledContent("Sensors", value: "\(session.uniquePIDs.count)")
            }

            Section("Peak Values") {
                peakRow(pid: "Engine RPM", label: "Max RPM", units: "rpm")
                peakRow(pid: "Vehicle speed", label: "Max Speed", units: "mph")
                peakRow(pid: "Engine coolant temperature", label: "Max Coolant Temp", units: "°F")
                peakRow(pid: "Throttle position", label: "Max Throttle", units: "%")
            }

            Section("All Recorded Sensors") {
                ForEach(session.uniquePIDs, id: \.self) { pid in
                    NavigationLink(destination: PIDTimelineView(session: session, pid: pid, settingsStore: settingsStore)) {
                        let latest = session.latestValues[pid]
                        HStack {
                            Text(pid)
                                .font(.subheadline)
                            Spacer()
                            if let latest {
                                Text(displayString(latest.value, pid: pid, units: latest.units))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Drive Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func peakRow(pid: String, label: String, units: String) -> some View {
        let points = session.points(for: pid)
        if let maxVal = points.map(\.value).max() {
            let displayVal = displayString(maxVal, pid: pid, units: units)
            let displayUnits = isTemp(pid) ? settingsStore.temperatureUnitSymbol : units
            LabeledContent(label, value: "\(displayVal) \(displayUnits)")
        }
    }

    private func displayString(_ value: Double, pid: String, units: String) -> String {
        let converted = isTemp(pid) ? settingsStore.convertTemperature(value) : value
        if converted == converted.rounded() && abs(converted) < 100_000 {
            return String(format: "%.0f", converted)
        }
        return String(format: "%.1f", converted)
    }

    private func isTemp(_ pid: String) -> Bool {
        PIDDescriptor.catalog[pid]?.isTemperature ?? false
    }
}

/// Shows a timeline of values for a single PID within a drive session.
struct PIDTimelineView: View {
    let session: DriveSession
    let pid: String
    var settingsStore: SettingsStore

    private var isTemp: Bool {
        PIDDescriptor.catalog[pid]?.isTemperature ?? false
    }

    private var points: [DriveDataPoint] {
        session.points(for: pid)
    }

    private func convert(_ value: Double) -> Double {
        isTemp ? settingsStore.convertTemperature(value) : value
    }

    private var displayUnits: String {
        if isTemp { return settingsStore.temperatureUnitSymbol }
        return points.first?.units ?? ""
    }

    private var stats: (min: Double, max: Double, avg: Double)? {
        guard !points.isEmpty else { return nil }
        let values = points.map { convert($0.value) }
        let min = values.min()!
        let max = values.max()!
        let avg = values.reduce(0, +) / Double(values.count)
        return (min, max, avg)
    }

    var body: some View {
        List {
            if let stats {
                Section("Statistics") {
                    LabeledContent("Minimum", value: String(format: "%.1f", stats.min))
                    LabeledContent("Maximum", value: String(format: "%.1f", stats.max))
                    LabeledContent("Average", value: String(format: "%.1f", stats.avg))
                    LabeledContent("Samples", value: "\(points.count)")
                }
            }

            Section("Timeline") {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack {
                        Text(formatElapsed(point.elapsed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Spacer()
                        Text(String(format: "%.1f", convert(point.value)))
                            .font(.body.monospacedDigit())
                        Text(displayUnits)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(pid)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let ms = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, ms)
    }
}
