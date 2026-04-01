import Foundation

enum SimilarityPreset: String, CaseIterable, Hashable, Codable, Sendable, Identifiable {
    case strict
    case balanced
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict:
            return "Strict"
        case .balanced:
            return "Balanced"
        case .relaxed:
            return "Relaxed"
        }
    }

    var visionDistanceThreshold: Float {
        switch self {
        case .strict:
            return 11.5
        case .balanced:
            return 13.0
        case .relaxed:
            return 14.5
        }
    }

    var hashDistanceThreshold: Double {
        switch self {
        case .strict:
            return 0.22
        case .balanced:
            return 0.26
        case .relaxed:
            return 0.30
        }
    }
}

enum CacheValidationMode: String, CaseIterable, Hashable, Codable, Sendable, Identifiable {
    case lightweightSnapshot
    case fullMonthSignature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lightweightSnapshot:
            return "Snapshot"
        case .fullMonthSignature:
            return "Full Signature"
        }
    }

    var description: String {
        switch self {
        case .lightweightSnapshot:
            return "Fast cache check using month count, boundaries, and sampled asset IDs."
        case .fullMonthSignature:
            return "Stronger cache check using a hash across all assets in the selected month."
        }
    }
}

struct AnalysisConfiguration: Hashable, Codable, Sendable {
    var similarityPreset: SimilarityPreset
    var temporalGapThresholdSeconds: TimeInterval
    var visionDistanceThreshold: Float
    var hashDistanceThreshold: Double
    var minimumClusterSize: Int
    var thumbnailSizeForAnalysis: Int

    mutating func applySimilarityPreset(_ preset: SimilarityPreset) {
        similarityPreset = preset
        visionDistanceThreshold = preset.visionDistanceThreshold
        hashDistanceThreshold = preset.hashDistanceThreshold
    }

    static let `default` = AnalysisConfiguration(
        similarityPreset: .balanced,
        temporalGapThresholdSeconds: 300,
        visionDistanceThreshold: SimilarityPreset.balanced.visionDistanceThreshold,
        hashDistanceThreshold: SimilarityPreset.balanced.hashDistanceThreshold,
        minimumClusterSize: 2,
        thumbnailSizeForAnalysis: 256
    )
}
