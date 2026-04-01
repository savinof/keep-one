import XCTest
@testable import KeepOne

final class GraphCoherenceRefinementTests: XCTestCase {
    func testRefinementRemovesWeakBridgeWithoutSupport() {
        let assets = [
            TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0),
            TestFixtures.asset(id: "b", secondsSinceReferenceDate: 10),
            TestFixtures.asset(id: "c", secondsSinceReferenceDate: 80),
            TestFixtures.asset(id: "d", secondsSinceReferenceDate: 90)
        ]

        let adjacency: [String: Set<String>] = [
            "a": ["b"],
            "b": ["a", "c"],
            "c": ["b", "d"],
            "d": ["c"]
        ]

        let metrics: [String: MonthAnalysisService.SimilarEdgeMetrics] = [
            pairKey("a", "b"): .init(timeGapSeconds: 10, hashDistance: 0.08, visionDistance: 8.0),
            pairKey("b", "c"): .init(timeGapSeconds: 70, hashDistance: 0.34, visionDistance: 15.0),
            pairKey("c", "d"): .init(timeGapSeconds: 10, hashDistance: 0.09, visionDistance: 8.5)
        ]

        let refined = MonthAnalysisService.refineAdjacencyByCoherence(
            assets: assets,
            adjacency: adjacency,
            edgeMetricsByPairKey: metrics,
            config: .default
        )

        XCTAssertEqual(refined["b"], ["a"])
        XCTAssertEqual(refined["c"], ["d"])
    }

    func testRefinementKeepsWeakEdgeWhenTriangleSupportExists() {
        let assets = [
            TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0),
            TestFixtures.asset(id: "b", secondsSinceReferenceDate: 10),
            TestFixtures.asset(id: "c", secondsSinceReferenceDate: 20)
        ]

        let adjacency: [String: Set<String>] = [
            "a": ["b", "c"],
            "b": ["a", "c"],
            "c": ["a", "b"]
        ]

        let metrics: [String: MonthAnalysisService.SimilarEdgeMetrics] = [
            pairKey("a", "b"): .init(timeGapSeconds: 10, hashDistance: 0.08, visionDistance: 8.0),
            pairKey("b", "c"): .init(timeGapSeconds: 10, hashDistance: 0.09, visionDistance: 8.2),
            pairKey("a", "c"): .init(timeGapSeconds: 20, hashDistance: 0.36, visionDistance: 15.4)
        ]

        let refined = MonthAnalysisService.refineAdjacencyByCoherence(
            assets: assets,
            adjacency: adjacency,
            edgeMetricsByPairKey: metrics,
            config: .default
        )

        XCTAssertEqual(refined["a"], ["b", "c"])
        XCTAssertEqual(refined["b"], ["a", "c"])
        XCTAssertEqual(refined["c"], ["a", "b"])
    }

    func testRefinementKeepsStrongEdgeWithoutTriangleSupport() {
        let assets = [
            TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0),
            TestFixtures.asset(id: "b", secondsSinceReferenceDate: 10),
            TestFixtures.asset(id: "c", secondsSinceReferenceDate: 100),
            TestFixtures.asset(id: "d", secondsSinceReferenceDate: 110)
        ]

        let adjacency: [String: Set<String>] = [
            "a": ["b"],
            "b": ["a", "c"],
            "c": ["b", "d"],
            "d": ["c"]
        ]

        let metrics: [String: MonthAnalysisService.SimilarEdgeMetrics] = [
            pairKey("a", "b"): .init(timeGapSeconds: 10, hashDistance: 0.06, visionDistance: 7.0),
            pairKey("b", "c"): .init(timeGapSeconds: 90, hashDistance: 0.17, visionDistance: 11.0),
            pairKey("c", "d"): .init(timeGapSeconds: 10, hashDistance: 0.05, visionDistance: 7.0)
        ]

        let refined = MonthAnalysisService.refineAdjacencyByCoherence(
            assets: assets,
            adjacency: adjacency,
            edgeMetricsByPairKey: metrics,
            config: .default
        )

        XCTAssertEqual(refined["b"], ["a", "c"])
        XCTAssertEqual(refined["c"], ["b", "d"])
    }

    private func pairKey(_ lhs: String, _ rhs: String) -> String {
        lhs < rhs ? "\(lhs)|\(rhs)" : "\(rhs)|\(lhs)"
    }
}
