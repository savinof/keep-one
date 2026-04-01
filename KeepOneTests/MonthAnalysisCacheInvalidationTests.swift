import Photos
import XCTest
@testable import KeepOne

final class MonthAnalysisCacheInvalidationTests: XCTestCase {
    func testAnalyzeUsesCacheWhenSnapshotAndConfigMatch() async throws {
        let selection = MonthSelection(year: 2024, month: 3)
        let snapshot = MonthAssetSnapshot(
            assetCount: 2,
            oldestAssetID: "a",
            newestAssetID: "b",
            oldestCreationDate: Date(timeIntervalSinceReferenceDate: 0),
            newestCreationDate: Date(timeIntervalSinceReferenceDate: 20),
            sampledAssetIDs: ["a", "b"]
        )
        let cached = MonthAnalysisResult(
            selection: selection,
            generatedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            assetCountAnalyzed: 2,
            groups: [],
            librarySnapshot: snapshot,
            config: .default,
            diagnostics: AnalysisDiagnostics(
                sequenceCount: 1,
                featureExtractionCount: 2,
                similarityEdgeCount: 1,
                groupCount: 1
            )
        )

        let photoLibrary = MockPhotoLibraryService(snapshot: snapshot, assets: [])
        let cache = MockAnalysisCache(cachedResult: cached)
        let service = makeService(photoLibrary: photoLibrary, cache: cache)

        let result = try await service.analyze(
            selection: selection,
            forceRecompute: false,
            runMode: .localFirst
        ) { _ in }

        XCTAssertEqual(result.generatedAt, cached.generatedAt)
        XCTAssertEqual(photoLibrary.fetchImageAssetsCallCount, 0)
        XCTAssertEqual(cache.saveCallCount, 0)
    }

    func testAnalyzeRecomputesWhenSnapshotChanged() async throws {
        let selection = MonthSelection(year: 2024, month: 3)
        let staleSnapshot = MonthAssetSnapshot(
            assetCount: 1,
            oldestAssetID: "old",
            newestAssetID: "old",
            oldestCreationDate: Date(timeIntervalSinceReferenceDate: 0),
            newestCreationDate: Date(timeIntervalSinceReferenceDate: 0),
            sampledAssetIDs: ["old"]
        )
        let currentSnapshot = MonthAssetSnapshot(
            assetCount: 1,
            oldestAssetID: "new",
            newestAssetID: "new",
            oldestCreationDate: Date(timeIntervalSinceReferenceDate: 10),
            newestCreationDate: Date(timeIntervalSinceReferenceDate: 10),
            sampledAssetIDs: ["new"]
        )

        let cached = MonthAnalysisResult(
            selection: selection,
            generatedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            assetCountAnalyzed: 1,
            groups: [],
            librarySnapshot: staleSnapshot,
            config: .default,
            diagnostics: AnalysisDiagnostics(
                sequenceCount: 0,
                featureExtractionCount: 0,
                similarityEdgeCount: 0,
                groupCount: 0
            )
        )

        let assets = [TestFixtures.asset(id: "new", secondsSinceReferenceDate: 10)]
        let photoLibrary = MockPhotoLibraryService(snapshot: currentSnapshot, assets: assets)
        let cache = MockAnalysisCache(cachedResult: cached)
        let service = makeService(photoLibrary: photoLibrary, cache: cache)

        let result = try await service.analyze(
            selection: selection,
            forceRecompute: false,
            runMode: .localFirst
        ) { _ in }

        XCTAssertEqual(photoLibrary.fetchImageAssetsCallCount, 1)
        XCTAssertEqual(result.assetCountAnalyzed, 1)
        XCTAssertEqual(result.librarySnapshot, currentSnapshot)
        XCTAssertEqual(cache.saveCallCount, 1)
    }

    func testAnalyzeRecomputesWhenFullSignatureModeSeesLegacySnapshotWithoutSignature() async throws {
        let selection = MonthSelection(year: 2024, month: 3)
        let legacySnapshot = MonthAssetSnapshot(
            assetCount: 2,
            oldestAssetID: "a",
            newestAssetID: "b",
            oldestCreationDate: Date(timeIntervalSinceReferenceDate: 0),
            newestCreationDate: Date(timeIntervalSinceReferenceDate: 20),
            sampledAssetIDs: ["a", "b"],
            fullContentSignature: nil
        )
        let currentSnapshot = MonthAssetSnapshot(
            assetCount: 2,
            oldestAssetID: "a",
            newestAssetID: "b",
            oldestCreationDate: Date(timeIntervalSinceReferenceDate: 0),
            newestCreationDate: Date(timeIntervalSinceReferenceDate: 20),
            sampledAssetIDs: ["a", "b"],
            fullContentSignature: "signature-v1"
        )
        let cached = MonthAnalysisResult(
            selection: selection,
            generatedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            assetCountAnalyzed: 2,
            groups: [],
            librarySnapshot: legacySnapshot,
            config: .default,
            diagnostics: AnalysisDiagnostics(
                sequenceCount: 0,
                featureExtractionCount: 0,
                similarityEdgeCount: 0,
                groupCount: 0
            ),
            cacheValidationMode: .fullMonthSignature
        )
        let assets = [TestFixtures.asset(id: "a", secondsSinceReferenceDate: 0)]
        let photoLibrary = MockPhotoLibraryService(snapshot: currentSnapshot, assets: assets)
        let cache = MockAnalysisCache(cachedResult: cached)
        let settings = InMemorySettingsStore(cacheValidationMode: .fullMonthSignature)
        let service = makeService(photoLibrary: photoLibrary, cache: cache, settingsStore: settings)

        let result = try await service.analyze(
            selection: selection,
            forceRecompute: false,
            runMode: .localFirst
        ) { _ in }

        XCTAssertEqual(photoLibrary.fetchImageAssetsCallCount, 1)
        XCTAssertEqual(cache.saveCallCount, 1)
        XCTAssertEqual(result.librarySnapshot?.fullContentSignature, "signature-v1")
        XCTAssertEqual(result.cacheValidationMode, .fullMonthSignature)
    }

