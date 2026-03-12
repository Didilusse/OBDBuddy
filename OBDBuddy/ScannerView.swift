import SwiftUI

struct ScannerView: View {
    @Bindable var bleManager: BLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                connectionStatusSection
                discoveredDevicesSection
            }
            .navigationTitle("Connect Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    scanButton
                }
            }
            .alert("Bluetooth Error", isPresented: showingError, actions: {
                Button("OK") { bleManager.errorMessage = nil }
            }, message: {
                Text(bleManager.errorMessage ?? "")
            })
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var connectionStatusSection: some View {
        Section {
            switch bleManager.connectionState {
            case .disconnected:
                Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(.secondary)
            case .scanning:
                Label {
                    Text("Scanning…")
                } icon: {
                    ProgressView()
                }
            case .connecting:
                Label {
                    Text("Connecting…")
                } icon: {
                    ProgressView()
                }
            case .discoveringServices:
                Label {
                    Text("Discovering services…")
                } icon: {
                    ProgressView()
                }
            case .ready:
                Label(
                    bleManager.connectedPeripheralName ?? "Connected",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)

                Button("Disconnect", role: .destructive) {
                    bleManager.disconnect()
                }
            }
        } header: {
            Text("Status")
        }
    }

    @ViewBuilder
    private var discoveredDevicesSection: some View {
        if bleManager.connectionState != .ready {
            Section {
                if bleManager.discoveredPeripherals.isEmpty && bleManager.connectionState == .scanning {
                    ContentUnavailableView {
                        Label("Scanning", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Looking for OBD-II adapters nearby…")
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(bleManager.discoveredPeripherals) { peripheral in
                    Button {
                        bleManager.connect(to: peripheral)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peripheral.name)
                                    .font(.body)
                                Text("RSSI: \(peripheral.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(bleManager.connectionState == .connecting)
                }
            } header: {
                Text("Devices")
            }
        }
    }

    // MARK: - Scan Button

    @ViewBuilder
    private var scanButton: some View {
        switch bleManager.connectionState {
        case .scanning:
            Button("Stop") { bleManager.stopScan() }
        case .disconnected:
            Button("Scan") { bleManager.startScan() }
        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var showingError: Binding<Bool> {
        Binding(
            get: { bleManager.errorMessage != nil },
            set: { if !$0 { bleManager.errorMessage = nil } }
        )
    }
}

#Preview {
    ScannerView(bleManager: BLEManager())
}
