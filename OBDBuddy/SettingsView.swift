import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    var gaugeConfigStore: GaugeConfigStore

    var body: some View {
        Form {
            Section("Units") {
                Picker("Temperature", selection: $settingsStore.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
            }

            Section("Dashboard") {
                Button("Reset Gauges to Default") {
                    gaugeConfigStore.resetToDefaults()
                }
                .foregroundStyle(.red)
            }

            Section("About") {
                LabeledContent("App", value: "OBD2 Gauge")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .navigationTitle("Settings")
    }
}
