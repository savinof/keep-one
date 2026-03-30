import XCTest
@testable import KeepOne

final class SimilarityServiceTests: XCTestCase {
    func testHashSimilarityIsRelaxedForFaceShotsWithinFifteenMinutes() {
        let lhs = TestFixtures.asset(id: "lhs", secondsSinceReferenceDate: 0)
        let rhs = TestFixtures.asset(id: "rhs", secondsSinceReferenceDate: 600)

        let lhsFeatures = TestFixtures.feature(asset: lhs, hash: 0, faceCount: 1, faceAreaRatio: 0.2)
        let rhsFeatures = TestFixtures.feature(asset: rhs, hash: hash(withBitCount: 22), faceCount: 2, faceAreaRatio: 0.18)
        let config = AnalysisConfiguration.default

        XCTAssertTrue(SimilarityService().areSimilar(lhsFeatures, rhsFeatures, config: config))
    }

    func testHashSimilarityRemainsStrictForFarShotsWithoutFaces() {
        let lhs = TestFixtures.asset(id: "lhs", secondsSinceReferenceDate: 0)
        let rhs = TestFixtures.asset(id: "rhs", secondsSinceReferenceDate: 3_600)

        let lhsFeatures = TestFixtures.feature(asset: lhs, hash: 0, faceCount: 0)
        let rhsFeatures = TestFixtures.feature(asset: rhs, hash: hash(withBitCount: 22), faceCount: 0)
        let config = AnalysisConfiguration.default

        XCTAssertFalse(SimilarityService().areSimilar(lhsFeatures, rhsFeatures, config: config))
    }

    func testVeryLargeHashDistanceStillRejectedEvenWhenClose() {
        let lhs = TestFixtures.asset(id: "lhs", secondsSinceReferenceDate: 0)
        let rhs = TestFixtures.asset(id: "rhs", secondsSinceReferenceDate: 45)

        let lhsFeatures = TestFixtures.feature(asset: lhs, hash: 0, faceCount: 1, faceAreaRatio: 0.2)
        let rhsFeatures = TestFixtures.feature(asset: rhs, hash: hash(withBitCount: 40), faceCount: 1, faceAreaRatio: 0.2)
        let config = AnalysisConfiguration.default

        XCTAssertFalse(SimilarityService().areSimilar(lhsFeatures, rhsFeatures, config: config))
    }

    private func hash(withBitCount bitCount: Int) -> UInt64 {
        guard bitCount > 0 else { return 0 }
        var value: UInt64 = 0
        for bit in 0 ..< min(bitCount, 64) {
            value |= (1 << UInt64(bit))
        }
        return value
    }
}
