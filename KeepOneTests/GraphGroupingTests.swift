import XCTest
@testable import KeepOne

final class GraphGroupingTests: XCTestCase {
    func testConnectedComponentsReturnOnlyLinkedSubgraphs() {
        let assets = [
            TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0),
            TestFixtures.asset(id: "b", secondsSinceReferenceDate: 1),
            TestFixtures.asset(id: "c", secondsSinceReferenceDate: 2),
            TestFixtures.asset(id: "d", secondsSinceReferenceDate: 3)
        ]

        let adjacency: [String: Set<String>] = [
            "a": ["b"],
            "b": ["a", "c"],
            "c": ["b"],
            "d": []
        ]

        let groupingService = GroupingService()
        let components = groupingService.connectedComponents(assets: assets, adjacency: adjacency)
        let sortedIDs = components.map { $0.map(\.localIdentifier).sorted() }.sorted { lhs, rhs in
            lhs.first ?? "" < rhs.first ?? ""
        }

        XCTAssertEqual(sortedIDs.count, 2)
        XCTAssertEqual(sortedIDs[0], ["a", "b", "c"])
        XCTAssertEqual(sortedIDs[1], ["d"])
    }
}
