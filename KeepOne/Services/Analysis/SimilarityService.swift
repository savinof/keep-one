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
        let faceAreaDelta = abs(lhs.faceAreaRatio - rhs.faceAreaRatio)
        let likelySameSubject = Self.isLikelySameSubject(
            bothHaveFaces: bothHaveFaces,
            faceCountDelta: faceCountDelta,
            faceAreaDelta: faceAreaDelta
        )

        var visionDistance: Float?
        if let lhsPrint = lhs.visionFeaturePrint, let rhsPrint = rhs.visionFeaturePrint {
            var rawDistance: Float = 0
            if (try? lhsPrint.computeDistance(&rawDistance, to: rhsPrint)) != nil {
                visionDistance = rawDistance
                let adjustedVisionThreshold = Self.adjustedVisionThreshold(
                    base: config.visionDistanceThreshold,
                    captureGapSeconds: timeGap,
                    bothHaveFaces: bothHaveFaces,
                    faceCountDelta: faceCountDelta,
                    faceAreaDelta: faceAreaDelta
                )
                if rawDistance <= adjustedVisionThreshold {
                    return true
                }

                if likelySameSubject, timeGap <= 900 {
                    let relaxedVisionThreshold = min(22.5, adjustedVisionThreshold + 1.5)
                    if rawDistance <= relaxedVisionThreshold {
                        return true
                    }
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
            faceCountDelta: faceCountDelta,
            faceAreaDelta: faceAreaDelta
        )
        if normalizedDistance <= adjustedHashThreshold {
            return true
        }

        let hasSingleFaceSide = (lhs.faceCount > 0) != (rhs.faceCount > 0)
        if hasSingleFaceSide {
            guard timeGap <= 180 else { return false }
            let strictHashCap = min(0.28, config.hashDistanceThreshold + 0.04)
            let strictVisionCap = config.visionDistanceThreshold - 0.5
            if let visionDistance {
                return visionDistance <= strictVisionCap && normalizedDistance <= strictHashCap
            }
            return normalizedDistance <= strictHashCap
        }

        if !bothHaveFaces {
            guard timeGap <= 240 else { return false }
            if let visionDistance {
                let strictVisionCap = min(15.5, config.visionDistanceThreshold + 0.8)
                let strictHashCap = min(0.30, config.hashDistanceThreshold + 0.04)
                return visionDistance <= strictVisionCap && normalizedDistance <= strictHashCap
            }

            if timeGap <= 120 {
                return normalizedDistance <= min(0.24, config.hashDistanceThreshold)
            }
            return normalizedDistance <= min(0.22, config.hashDistanceThreshold - 0.02)
        }

        if likelySameSubject {
            if timeGap <= 120, normalizedDistance <= 0.58 {
                return true
            }
            if timeGap <= 300, normalizedDistance <= 0.54 {
                return true
            }
            if timeGap <= 900, normalizedDistance <= 0.49 {
                return true
            }
        }

        if timeGap <= 180, normalizedDistance <= min(0.44, config.hashDistanceThreshold + 0.12) {
            return true
        }

        if timeGap <= 900 {
            return normalizedDistance <= min(0.38, config.hashDistanceThreshold + 0.08)
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
        bothHaveFaces: Bool,
        faceCountDelta: Int,
        faceAreaDelta: Double
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
        if bothHaveFaces, faceCountDelta <= 1, faceAreaDelta <= 0.22 {
            threshold += 1.0
        }
        return min(21, threshold)
    }

    private static func adjustedHashThreshold(
        base: Double,
        captureGapSeconds: TimeInterval,
        bothHaveFaces: Bool,
        faceCountDelta: Int,
        faceAreaDelta: Double
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
            threshold += faceCountDelta <= 1 ? 0.07 : 0.04
        }

        if bothHaveFaces, faceCountDelta <= 1, faceAreaDelta <= 0.22 {
            threshold += 0.05
        }

        return min(0.52, threshold)
    }

    private static func isLikelySameSubject(
        bothHaveFaces: Bool,
        faceCountDelta: Int,
        faceAreaDelta: Double
    ) -> Bool {
        bothHaveFaces && faceCountDelta <= 1 && faceAreaDelta <= 0.22
    }
}
