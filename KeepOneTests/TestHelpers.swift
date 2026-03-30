import Foundation
@testable import KeepOne

enum TestFixtures {
    static func asset(
        id: String,
        secondsSinceReferenceDate: TimeInterval,
        pixelWidth: Int = 1000,
        pixelHeight: Int = 1000,
        mediaSubtypesRawValue: UInt = 0,
        burstIdentifier: String? = nil,
        burstSelectionTypesRawValue: UInt = 0,
        isFavorite: Bool = false
    ) -> PhotoAssetRef {
        PhotoAssetRef(
            localIdentifier: id,
            creationDate: Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            mediaSubtypesRawValue: mediaSubtypesRawValue,
            burstIdentifier: burstIdentifier,
            burstSelectionTypesRawValue: burstSelectionTypesRawValue,
            isFavorite: isFavorite
        )
    }

    static func feature(
        asset: PhotoAssetRef,
        hash: UInt64 = 0,
        sharpness: Double = 0.2,
        faceCount: Int = 0,
        faceAreaRatio: Double = 0
    ) -> AssetAnalysisFeatures {
        AssetAnalysisFeatures(
            asset: asset,
            perceptualHash: hash,
            sharpness: sharpness,
            faceCount: faceCount,
            faceAreaRatio: faceAreaRatio,
            visionFeaturePrint: nil
        )
    }
}
