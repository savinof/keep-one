import XCTest
@testable import KeepOne

final class GroupCardRankingSummaryTests: XCTestCase {
    func testRankingSummaryIsNilWithoutDiagnostics() {
        XCTAssertNil(GroupCardView.rankingSummary(for: nil))
    }

    func testRankingSummaryForClearFirstPassWinner() {
        let summary = GroupCardView.rankingSummary(for: makeDiagnostics(
            secondPassTriggered: false,
            secondPassExtractionCount: 0,
            winnerChanged: false
        ))

        XCTAssertEqual(summary?.iconName, "checkmark.seal")
        XCTAssertEqual(summary?.text, "Clear first-pass winner")
    }

    func testRankingSummaryForLimitedSecondPassData() {
        let summary = GroupCardView.rankingSummary(for: makeDiagnostics(
            secondPassTriggered: true,
            secondPassExtractionCount: 1,
            winnerChanged: false
        ))

        XCTAssertEqual(summary?.iconName, "exclamationmark.triangle")
        XCTAssertEqual(summary?.text, "Second pass had limited data")
    }

    func testRankingSummaryForChangedWinner() {
        let summary = GroupCardView.rankingSummary(for: makeDiagnostics(
            secondPassTriggered: true,
            secondPassExtractionCount: 2,
            winnerChanged: true
        ))

        XCTAssertEqual(summary?.iconName, "arrow.triangle.2.circlepath")
        XCTAssertEqual(summary?.text, "Refined on larger preview")
    }

    func testRankingSummaryForConfirmedWinner() {
        let summary = GroupCardView.rankingSummary(for: makeDiagnostics(
            secondPassTriggered: true,
            secondPassExtractionCount: 2,
            winnerChanged: false
        ))

        XCTAssertEqual(summary?.iconName, "checkmark.circle")
        XCTAssertEqual(summary?.text, "Confirmed on larger preview")
    }

    private func makeDiagnostics(
        secondPassTriggered: Bool,
        secondPassExtractionCount: Int,
        winnerChanged: Bool
    ) -> GroupRankingDiagnostics {
        GroupRankingDiagnostics(
            firstPassWinnerAssetID: "a",
            finalWinnerAssetID: winnerChanged ? "b" : "a",
            firstPassTopGap: 0.02,
            secondPassTriggered: secondPassTriggered,
            secondPassCandidateCount: 3,
            secondPassExtractionCount: secondPassExtractionCount,
            winnerChanged: winnerChanged,
            winnerChangeMargin: winnerChanged ? 0.10 : nil
        )
    }
}
