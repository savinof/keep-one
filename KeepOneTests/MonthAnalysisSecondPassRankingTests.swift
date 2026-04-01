import Photos
import XCTest
@testable import KeepOne

final class MonthAnalysisSecondPassRankingTests: XCTestCase {
    func testSecondPassLargeThumbnailCanChangeSuggestedBest() async throws {
        let selection = MonthSelection(year: 2024, month: 3)
        let assetA = TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0)
        let assetB = TestFixtures.asset(id: "b", secondsSinceReferenceDate: 12)
        let snapshot = MonthAssetSnapshot(
            assetCount: 2,
            oldestAssetID: assetA.localIdentifier,
            newestAssetID: assetB.localIdentifier,
            oldestCreationDate: assetA.creationDate,
            newestCreationDate: assetB.creationDate,
            sampledAssetIDs: [assetA.localIdentifier, assetB.localIdentifier]
        )

        let extractor = SizeAwareFeatureExtractionService(
            lowResFeatures: [
                assetA.localIdentifier: TestFixtures.feature(
                    asset: assetA,
                    sharpness: 0.82,
                    faceCount: 1,
                    faceAreaRatio: 0.25,
                    faceCentering: 0.82,
                    eyeOpenness: 0.42,
                    expressionScore: 0.42,
                    luminanceMean: 0.52,
                    luminanceContrast: 0.35,
                    saliencyScore: 0.70
                ),
                assetB.localIdentifier: TestFixtures.feature(
                    asset: assetB,
                    sharpness: 0.82,
                    faceCount: 1,
                    faceAreaRatio: 0.25,
                    faceCentering: 0.82,
                    eyeOpenness: 0.42,
                    expressionScore: 0.42,
                    luminanceMean: 0.32,
                    luminanceContrast: 0.20,
                    saliencyScore: 0.70
                )
            ],
            highResFeatures: [
                assetA.localIdentifier: TestFixtures.feature(
                    asset: assetA,
                    sharpness: 0.70,
                    faceCount: 1,
                    faceAreaRatio: 0.25,
                    faceCentering: 0.82,
                    eyeOpenness: 0.18,
                    expressionScore: 0.18,
                    luminanceMean: 0.50,
                    luminanceContrast: 0.35,
                    saliencyScore: 0.70
                ),
                assetB.localIdentifier: TestFixtures.feature(
                    asset: assetB,
                    sharpness: 0.72,
                    faceCount: 1,
                    faceAreaRatio: 0.25,
                    faceCentering: 0.82,
                    eyeOpenness: 0.95,
                    expressionScore: 0.92,
                    luminanceMean: 0.50,
                    luminanceContrast: 0.35,
                    saliencyScore: 0.70
                )
            ]
        )

        let service = MonthAnalysisService(
            photoLibraryService: StaticPhotoLibraryService(
                assets: [assetA, assetB],
                snapshot: snapshot
            ),
            featureExtractionService: extractor,
            similarityService: AlwaysSimilarService(),
            groupingService: GroupingService(),
            rankingService: RankingService(),
            cache: NoOpAnalysisCache(),
            settingsStore: InMemoryAnalysisSettingsStore()
        )

