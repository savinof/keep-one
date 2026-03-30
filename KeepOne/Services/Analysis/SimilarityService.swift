import Foundation

protocol SimilarityServiceProtocol {
    func areSimilar(
        _ lhs: AssetAnalysisFeatures,
        _ rhs: AssetAnalysisFeatures,
        config: AnalysisConfiguration
    ) -> Bool
}

final class SimilarityService: SimilarityServiceProtocol {
    func areSimilar(
        _ lhs: AssetAnalysisFeatures,
        _ rhs: AssetAnalysisFeatures,
        config: AnalysisConfiguration
    ) -> Bool {
        let timeGap = Self.captureGapSeconds(lhs.asset, rhs.asset)
        let bothHaveFaces = lhs.faceCount > 0 && rhs.faceCount > 0
        let faceCountDelta = abs(lhs.faceCount - rhs.faceCount)

        if let lhsPrint = lhs.visionFeaturePrint, let rhsPrint = rhs.visionFeaturePrint {
            var rawDistance: Float = 0
            if (try? lhsPrint.computeDistance(&rawDistance, to: rhsPrint)) != nil {
                let adjustedVisionThreshold = Self.adjustedVisionThreshold(
                    base: config.visionDistanceThreshold,
                    captureGapSeconds: timeGap,
                    bothHaveFaces: bothHaveFaces
                )
                if rawDistance <= adjustedVisionThreshold {
                    return true
                }
            }
        }

        let xor = lhs.perceptualHash ^ rhs.perceptualHash
        let normalizedDistance = Double(xor.nonzeroBitCount) / 64.0
        if normalizedDistance <= config.hashDistanceThreshold {
            return true
        }

        let adjustedHashThreshold = Self.adjustedHashThreshold(
            base: config.hashDistanceThreshold,
            captureGapSeconds: timeGap,
            bothHaveFaces: bothHaveFaces,
            faceCountDelta: faceCountDelta
        )

        guard normalizedDistance <= adjustedHashThreshold else {
            return false
        }

        if bothHaveFaces {
            return true
        }

        if timeGap <= 180 {
            return true
        }

        if timeGap <= 900 {
            return normalizedDistance <= min(0.40, config.hashDistanceThreshold + 0.12)
        }

        return false
    }

    private static func captureGapSeconds(_ lhs: PhotoAssetRef, _ rhs: PhotoAssetRef) -> TimeInterval {
        guard let lhsDate = lhs.creationDate, let rhsDate = rhs.creationDate else {
            return .greatestFiniteMagnitude
        }
        return abs(lhsDate.timeIntervalSince(rhsDate))
    }

    private static func adjustedVisionThreshold(
        base: Float,
        captureGapSeconds: TimeInterval,
        bothHaveFaces: Bool
    ) -> Float {
        var threshold = base
        if captureGapSeconds <= 120 {
            threshold += 3
        } else if captureGapSeconds <= 300 {
            threshold += 2
        } else if captureGapSeconds <= 900 {
            threshold += 1
        }
        if bothHaveFaces {
            threshold += 1
        }
        return min(20, threshold)
    }

    private static func adjustedHashThreshold(
        base: Double,
        captureGapSeconds: TimeInterval,
        bothHaveFaces: Bool,
        faceCountDelta: Int
    ) -> Double {
        var threshold = base

        if captureGapSeconds <= 120 {
            threshold += 0.14
        } else if captureGapSeconds <= 300 {
            threshold += 0.10
        } else if captureGapSeconds <= 900 {
            threshold += 0.06
        }

        if bothHaveFaces {
            threshold += faceCountDelta <= 1 ? 0.08 : 0.05
        }

        return min(0.48, threshold)
    }
}
