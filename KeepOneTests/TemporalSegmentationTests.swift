import XCTest
@testable import KeepOne

final class TemporalSegmentationTests: XCTestCase {
    func testTemporalSegmentationBreaksWhenGapExceedsThreshold() {
        let assets = [
            TestFixtures.asset(id: "a1", secondsSinceReferenceDate: 0),
            TestFixtures.asset(id: "a2", secondsSinceReferenceDate: 12),
            TestFixtures.asset(id: "a3", secondsSinceReferenceDate: 44),
            TestFixtures.asset(id: "a4", secondsSinceReferenceDate: 50),
            TestFixtures.asset(id: "a5", secondsSinceReferenceDate: 300)
        ]

        let groupingService = GroupingService()
        let sequences = groupingService.temporalSequences(from: assets, maxGap: 25)

        XCTAssertEqual(sequences.count, 3)
        XCTAssertEqual(sequences[0].assets.map(\.localIdentifier), ["a1", "a2"])
        XCTAssertEqual(sequences[1].assets.map(\.localIdentifier), ["a3", "a4"])
        XCTAssertEqual(sequences[2].assets.map(\.localIdentifier), ["a5"])
    }

    func testTemporalSegmentationKeepsSameBurstTogether() {
        let assets = [
            TestFixtures.asset(id: "b1", secondsSinceReferenceDate: 0, burstIdentifier: "burstA"),
            TestFixtures.asset(id: "b2", secondsSinceReferenceDate: 80, burstIdentifier: "burstA"),
            TestFixtures.asset(id: "b3", secondsSinceReferenceDate: 160, burstIdentifier: "burstB")
        ]

        let groupingService = GroupingService()
        let sequences = groupingService.temporalSequences(from: assets, maxGap: 25)

        XCTAssertEqual(sequences.count, 2)
        XCTAssertEqual(sequences[0].assets.map(\.localIdentifier), ["b1", "b2"])
        XCTAssertEqual(sequences[1].assets.map(\.localIdentifier), ["b3"])
    }
}
