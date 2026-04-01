import Foundation

struct TemporalGapChange: Hashable, Codable, Sendable {
    let changedAt: Date
    let previousSeconds: TimeInterval
    let newSeconds: TimeInterval
}

struct SimilarityPresetChange: Hashable, Codable, Sendable {
    let changedAt: Date
    let previousPreset: SimilarityPreset
    let newPreset: SimilarityPreset
}

struct CacheValidationModeChange: Hashable, Codable, Sendable {
    let changedAt: Date
    let previousMode: CacheValidationMode
    let newMode: CacheValidationMode
}

struct AnalysisSettingsSnapshot: Hashable, Codable, Sendable {
    var temporalGapSeconds: TimeInterval
    var similarityPreset: SimilarityPreset
    var cacheValidationMode: CacheValidationMode
    var gapHistory: [TemporalGapChange]
    var presetHistory: [SimilarityPresetChange]
    var cacheValidationHistory: [CacheValidationModeChange]

    private enum CodingKeys: String, CodingKey {
        case temporalGapSeconds
        case similarityPreset
        case cacheValidationMode
        case gapHistory
        case presetHistory
        case cacheValidationHistory
    }

    init(
        temporalGapSeconds: TimeInterval,
        similarityPreset: SimilarityPreset,
        cacheValidationMode: CacheValidationMode,
        gapHistory: [TemporalGapChange],
        presetHistory: [SimilarityPresetChange],
        cacheValidationHistory: [CacheValidationModeChange]
    ) {
        self.temporalGapSeconds = temporalGapSeconds
        self.similarityPreset = similarityPreset
        self.cacheValidationMode = cacheValidationMode
        self.gapHistory = gapHistory
        self.presetHistory = presetHistory
        self.cacheValidationHistory = cacheValidationHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temporalGapSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .temporalGapSeconds)
            ?? AnalysisConfiguration.default.temporalGapThresholdSeconds
        similarityPreset = try container.decodeIfPresent(SimilarityPreset.self, forKey: .similarityPreset)
            ?? .balanced
        cacheValidationMode = try container.decodeIfPresent(CacheValidationMode.self, forKey: .cacheValidationMode)
            ?? .lightweightSnapshot
        gapHistory = try container.decodeIfPresent([TemporalGapChange].self, forKey: .gapHistory) ?? []
        presetHistory = try container.decodeIfPresent([SimilarityPresetChange].self, forKey: .presetHistory) ?? []
        cacheValidationHistory = try container.decodeIfPresent([CacheValidationModeChange].self, forKey: .cacheValidationHistory)
            ?? []
    }
}

protocol AnalysisSettingsStoreProtocol {
    var filePath: String { get }
    func load(defaultTemporalGapSeconds: TimeInterval, defaultPreset: SimilarityPreset) -> AnalysisSettingsSnapshot
    func updateTemporalGap(to newSeconds: TimeInterval, previous fallbackPrevious: TimeInterval) -> AnalysisSettingsSnapshot
    func updateCacheValidationMode(
        to newMode: CacheValidationMode,
        previous fallbackPrevious: CacheValidationMode
    ) -> AnalysisSettingsSnapshot
    func updateSimilarityPreset(
        to newPreset: SimilarityPreset,
        previous fallbackPrevious: SimilarityPreset
    ) -> AnalysisSettingsSnapshot
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

    func load(defaultTemporalGapSeconds: TimeInterval, defaultPreset: SimilarityPreset) -> AnalysisSettingsSnapshot {
        if let existing = read() {
            return existing
        }

        let initial = AnalysisSettingsSnapshot(
            temporalGapSeconds: defaultTemporalGapSeconds,
            similarityPreset: defaultPreset,
            cacheValidationMode: .lightweightSnapshot,
            gapHistory: [],
            presetHistory: [],
            cacheValidationHistory: []
        )
        write(initial)
        return initial
    }

    func updateTemporalGap(to newSeconds: TimeInterval, previous fallbackPrevious: TimeInterval) -> AnalysisSettingsSnapshot {
        var snapshot = load(defaultTemporalGapSeconds: fallbackPrevious, defaultPreset: .balanced)
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

    func updateCacheValidationMode(
        to newMode: CacheValidationMode,
        previous fallbackPrevious: CacheValidationMode
    ) -> AnalysisSettingsSnapshot {
        _ = fallbackPrevious
        var snapshot = load(
            defaultTemporalGapSeconds: AnalysisConfiguration.default.temporalGapThresholdSeconds,
            defaultPreset: .balanced
        )
        let previousMode = snapshot.cacheValidationMode
        guard previousMode != newMode else {
            return snapshot
        }

        let change = CacheValidationModeChange(
            changedAt: Date(),
            previousMode: previousMode,
            newMode: newMode
        )

        snapshot.cacheValidationMode = newMode
        snapshot.cacheValidationHistory.append(change)
        if snapshot.cacheValidationHistory.count > 200 {
            snapshot.cacheValidationHistory = Array(snapshot.cacheValidationHistory.suffix(200))
        }
        write(snapshot)
        return snapshot
    }

    func updateSimilarityPreset(
        to newPreset: SimilarityPreset,
        previous fallbackPrevious: SimilarityPreset
    ) -> AnalysisSettingsSnapshot {
        var snapshot = load(
            defaultTemporalGapSeconds: AnalysisConfiguration.default.temporalGapThresholdSeconds,
            defaultPreset: fallbackPrevious
        )
        guard snapshot.similarityPreset != newPreset else {
            return snapshot
        }

        let change = SimilarityPresetChange(
            changedAt: Date(),
            previousPreset: snapshot.similarityPreset,
            newPreset: newPreset
        )

        snapshot.similarityPreset = newPreset
        snapshot.presetHistory.append(change)
        if snapshot.presetHistory.count > 200 {
            snapshot.presetHistory = Array(snapshot.presetHistory.suffix(200))
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
