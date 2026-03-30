import Foundation

struct TemporalGapChange: Hashable, Codable, Sendable {
    let changedAt: Date
    let previousSeconds: TimeInterval
    let newSeconds: TimeInterval
}

struct AnalysisSettingsSnapshot: Hashable, Codable, Sendable {
    var temporalGapSeconds: TimeInterval
    var gapHistory: [TemporalGapChange]
}

protocol AnalysisSettingsStoreProtocol {
    var filePath: String { get }
    func load(defaultTemporalGapSeconds: TimeInterval) -> AnalysisSettingsSnapshot
    func updateTemporalGap(to newSeconds: TimeInterval, previous fallbackPrevious: TimeInterval) -> AnalysisSettingsSnapshot
}

final class AnalysisSettingsStore: AnalysisSettingsStoreProtocol {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    var filePath: String { fileURL.path }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let appSupportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupportBase.appendingPathComponent("KeepOne", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        fileURL = directory.appendingPathComponent("analysis-settings.json", isDirectory: false)
    }

    func load(defaultTemporalGapSeconds: TimeInterval) -> AnalysisSettingsSnapshot {
        if let existing = read() {
            return existing
        }

        let initial = AnalysisSettingsSnapshot(
            temporalGapSeconds: defaultTemporalGapSeconds,
            gapHistory: []
        )
        write(initial)
        return initial
    }

    func updateTemporalGap(to newSeconds: TimeInterval, previous fallbackPrevious: TimeInterval) -> AnalysisSettingsSnapshot {
        var snapshot = load(defaultTemporalGapSeconds: fallbackPrevious)
        guard abs(snapshot.temporalGapSeconds - newSeconds) > 0.0001 else {
            return snapshot
        }

        let change = TemporalGapChange(
            changedAt: Date(),
            previousSeconds: snapshot.temporalGapSeconds,
            newSeconds: newSeconds
        )

        snapshot.temporalGapSeconds = newSeconds
        snapshot.gapHistory.append(change)
        if snapshot.gapHistory.count > 200 {
            snapshot.gapHistory = Array(snapshot.gapHistory.suffix(200))
        }
        write(snapshot)
        return snapshot
    }

    private func read() -> AnalysisSettingsSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AnalysisSettingsSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    private func write(_ snapshot: AnalysisSettingsSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort persistence for MVP.
        }
    }
}
