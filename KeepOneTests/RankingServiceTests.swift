import Photos
import XCTest
@testable import KeepOne

final class RankingServiceTests: XCTestCase {
    func testRankingPrefersSharperPhotoWithFaces() {
        let best = TestFixtures.asset(id: "best", secondsSinceReferenceDate: 0, pixelWidth: 2000, pixelHeight: 1500)
        let medium = TestFixtures.asset(id: "medium", secondsSinceReferenceDate: 1, pixelWidth: 1800, pixelHeight: 1200)
        let low = TestFixtures.asset(id: "low", secondsSinceReferenceDate: 2, pixelWidth: 1600, pixelHeight: 1200)

        let features = [
            best.localIdentifier: TestFixtures.feature(asset: best, sharpness: 0.9, faceCount: 2, faceAreaRatio: 0.3),
            medium.localIdentifier: TestFixtures.feature(asset: medium, sharpness: 0.5, faceCount: 1, faceAreaRatio: 0.1),
            low.localIdentifier: TestFixtures.feature(asset: low, sharpness: 0.2, faceCount: 0, faceAreaRatio: 0)
        ]

        let ranked = RankingService().rank(assets: [best, medium, low], featuresByAssetID: features)

        XCTAssertEqual(ranked.first?.asset.localIdentifier, "best")
        XCTAssertEqual(ranked.last?.asset.localIdentifier, "low")
    }

    func testRankingAppliesPenaltyToScreenshots() {
        let screenshot = TestFixtures.asset(
            id: "screenshot",
            secondsSinceReferenceDate: 0,
            mediaSubtypesRawValue: PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let normal = TestFixtures.asset(id: "normal", secondsSinceReferenceDate: 1)

        let features = [
            screenshot.localIdentifier: TestFixtures.feature(asset: screenshot, sharpness: 0.5),
            normal.localIdentifier: TestFixtures.feature(asset: normal, sharpness: 0.5)
        ]

        let ranked = RankingService().rank(assets: [screenshot, normal], featuresByAssetID: features)
        XCTAssertEqual(ranked.first?.asset.localIdentifier, "normal")
        XCTAssertEqual(ranked.last?.asset.localIdentifier, "screenshot")
    }
}