    func testAnalyzeUsesCacheWhenFullSignatureMatches() async throws {
        let selection = MonthSelection(year: 2024, month: 3)
        let snapshot = MonthAssetSnapshot(
            assetCount: 2,
            oldestAssetID: "a",
            newestAssetID: "b",
            oldestCreationDate: Date(timeIntervalSinceReferenceDate: 0),
            newestCreationDate: Date(timeIntervalSinceReferenceDate: 20),
            sampledAssetIDs: ["a", "b"],
            fullContentSignature: "signature-v1"
        )
        let cached = MonthAnalysisResult(
            selection: selection,
            generatedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            assetCountAnalyzed: 2,
            groups: [],
            librarySnapshot: snapshot,
            config: .default,
            diagnostics: AnalysisDiagnostics(
                sequenceCount: 0,
                featureExtractionCount: 0,
                similarityEdgeCount: 0,
                groupCount: 0
            ),
            cacheValidationMode: .fullMonthSignature
        )

        let photoLibrary = MockPhotoLibraryService(snapshot: snapshot, assets: [])
        let cache = MockAnalysisCache(cachedResult: cached)
        let settings = InMemorySettingsStore(cacheValidationMode: .fullMonthSignature)
        let service = makeService(photoLibrary: photoLibrary, cache: cache, settingsStore: settings)

        let result = try await service.analyze(
            selection: selection,
            forceRecompute: false,
            runMode: .localFirst
        ) { _ in }

        XCTAssertEqual(result.generatedAt, cached.generatedAt)
        XCTAssertEqual(photoLibrary.fetchImageAssetsCallCount, 0)
        XCTAssertEqual(cache.saveCallCount, 0)
    }

    private func makeService(
        photoLibrary: MockPhotoLibraryService,
        cache: MockAnalysisCache,
        settingsStore: InMemorySettingsStore = InMemorySettingsStore()
    ) -> MonthAnalysisService {
        MonthAnalysisService(
            photoLibraryService: photoLibrary,
            featureExtractionService: NoOpFeatureExtractionService(),
            similarityService: NoOpSimilarityService(),
            groupingService: GroupingService(),
            rankingService: RankingService(),
            cache: cache,
            settingsStore: settingsStore
        )
    }
}

private final class MockPhotoLibraryService: PhotoLibraryServiceProtocol {
    private let snapshot: MonthAssetSnapshot
    private let assets: [PhotoAssetRef]
    private(set) var fetchImageAssetsCallCount = 0

    init(snapshot: MonthAssetSnapshot, assets: [PhotoAssetRef]) {
        self.snapshot = snapshot
        self.assets = assets
    }

    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
    func fetchAvailableYears() async -> [YearSection] { [] }
    func fetchMonths(in year: Int) async -> [MonthSection] { [] }
    func fetchMonthAssetSnapshot(
        for selection: MonthSelection,
        includeFullContentSignature: Bool
    ) async -> MonthAssetSnapshot {
        snapshot
    }

    func fetchImageAssets(for selection: MonthSelection) async -> [PhotoAssetRef] {
        fetchImageAssetsCallCount += 1
        return assets
    }

    func fetchAsset(localIdentifier: String) -> PHAsset? { nil }
    func deleteAssets(with localIdentifiers: [String]) async throws {}
}

private final class MockAnalysisCache: AnalysisCacheProtocol {
    private let cachedResult: MonthAnalysisResult?
    private(set) var saveCallCount = 0

    init(cachedResult: MonthAnalysisResult?) {
        self.cachedResult = cachedResult
    }

    func load(selection: MonthSelection) -> MonthAnalysisResult? { cachedResult }

    func save(_ result: MonthAnalysisResult) throws {
        saveCallCount += 1
    }

    func invalidate(selection: MonthSelection) throws {}
    func hasCachedResult(selection: MonthSelection) -> Bool { cachedResult != nil }
}

private final class NoOpFeatureExtractionService: FeatureExtractionServiceProtocol {
    func extractFeatures(
        for asset: PhotoAssetRef,
        thumbnailSize: Int,
        allowNetworkAccess: Bool
    ) async -> FeatureExtractionOutcome {
        FeatureExtractionOutcome(
            features: nil,
            usedDegradedThumbnail: false,
            skipReason: .unavailable
        )
    }
}

private final class NoOpSimilarityService: SimilarityServiceProtocol {
    func areSimilar(
        _ lhs: AssetAnalysisFeatures,
        _ rhs: AssetAnalysisFeatures,
        config: AnalysisConfiguration
    ) -> Bool {
        false
    }
}

private final class InMemorySettingsStore: AnalysisSettingsStoreProtocol {
    var filePath: String { "/tmp/in-memory-analysis-settings.json" }
    private var snapshot: AnalysisSettingsSnapshot

    init(cacheValidationMode: CacheValidationMode = .lightweightSnapshot) {
        snapshot = AnalysisSettingsSnapshot(
            temporalGapSeconds: AnalysisConfiguration.default.temporalGapThresholdSeconds,
            similarityPreset: AnalysisConfiguration.default.similarityPreset,
            cacheValidationMode: cacheValidationMode,
            gapHistory: [],
            presetHistory: [],
            cacheValidationHistory: []
        )
    }

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