        let result = try await service.analyze(
            selection: selection,
            forceRecompute: true,
            runMode: .localFirst
        ) { _ in }

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups.first?.suggestedBestAssetID, assetB.localIdentifier)
        let diagnostics = try XCTUnwrap(result.groups.first?.rankingDiagnostics)
        XCTAssertTrue(diagnostics.secondPassTriggered)
        XCTAssertEqual(diagnostics.secondPassCandidateCount, 2)
        XCTAssertEqual(diagnostics.secondPassExtractionCount, 2)
        XCTAssertTrue(diagnostics.winnerChanged)
        XCTAssertEqual(diagnostics.finalWinnerAssetID, assetB.localIdentifier)
        XCTAssertNotEqual(diagnostics.firstPassWinnerAssetID, diagnostics.finalWinnerAssetID)
        XCTAssertNotNil(diagnostics.winnerChangeMargin)
        XCTAssertEqual(extractor.requestedSizes[assetA.localIdentifier], [256, 640])
        XCTAssertEqual(extractor.requestedSizes[assetB.localIdentifier], [256, 640])
    }

    func testSecondPassDoesNotOverrideClearFirstPassWinner() async throws {
        let selection = MonthSelection(year: 2024, month: 3)
        let assetA = TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0)
        let assetB = TestFixtures.asset(id: "b", secondsSinceReferenceDate: 12)
        let snapshot = MonthAssetSnapshot(
            assetCount: 2,
            oldestAssetID: assetA.localIdentifier,
            newestAssetID: assetB.localIdentifier,
            oldestCreationDate: assetA.creationDate,
            newestCreationDate: assetB.creationDate,
            sampledAssetIDs: [assetA.localIdentifier, assetB.localIdentifier]
        )

        let extractor = SizeAwareFeatureExtractionService(
            lowResFeatures: [
                assetA.localIdentifier: TestFixtures.feature(
                    asset: assetA,
                    sharpness: 0.95,
                    faceCount: 1,
                    faceAreaRatio: 0.30,
                    faceCentering: 0.90,
                    eyeOpenness: 0.70,
                    expressionScore: 0.65,
                    luminanceMean: 0.50,
                    luminanceContrast: 0.35,
                    saliencyScore: 0.75
                ),
                assetB.localIdentifier: TestFixtures.feature(
                    asset: assetB,
                    sharpness: 0.72,
                    faceCount: 1,
                    faceAreaRatio: 0.18,
                    faceCentering: 0.50,
                    eyeOpenness: 0.45,
                    expressionScore: 0.40,
                    luminanceMean: 0.50,
                    luminanceContrast: 0.35,
                    saliencyScore: 0.50
                )
            ],
            highResFeatures: [
                assetA.localIdentifier: TestFixtures.feature(
                    asset: assetA,
                    sharpness: 0.70,
                    faceCount: 1,
                    faceAreaRatio: 0.24,
                    faceCentering: 0.82,
                    eyeOpenness: 0.30,
                    expressionScore: 0.30,
                    luminanceMean: 0.50,
                    luminanceContrast: 0.35,
                    saliencyScore: 0.70
                ),
                assetB.localIdentifier: TestFixtures.feature(
                    asset: assetB,
                    sharpness: 0.75,
                    faceCount: 1,
                    faceAreaRatio: 0.24,
                    faceCentering: 0.82,
                    eyeOpenness: 0.92,
                    expressionScore: 0.90,
                    luminanceMean: 0.50,
                    luminanceContrast: 0.35,
                    saliencyScore: 0.70
                )
            ]
        )

        let service = MonthAnalysisService(
            photoLibraryService: StaticPhotoLibraryService(
                assets: [assetA, assetB],
                snapshot: snapshot
            ),
            featureExtractionService: extractor,
            similarityService: AlwaysSimilarService(),
            groupingService: GroupingService(),
            rankingService: RankingService(),
            cache: NoOpAnalysisCache(),
            settingsStore: InMemoryAnalysisSettingsStore()
        )

        let result = try await service.analyze(
            selection: selection,
            forceRecompute: true,
            runMode: .localFirst
        ) { _ in }

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups.first?.suggestedBestAssetID, assetA.localIdentifier)
        let diagnostics = try XCTUnwrap(result.groups.first?.rankingDiagnostics)
        XCTAssertFalse(diagnostics.secondPassTriggered)
        XCTAssertEqual(diagnostics.secondPassCandidateCount, 0)
        XCTAssertEqual(diagnostics.secondPassExtractionCount, 0)
        XCTAssertFalse(diagnostics.winnerChanged)
        XCTAssertEqual(diagnostics.firstPassWinnerAssetID, assetA.localIdentifier)
        XCTAssertEqual(diagnostics.finalWinnerAssetID, assetA.localIdentifier)
        XCTAssertEqual(extractor.requestedSizes[assetA.localIdentifier], [256])
        XCTAssertEqual(extractor.requestedSizes[assetB.localIdentifier], [256])
    }
}

private final class StaticPhotoLibraryService: PhotoLibraryServiceProtocol {
    private let assets: [PhotoAssetRef]
    private let snapshot: MonthAssetSnapshot

