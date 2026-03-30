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
        static let sharpness = 0.40
        static let faceClarity = 0.30
        static let resolution = 0.20
        static let favorite = 0.05
        static let burstAutoPick = 0.10
        static let screenshotPenalty = -0.50
    }

    func rank(
        assets: [PhotoAssetRef],
        featuresByAssetID: [String: AssetAnalysisFeatures]
    ) -> [RankedPhotoCandidate] {
        guard !assets.isEmpty else { return [] }

        let sharpnessValues = assets.compactMap { featuresByAssetID[$0.localIdentifier]?.sharpness }
        let faceValues = assets.map {
            let feature = featuresByAssetID[$0.localIdentifier]
            return (Double(feature?.faceCount ?? 0) * 0.5) + (feature?.faceAreaRatio ?? 0)
        }
        let resolutionValues = assets.map { log(Double(max(1, $0.pixelCount))) }

        let sharpnessRange = Self.range(for: sharpnessValues)
        let faceRange = Self.range(for: faceValues)
        let resolutionRange = Self.range(for: resolutionValues)

        let candidates = assets.map { asset in
            let feature = featuresByAssetID[asset.localIdentifier]

            let sharpnessSignal = Self.normalize(feature?.sharpness ?? 0.2, in: sharpnessRange)
            let faceSignalRaw = (Double(feature?.faceCount ?? 0) * 0.5) + (feature?.faceAreaRatio ?? 0)
            let faceSignal = Self.normalize(faceSignalRaw, in: faceRange)
            let resolutionSignal = Self.normalize(log(Double(max(1, asset.pixelCount))), in: resolutionRange)

            var contributions: [(reason: String, value: Double)] = []
            contributions.append(("it appears sharper", Weights.sharpness * sharpnessSignal))
            contributions.append(("visual details are clearer around faces", Weights.faceClarity * faceSignal))
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
                .filter { $0.value > 0.01 }
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
}
