import SwiftUI

struct DriveHistoryView: View {
    @Bindable var driveStore: DriveStore
    var settingsStore: SettingsStore

    var body: some View {
        List {
            if driveStore.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Drives", systemImage: "car")
                } description: {
                    Text("Recorded drives will appear here. Connect to a scanner in live mode and tap Record to start.")
                }
            } else {
                ForEach(driveStore.sessions) { session in
                    NavigationLink(destination: DriveDetailView(session: session, settingsStore: settingsStore)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.formattedDate)
                                .font(.headline)
                            HStack(spacing: 16) {
                                Label(session.formattedDuration, systemImage: "clock")
                                Label("\(session.dataPoints.count) readings", systemImage: "chart.bar")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        driveStore.delete(driveStore.sessions[index])
                    }
                }
            }
        }
        .navigationTitle("Drive History")
    }
}