    init(assets: [PhotoAssetRef], snapshot: MonthAssetSnapshot) {
        self.assets = assets
        self.snapshot = snapshot
    }

    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
    func fetchAvailableYears() async -> [YearSection] { [] }
    func fetchMonths(in year: Int) async -> [MonthSection] { [] }
    func fetchMonthAssetSnapshot(
        for selection: MonthSelection,
        includeFullContentSignature: Bool
    ) async -> MonthAssetSnapshot { snapshot }
    func fetchImageAssets(for selection: MonthSelection) async -> [PhotoAssetRef] { assets }
    func fetchAsset(localIdentifier: String) -> PHAsset? { nil }
    func deleteAssets(with localIdentifiers: [String]) async throws {}
}

private final class SizeAwareFeatureExtractionService: FeatureExtractionServiceProtocol {
    private let lowResFeatures: [String: AssetAnalysisFeatures]
    private let highResFeatures: [String: AssetAnalysisFeatures]

    private(set) var requestedSizes: [String: [Int]] = [:]

    init(
        lowResFeatures: [String: AssetAnalysisFeatures],
        highResFeatures: [String: AssetAnalysisFeatures]
    ) {
        self.lowResFeatures = lowResFeatures
        self.highResFeatures = highResFeatures
    }

    func extractFeatures(
        for asset: PhotoAssetRef,
        thumbnailSize: Int,
        allowNetworkAccess: Bool
    ) async -> FeatureExtractionOutcome {
        requestedSizes[asset.localIdentifier, default: []].append(thumbnailSize)
        if thumbnailSize <= 256 {
            return FeatureExtractionOutcome(
                features: lowResFeatures[asset.localIdentifier],
                usedDegradedThumbnail: false,
                skipReason: lowResFeatures[asset.localIdentifier] == nil ? .unavailable : nil
            )
        }
        return FeatureExtractionOutcome(
            features: highResFeatures[asset.localIdentifier],
            usedDegradedThumbnail: false,
            skipReason: highResFeatures[asset.localIdentifier] == nil ? .unavailable : nil
        )
    }
}

private final class AlwaysSimilarService: SimilarityServiceProtocol {
    func areSimilar(
        _ lhs: AssetAnalysisFeatures,
        _ rhs: AssetAnalysisFeatures,
        config: AnalysisConfiguration
    ) -> Bool {
        true
    }
}

private final class NoOpAnalysisCache: AnalysisCacheProtocol {
    func load(selection: MonthSelection) -> MonthAnalysisResult? { nil }
    func save(_ result: MonthAnalysisResult) throws {}
    func invalidate(selection: MonthSelection) throws {}
    func hasCachedResult(selection: MonthSelection) -> Bool { false }
}

private final class InMemoryAnalysisSettingsStore: AnalysisSettingsStoreProtocol {
    var filePath: String { "/tmp/in-memory-analysis-settings.json" }
    private var snapshot = AnalysisSettingsSnapshot(
        temporalGapSeconds: AnalysisConfiguration.default.temporalGapThresholdSeconds,
        similarityPreset: AnalysisConfiguration.default.similarityPreset,
        cacheValidationMode: .lightweightSnapshot,
        gapHistory: [],
        presetHistory: [],
        cacheValidationHistory: []
    )

    func load(defaultTemporalGapSeconds: TimeInterval, defaultPreset: SimilarityPreset) -> AnalysisSettingsSnapshot {
        snapshot
    }

    func updateTemporalGap(to newSeconds: TimeInterval, previous fallbackPrevious: TimeInterval) -> AnalysisSettingsSnapshot {
        snapshot.temporalGapSeconds = newSeconds
        return snapshot
    }

    func updateCacheValidationMode(
        to newMode: CacheValidationMode,
        previous fallbackPrevious: CacheValidationMode
    ) -> AnalysisSettingsSnapshot {
        snapshot.cacheValidationMode = newMode
        return snapshot
    }

    func updateSimilarityPreset(
        to newPreset: SimilarityPreset,
        previous fallbackPrevious: SimilarityPreset
    ) -> AnalysisSettingsSnapshot {
        snapshot.similarityPreset = newPreset
        return snapshot
    }
}
