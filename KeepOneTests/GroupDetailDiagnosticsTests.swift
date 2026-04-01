import Photos
import XCTest
@testable import KeepOne

@MainActor
final class GroupDetailDiagnosticsTests: XCTestCase {
    func testSimilarityExplanationIncludesTimeHashAndVision() {
        let first = TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0)
        let second = TestFixtures.asset(id: "b", secondsSinceReferenceDate: 8)
        let ranked = [
            RankedPhotoCandidate(asset: first, score: 0.9, reasons: ["it appears sharper"]),
            RankedPhotoCandidate(asset: second, score: 0.8, reasons: ["faces appear clearer"])
        ]
        let diagnostics = GroupSimilarityDiagnostics(
            edgeCount: 1,
            minEdgeGapSeconds: 8,
            maxEdgeGapSeconds: 8,
            averageEdgeGapSeconds: 8,
            minHashDistance: 0.12,
            maxHashDistance: 0.12,
            averageHashDistance: 0.12,
            visionEdgeCount: 1,
            minVisionDistance: 9.4,
            maxVisionDistance: 9.4,
            averageVisionDistance: 9.4
        )
        let group = SimilarPhotoGroup(
            id: "group",
            assets: [first, second],
            representativeAssetID: first.localIdentifier,
            suggestedBestAssetID: first.localIdentifier,
            rankedCandidates: ranked,
            dateRange: .init(start: first.creationDate ?? .distantPast, end: second.creationDate ?? .distantPast),
            similarityDiagnostics: diagnostics,
            rankingDiagnostics: nil
        )

        let viewModel = GroupDetailViewModel(
            group: group,
            photoLibraryService: NoOpPhotoLibraryService()
        )

        XCTAssertTrue(viewModel.hasSimilarityDiagnostics)
        let joined = viewModel.similarityExplanationLines.joined(separator: " ")
        XCTAssertTrue(joined.contains("Capture gap"))
        XCTAssertTrue(joined.contains("Hash distance"))
        XCTAssertTrue(joined.contains("Vision distance"))
    }

    func testRankingExplanationWhenSecondPassChangesWinner() {
        let first = TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0)
        let second = TestFixtures.asset(id: "b", secondsSinceReferenceDate: 8)
        let ranked = [
            RankedPhotoCandidate(asset: second, score: 0.9, reasons: ["faces appear clearer"]),
            RankedPhotoCandidate(asset: first, score: 0.8, reasons: ["it appears sharper"])
        ]
        let ranking = GroupRankingDiagnostics(
            firstPassWinnerAssetID: first.localIdentifier,
            finalWinnerAssetID: second.localIdentifier,
            firstPassTopGap: 0.03,
            secondPassTriggered: true,
            secondPassCandidateCount: 2,
            secondPassExtractionCount: 2,
            winnerChanged: true,
            winnerChangeMargin: 0.11
        )
        let group = SimilarPhotoGroup(
            id: "group",
            assets: [first, second],
            representativeAssetID: second.localIdentifier,
            suggestedBestAssetID: second.localIdentifier,
            rankedCandidates: ranked,
            dateRange: .init(start: first.creationDate ?? .distantPast, end: second.creationDate ?? .distantPast),
            similarityDiagnostics: nil,
            rankingDiagnostics: ranking
        )

        let viewModel = GroupDetailViewModel(
            group: group,
            photoLibraryService: NoOpPhotoLibraryService()
        )

        XCTAssertTrue(viewModel.hasRankingDiagnostics)
        let joined = viewModel.rankingExplanationLines.joined(separator: " ")
        XCTAssertTrue(joined.contains("First-pass top gap"))
        XCTAssertTrue(joined.contains("Second pass re-checked"))
        XCTAssertTrue(joined.contains("Suggestion changed"))
    }
}

private final class NoOpPhotoLibraryService: PhotoLibraryServiceProtocol {
    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
    func fetchAvailableYears() async -> [YearSection] { [] }
    func fetchMonths(in year: Int) async -> [MonthSection] { [] }
    func fetchMonthAssetSnapshot(
        for selection: MonthSelection,
        includeFullContentSignature: Bool
    ) async -> MonthAssetSnapshot {
        MonthAssetSnapshot(
            assetCount: 0,
            oldestAssetID: nil,
            newestAssetID: nil,
            oldestCreationDate: nil,
            newestCreationDate: nil,
            sampledAssetIDs: []
        )
    }
    func fetchImageAssets(for selection: MonthSelection) async -> [PhotoAssetRef] { [] }
    func fetchAsset(localIdentifier: String) -> PHAsset? { nil }
    func deleteAssets(with localIdentifiers: [String]) async throws {}
}
