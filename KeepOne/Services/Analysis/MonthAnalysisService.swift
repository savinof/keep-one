import CryptoKit
import Foundation

protocol MonthAnalysisServiceProtocol {
    func analyze(
        selection: MonthSelection,
        forceRecompute: Bool,
        progress: @escaping (AnalysisProgress) -> Void
    ) async throws -> MonthAnalysisResult
    func currentTemporalGapSeconds() async -> TimeInterval
    func updateTemporalGapSeconds(_ seconds: TimeInterval) async
    func settingsFilePath() async -> String
}

actor MonthAnalysisService: MonthAnalysisServiceProtocol {
    private static let maxPairwiseEdgeGapSeconds: TimeInterval = 180

    private let photoLibraryService: any PhotoLibraryServiceProtocol
    private let featureExtractionService: any FeatureExtractionServiceProtocol
    private let similarityService: any SimilarityServiceProtocol
    private let groupingService: any GroupingServiceProtocol
    private let rankingService: any RankingServiceProtocol
    private let cache: any AnalysisCacheProtocol
    private let settingsStore: any AnalysisSettingsStoreProtocol
    private var configuration: AnalysisConfiguration

    init(
        photoLibraryService: any PhotoLibraryServiceProtocol,
        featureExtractionService: any FeatureExtractionServiceProtocol,
        similarityService: any SimilarityServiceProtocol,
        groupingService: any GroupingServiceProtocol,
        rankingService: any RankingServiceProtocol,
        cache: any AnalysisCacheProtocol,
        configuration: AnalysisConfiguration = .default,
        settingsStore: any AnalysisSettingsStoreProtocol = AnalysisSettingsStore()
    ) {
        self.photoLibraryService = photoLibraryService
        self.featureExtractionService = featureExtractionService
        self.similarityService = similarityService
        self.groupingService = groupingService
        self.rankingService = rankingService
        self.cache = cache
        self.settingsStore = settingsStore

        let persisted = settingsStore.load(defaultTemporalGapSeconds: configuration.temporalGapThresholdSeconds)
        var normalizedConfiguration = configuration
        normalizedConfiguration.temporalGapThresholdSeconds = Self.clampTemporalGap(persisted.temporalGapSeconds)
        self.configuration = normalizedConfiguration
    }

    func currentTemporalGapSeconds() async -> TimeInterval {
        configuration.temporalGapThresholdSeconds
    }

    func updateTemporalGapSeconds(_ seconds: TimeInterval) async {
        let normalized = Self.clampTemporalGap(seconds)
        let previous = configuration.temporalGapThresholdSeconds
        guard abs(previous - normalized) > 0.0001 else { return }

        configuration.temporalGapThresholdSeconds = normalized
        _ = settingsStore.updateTemporalGap(to: normalized, previous: previous)
    }

    func settingsFilePath() async -> String {
        settingsStore.filePath
    }

    func analyze(
        selection: MonthSelection,
        forceRecompute: Bool,
        progress: @escaping (AnalysisProgress) -> Void
    ) async throws -> MonthAnalysisResult {
        if !forceRecompute, let cached = cache.load(selection: selection) {
            if cached.config == configuration {
                progress(AnalysisProgress(stage: "Loaded cached analysis", completedUnits: 1, totalUnits: 1))
                return cached
            }

            progress(
                AnalysisProgress(
                    stage: "Settings changed, recomputing analysis",
                    completedUnits: 0,
                    totalUnits: 1
                )
            )
        }

        progress(AnalysisProgress(stage: "Fetching month photos", completedUnits: 0, totalUnits: 1))
        let assets = await photoLibraryService.fetchImageAssets(for: selection)

        if assets.count < configuration.minimumClusterSize {
            let result = MonthAnalysisResult(
                selection: selection,
                generatedAt: Date(),
                assetCountAnalyzed: assets.count,
                groups: [],
                config: configuration,
                diagnostics: AnalysisDiagnostics(
                    sequenceCount: 0,
                    featureExtractionCount: 0,
                    similarityEdgeCount: 0,
                    groupCount: 0
                )
            )
            try? cache.save(result)
            progress(AnalysisProgress(stage: "No similar groups found", completedUnits: 1, totalUnits: 1))
            return result
        }

        let sequences = groupingService.temporalSequences(
            from: assets,
            maxGap: configuration.temporalGapThresholdSeconds
        )

        var groups: [SimilarPhotoGroup] = []
        var totalFeaturesExtracted = 0
        var totalSimilarityEdges = 0
        for (sequenceIndex, sequence) in sequences.enumerated() {
            progress(
                AnalysisProgress(
                    stage: "Analyzing sequence \(sequenceIndex + 1) of \(sequences.count)",
                    completedUnits: sequenceIndex,
                    totalUnits: sequences.count
                )
            )

            guard sequence.assets.count >= configuration.minimumClusterSize else { continue }

            var featuresByAssetID: [String: AssetAnalysisFeatures] = [:]
            for asset in sequence.assets {
                if let features = await featureExtractionService.extractFeatures(
                    for: asset,
                    thumbnailSize: configuration.thumbnailSizeForAnalysis
                ) {
                    featuresByAssetID[asset.localIdentifier] = features
                }
            }
            totalFeaturesExtracted += featuresByAssetID.count

            let adjacency = groupingService.buildAdjacency(assets: sequence.assets) { lhs, rhs in
                if !Self.withinPairwiseEdgeWindow(lhs: lhs, rhs: rhs) {
                    return false
                }
                guard
                    let lhsFeatures = featuresByAssetID[lhs.localIdentifier],
                    let rhsFeatures = featuresByAssetID[rhs.localIdentifier]
                else {
                    return false
                }
                return similarityService.areSimilar(lhsFeatures, rhsFeatures, config: configuration)
            }
            totalSimilarityEdges += Self.edgeCount(adjacency: adjacency)

            let components = groupingService.connectedComponents(assets: sequence.assets, adjacency: adjacency)
            let candidateGroups = components.filter { $0.count >= configuration.minimumClusterSize }

            for component in candidateGroups {
                let ranked = rankingService.rank(assets: component, featuresByAssetID: featuresByAssetID)
                guard let suggested = ranked.first else { continue }
                let representativeID = suggested.asset.localIdentifier
                let dateRange = Self.dateRange(for: component)
                let id = Self.stableGroupID(selection: selection, assets: component)

                groups.append(
                    SimilarPhotoGroup(
                        id: id,
                        assets: component.sorted {
                            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
                        },
                        representativeAssetID: representativeID,
                        suggestedBestAssetID: suggested.asset.localIdentifier,
                        rankedCandidates: ranked,
                        dateRange: dateRange
                    )
                )
            }
        }

        let sortedGroups = groups.sorted { lhs, rhs in
            let lhsDate = lhs.dateRange?.start ?? .distantPast
            let rhsDate = rhs.dateRange?.start ?? .distantPast
            return lhsDate > rhsDate
        }

        let result = MonthAnalysisResult(
            selection: selection,
            generatedAt: Date(),
            assetCountAnalyzed: assets.count,
            groups: sortedGroups,
            config: configuration,
            diagnostics: AnalysisDiagnostics(
                sequenceCount: sequences.count,
                featureExtractionCount: totalFeaturesExtracted,
                similarityEdgeCount: totalSimilarityEdges,
                groupCount: sortedGroups.count
            )
        )
        try? cache.save(result)

        print(
            "[KeepOneAnalysis] month=\(selection.id) assets=\(assets.count) sequences=\(sequences.count) " +
                "features=\(totalFeaturesExtracted) edges=\(totalSimilarityEdges) groups=\(sortedGroups.count)"
        )

        progress(
            AnalysisProgress(
                stage: "Analysis complete",
                completedUnits: sequences.count,
                totalUnits: sequences.count
            )
        )
        return result
    }

    private static func dateRange(for assets: [PhotoAssetRef]) -> SimilarPhotoGroup.DateRange? {
        let dates = assets.compactMap(\.creationDate)
        guard let start = dates.min(), let end = dates.max() else { return nil }
        return SimilarPhotoGroup.DateRange(start: start, end: end)
    }

    private static func stableGroupID(selection: MonthSelection, assets: [PhotoAssetRef]) -> String {
        let joined = ([selection.id] + assets.map(\.localIdentifier).sorted()).joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func edgeCount(adjacency: [String: Set<String>]) -> Int {
        adjacency.values.reduce(0) { $0 + $1.count } / 2
    }

    private static func clampTemporalGap(_ seconds: TimeInterval) -> TimeInterval {
        min(900, max(10, seconds))
    }

    private static func withinPairwiseEdgeWindow(lhs: PhotoAssetRef, rhs: PhotoAssetRef) -> Bool {
        if let lhsBurst = lhs.burstIdentifier, let rhsBurst = rhs.burstIdentifier, lhsBurst == rhsBurst {
            return true
        }
        guard let lhsDate = lhs.creationDate, let rhsDate = rhs.creationDate else {
            return false
        }
        return abs(lhsDate.timeIntervalSince(rhsDate)) <= maxPairwiseEdgeGapSeconds
    }
}
