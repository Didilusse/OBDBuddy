import Foundation
import Observation

/// A single recorded data point during a drive.
struct DriveDataPoint: Codable {
    let elapsed: TimeInterval
    let pid: String
    let value: Double
    let units: String
}

/// A recorded driving session with all OBD-II data captured.
struct DriveSession: Codable, Identifiable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var dataPoints: [DriveDataPoint]

    var duration: TimeInterval {
        (endDate ?? Date()).timeIntervalSince(startDate)
    }

    var formattedDate: String {
        startDate.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Get the most recent value for each unique PID.
    var latestValues: [String: (value: Double, units: String)] {
        var result: [String: (Double, String)] = [:]
        for point in dataPoints {
            result[point.pid] = (point.value, point.units)
        }
        return result
    }

    /// Get all data points for a specific PID, sorted by time.
    func points(for pid: String) -> [DriveDataPoint] {
        dataPoints.filter { $0.pid == pid }
    }

    /// All unique PIDs recorded in this session.
    var uniquePIDs: [String] {
        Array(Set(dataPoints.map(\.pid))).sorted()
    }
}

/// Persists drive sessions to disk as JSON files in the app's documents directory.
@MainActor
@Observable
final class DriveStore {

    var sessions: [DriveSession] = []

    private let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("Drives", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAll()
    }

    func save(_ session: DriveSession) {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: url)
        }

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    func delete(_ session: DriveSession) {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        sessions.removeAll { $0.id == session.id }
    }

    private func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DriveSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(DriveSession.self, from: data)
            }
            .sorted { $0.startDate > $1.startDate }
    }
}
