import Foundation
import Observation
import SwiftUI

/// User's configuration for a single gauge on the dashboard.
struct GaugeConfig: Codable, Identifiable {
    var id: UUID
    var pidName: String
    var displayTitle: String
    var unit: String
    var rangeLower: Double
    var rangeUpper: Double
    var warningThreshold: Double?
    var formatStyle: GaugeFormatStyle
    var isWide: Bool

    var range: ClosedRange<Double> { rangeLower...rangeUpper }

    /// Create from a PIDDescriptor with its defaults.
    init(from descriptor: PIDDescriptor, wide: Bool = false) {
        self.id = UUID()
        self.pidName = descriptor.id
        self.displayTitle = descriptor.displayTitle
        self.unit = descriptor.unit
        self.rangeLower = descriptor.range.lowerBound
        self.rangeUpper = descriptor.range.upperBound
        self.warningThreshold = descriptor.warningThreshold
        self.formatStyle = descriptor.formatStyle
        self.isWide = wide
    }
}

/// Persists the dashboard gauge layout as a JSON array in UserDefaults.
@MainActor
@Observable
final class GaugeConfigStore {

    var configs: [GaugeConfig] {
        didSet { save() }
    }

    private static let key = "dashboard_gauge_configs"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([GaugeConfig].self, from: data) {
            configs = decoded
        } else {
            configs = Self.defaultConfigs
        }
    }

    func addGauge(from descriptor: PIDDescriptor) {
        configs.append(GaugeConfig(from: descriptor))
    }

    func removeGauge(at offsets: IndexSet) {
        configs.remove(atOffsets: offsets)
    }

    func moveGauge(from source: IndexSet, to destination: Int) {
        configs.move(fromOffsets: source, toOffset: destination)
    }

    func toggleSize(for id: UUID) {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[index].isWide.toggle()
    }

    func resetToDefaults() {
        configs = Self.defaultConfigs
    }

    private func save() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static var defaultConfigs: [GaugeConfig] {
        let pids = ["Engine RPM", "Vehicle speed", "Throttle position", "Engine coolant temperature"]
        return pids.compactMap { pidName in
            guard let desc = PIDDescriptor.catalog[pidName] else { return nil }
            return GaugeConfig(from: desc)
        }
    }
}
