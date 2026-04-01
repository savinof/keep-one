import Foundation
import Photos

protocol RankingServiceProtocol {
    func rank(
        assets: [PhotoAssetRef],
        featuresByAssetID: [String: AssetAnalysisFeatures]
    ) -> [RankedPhotoCandidate]
}

final class RankingService: RankingServiceProtocol {
    private enum Weights {
        static let sharpness = 0.24
        static let faceClarity = 0.30
        static let eyeOpenness = 0.16
        static let expression = 0.10
        static let composition = 0.08
        static let exposure = 0.07
        static let resolution = 0.07
        static let favorite = 0.03
        static let burstAutoPick = 0.05
        static let screenshotPenalty = -0.55
    }

    func rank(
        assets: [PhotoAssetRef],
        featuresByAssetID: [String: AssetAnalysisFeatures]
    ) -> [RankedPhotoCandidate] {
        guard !assets.isEmpty else { return [] }

        let sharpnessValues = assets.compactMap { featuresByAssetID[$0.localIdentifier]?.sharpness }
        let faceValues = assets.map {
            let feature = featuresByAssetID[$0.localIdentifier]
            return Self.faceClarityRawSignal(feature)
        }
        let eyeValues = assets.map {
            featuresByAssetID[$0.localIdentifier]?.eyeOpenness ?? 0
        }
        let expressionValues = assets.map {
            featuresByAssetID[$0.localIdentifier]?.expressionScore ?? 0
        }
        let compositionValues = assets.map {
            let feature = featuresByAssetID[$0.localIdentifier]
            return Self.compositionRawSignal(feature)
        }
        let exposureValues = assets.map {
            let feature = featuresByAssetID[$0.localIdentifier]
            return Self.exposureRawSignal(feature)
        }
        let resolutionValues = assets.map { log(Double(max(1, $0.pixelCount))) }

        let sharpnessRange = Self.range(for: sharpnessValues)
        let faceRange = Self.range(for: faceValues)
        let eyeRange = Self.range(for: eyeValues)
        let expressionRange = Self.range(for: expressionValues)
        let compositionRange = Self.range(for: compositionValues)
        let exposureRange = Self.range(for: exposureValues)
        let resolutionRange = Self.range(for: resolutionValues)

        let candidates = assets.map { asset in
            let feature = featuresByAssetID[asset.localIdentifier]

            let sharpnessSignal = Self.normalize(feature?.sharpness ?? 0.2, in: sharpnessRange)
            let faceSignalRaw = Self.faceClarityRawSignal(feature)
            let faceSignal = Self.normalize(faceSignalRaw, in: faceRange)
            let eyeSignal = Self.normalize(feature?.eyeOpenness ?? 0, in: eyeRange)
            let expressionSignal = Self.normalize(feature?.expressionScore ?? 0, in: expressionRange)
            let compositionSignalRaw = Self.compositionRawSignal(feature)
            let compositionSignal = Self.normalize(compositionSignalRaw, in: compositionRange)
            let exposureSignalRaw = Self.exposureRawSignal(feature)
            let exposureSignal = Self.normalize(exposureSignalRaw, in: exposureRange)
            let resolutionSignal = Self.normalize(log(Double(max(1, asset.pixelCount))), in: resolutionRange)

            var contributions: [(reason: String, value: Double)] = []
            contributions.append(("faces appear clearer", Weights.faceClarity * faceSignal))
            contributions.append(("eyes appear more open", Weights.eyeOpenness * eyeSignal))
            contributions.append(("expression looks better", Weights.expression * expressionSignal))
            contributions.append(("it appears sharper", Weights.sharpness * sharpnessSignal))
            contributions.append(("the subject stands out better", Weights.composition * compositionSignal))
            contributions.append(("lighting looks more balanced", Weights.exposure * exposureSignal))
            contributions.append(("it has slightly higher resolution", Weights.resolution * resolutionSignal))

            if asset.isFavorite {
                contributions.append(("it is already marked as a favorite", Weights.favorite))
            }

            if (asset.burstSelectionTypesRawValue & PHAssetBurstSelectionType.autoPick.rawValue) != 0 {
                contributions.append(("it was marked as a burst auto-pick", Weights.burstAutoPick))
            }

            if (asset.mediaSubtypesRawValue & PHAssetMediaSubtype.photoScreenshot.rawValue) != 0 {
                contributions.append(("it looks like a screenshot, so it gets a utility penalty", Weights.screenshotPenalty))
            }

            let score = contributions.reduce(0) { $0 + $1.value }
            let topReasons = contributions
                .filter { $0.value > 0.015 }
                .sorted { $0.value > $1.value }
                .prefix(2)
                .map(\.reason)

            return RankedPhotoCandidate(
                asset: asset,
                score: score,
                reasons: topReasons.isEmpty ? ["conservative fallback score"] : topReasons
            )
        }

        return candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.asset.creationDate ?? .distantPast < rhs.asset.creationDate ?? .distantPast
            }
            return lhs.score > rhs.score
        }
    }

    private static func range(for values: [Double]) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0 ... 1
        }
        if abs(maxValue - minValue) < 0.000001 {
            return minValue ... (minValue + 1)
        }
        return minValue ... maxValue
    }

    private static func normalize(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let width = range.upperBound - range.lowerBound
        guard width > 0 else { return 0 }
        let normalized = (value - range.lowerBound) / width
        return min(1, max(0, normalized))
    }

    private static func faceClarityRawSignal(_ feature: AssetAnalysisFeatures?) -> Double {
        guard let feature else { return 0 }
        return (Double(feature.faceCount) * 0.45) + (feature.faceAreaRatio * 1.0) + (feature.faceCentering * 0.35)
    }

    private static func compositionRawSignal(_ feature: AssetAnalysisFeatures?) -> Double {
        guard let feature else { return 0 }
        return max(feature.faceCentering, feature.saliencyScore)
    }

    private static func exposureRawSignal(_ feature: AssetAnalysisFeatures?) -> Double {
        guard let feature else { return 0 }
        let mean = feature.luminanceMean
        let midpointDistance = abs(mean - 0.52)
        let balance = max(0, 1 - min(1, midpointDistance / 0.52))
        return (balance * 0.65) + (feature.luminanceContrast * 0.35)
    }
}
