import Foundation

struct AnalysisConfiguration: Hashable, Codable, Sendable {
    var temporalGapThresholdSeconds: TimeInterval
    var visionDistanceThreshold: Float
    var hashDistanceThreshold: Double
    var minimumClusterSize: Int
    var thumbnailSizeForAnalysis: Int

    static let `default` = AnalysisConfiguration(
        temporalGapThresholdSeconds: 300,
        visionDistanceThreshold: 13,
        hashDistanceThreshold: 0.26,
        minimumClusterSize: 2,
        thumbnailSizeForAnalysis: 256
    )
}
