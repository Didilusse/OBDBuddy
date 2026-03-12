import Foundation
import Observation

/// Temperature unit preference.
enum TemperatureUnit: String, Codable, CaseIterable {
    case fahrenheit = "Fahrenheit"
    case celsius = "Celsius"
}

/// App-wide settings backed by UserDefaults.
@MainActor
@Observable
final class SettingsStore {

    var temperatureUnit: TemperatureUnit {
        didSet {
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: "temperature_unit")
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "temperature_unit"),
           let unit = TemperatureUnit(rawValue: raw) {
            temperatureUnit = unit
        } else {
            temperatureUnit = .fahrenheit
        }
    }

    /// Convert a Fahrenheit value to the user's preferred unit.
    func convertTemperature(_ fahrenheit: Double) -> Double {
        switch temperatureUnit {
        case .fahrenheit:
            return fahrenheit
        case .celsius:
            return (fahrenheit - 32.0) * 5.0 / 9.0
        }
    }

    /// The unit string for the current temperature preference.
    var temperatureUnitSymbol: String {
        switch temperatureUnit {
        case .fahrenheit: return "°F"
        case .celsius: return "°C"
        }
    }

    /// Convert a temperature range from F to the preferred unit.
    func convertTemperatureRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        switch temperatureUnit {
        case .fahrenheit:
            return range
        case .celsius:
            let lower = (range.lowerBound - 32.0) * 5.0 / 9.0
            let upper = (range.upperBound - 32.0) * 5.0 / 9.0
            return lower...upper
        }
    }

    /// Convert a warning threshold from F to the preferred unit.
    func convertTemperatureThreshold(_ threshold: Double?) -> Double? {
        guard let t = threshold else { return nil }
        return convertTemperature(t)
    }
}
