import SwiftUI

struct GaugePickerView: View {
    var gaugeConfigStore: GaugeConfigStore
    @Environment(\.dismiss) private var dismiss

    private var existingPIDs: Set<String> {
        Set(gaugeConfigStore.configs.map(\.pidName))
    }

    private var grouped: [(category: PIDCategory, descriptors: [PIDDescriptor])] {
        let byCategory = Dictionary(grouping: PIDDescriptor.allDescriptors) {
            PIDCategory.category(for: $0.id)
        }
        return PIDCategory.allCases.compactMap { cat in
            guard let descs = byCategory[cat], !descs.isEmpty else { return nil }
            return (category: cat, descriptors: descs)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category.rawValue) {
                        ForEach(group.descriptors) { descriptor in
                            Button {
                                gaugeConfigStore.addGauge(from: descriptor)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(descriptor.displayTitle)
                                            .font(.body)
                                        Text(descriptor.id)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if existingPIDs.contains(descriptor.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    Text(descriptor.unit)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Gauge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
