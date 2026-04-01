import CryptoKit
import Foundation

protocol MonthAnalysisServiceProtocol {
    func analyze(
        selection: MonthSelection,
        forceRecompute: Bool,
        runMode: AnalysisRunMode,
        progress: @escaping (AnalysisProgress) -> Void
    ) async throws -> MonthAnalysisResult
    func currentTemporalGapSeconds() async -> TimeInterval
    func currentSimilarityPreset() async -> SimilarityPreset
    func currentCacheValidationMode() async -> CacheValidationMode
    func updateTemporalGapSeconds(_ seconds: TimeInterval) async
    func updateSimilarityPreset(_ preset: SimilarityPreset) async
    func updateCacheValidationMode(_ mode: CacheValidationMode) async
    func settingsFilePath() async -> String
}

actor MonthAnalysisService: MonthAnalysisServiceProtocol {
    private static let maxPairwiseEdgeGapSeconds: TimeInterval = 180
    private static let secondPassTopCandidateCount = 3
    private static let secondPassThumbnailSize = 640
    private static let secondPassTieBreakGapThreshold = 0.08
    private static let secondPassWinnerOverrideMargin = 0.06

    struct SimilarEdgeMetrics: Sendable {
        let timeGapSeconds: TimeInterval
        let hashDistance: Double
        let visionDistance: Float?
    }

    private struct RefinedRankingResult: Sendable {
        let rankedCandidates: [RankedPhotoCandidate]
        let diagnostics: GroupRankingDiagnostics?
    }

    private let photoLibraryService: any PhotoLibraryServiceProtocol
    private let featureExtractionService: any FeatureExtractionServiceProtocol
    private let similarityService: any SimilarityServiceProtocol
    private let groupingService: any GroupingServiceProtocol
    private let rankingService: any RankingServiceProtocol
    private let cache: any AnalysisCacheProtocol
    private let settingsStore: any AnalysisSettingsStoreProtocol
    private var configuration: AnalysisConfiguration
    private var cacheValidationMode: CacheValidationMode

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

        let persisted = settingsStore.load(
            defaultTemporalGapSeconds: configuration.temporalGapThresholdSeconds,
            defaultPreset: configuration.similarityPreset
        )
        var normalizedConfiguration = configuration
        normalizedConfiguration.temporalGapThresholdSeconds = Self.clampTemporalGap(persisted.temporalGapSeconds)
        normalizedConfiguration.applySimilarityPreset(persisted.similarityPreset)
        self.configuration = normalizedConfiguration
        self.cacheValidationMode = persisted.cacheValidationMode
    }

    func currentTemporalGapSeconds() async -> TimeInterval {
        configuration.temporalGapThresholdSeconds
    }

    func currentSimilarityPreset() async -> SimilarityPreset {
        configuration.similarityPreset
    }

    func currentCacheValidationMode() async -> CacheValidationMode {
        cacheValidationMode
    }

    func updateTemporalGapSeconds(_ seconds: TimeInterval) async {
        let normalized = Self.clampTemporalGap(seconds)
        let previous = configuration.temporalGapThresholdSeconds
        guard abs(previous - normalized) > 0.0001 else { return }

        configuration.temporalGapThresholdSeconds = normalized
        _ = settingsStore.updateTemporalGap(to: normalized, previous: previous)
    }

    func updateSimilarityPreset(_ preset: SimilarityPreset) async {
        let previous = configuration.similarityPreset
        guard previous != preset else { return }

        configuration.applySimilarityPreset(preset)
        _ = settingsStore.updateSimilarityPreset(to: preset, previous: previous)
    }

    func updateCacheValidationMode(_ mode: CacheValidationMode) async {
        let previous = cacheValidationMode
        guard previous != mode else { return }

        cacheValidationMode = mode
        _ = settingsStore.updateCacheValidationMode(to: mode, previous: previous)
    }

    func settingsFilePath() async -> String {
        settingsStore.filePath
    }

    func analyze(
        selection: MonthSelection,
        forceRecompute: Bool,
        runMode: AnalysisRunMode,
        progress: @escaping (AnalysisProgress) -> Void
    ) async throws -> MonthAnalysisResult {
        progress(AnalysisProgress(stage: "Checking month snapshot", completedUnits: 0, totalUnits: 1))
        let currentSnapshot = await photoLibraryService.fetchMonthAssetSnapshot(
            for: selection,
            includeFullContentSignature: cacheValidationMode == .fullMonthSignature
        )

        if !forceRecompute, let cached = cache.load(selection: selection) {
            let sameConfig = cached.config == configuration
            let sameSnapshot = cached.librarySnapshot == currentSnapshot
            let sameValidationMode = (cached.cacheValidationMode ?? .lightweightSnapshot) == cacheValidationMode

            if sameConfig, sameSnapshot, sameValidationMode {
                progress(AnalysisProgress(stage: "Loaded cached analysis", completedUnits: 1, totalUnits: 1))
                return cached
            }

            let stage: String = if !sameConfig {
                "Settings changed, recomputing analysis"
            } else if !sameValidationMode {
                "Cache validation mode changed, recomputing analysis"
            } else {
                "Month changed since cached run, recomputing analysis"
            }
            progress(AnalysisProgress(stage: stage, completedUnits: 0, totalUnits: 1))
        }

        progress(AnalysisProgress(stage: "Fetching month photos", completedUnits: 0, totalUnits: 1))
        let assets = await photoLibraryService.fetchImageAssets(for: selection)

        if assets.count < configuration.minimumClusterSize {
            let result = MonthAnalysisResult(
                selection: selection,
                generatedAt: Date(),
                assetCountAnalyzed: assets.count,
                groups: [],
                librarySnapshot: currentSnapshot,
                config: configuration,
                diagnostics: AnalysisDiagnostics(
                    sequenceCount: 0,
                    featureExtractionCount: 0,
                    similarityEdgeCount: 0,
                    groupCount: 0
                ),
                runMode: runMode,
                assetAvailabilityDiagnostics: AssetAvailabilityDiagnostics(
                    processedFeatureCount: 0,
                    degradedThumbnailCount: 0,
                    skippedNoLocalThumbnailCount: 0
                ),
                cacheValidationMode: cacheValidationMode
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
        var degradedThumbnailCount = 0
        var skippedNoLocalThumbnailCount = 0
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
                let extraction = await featureExtractionService.extractFeatures(
                    for: asset,
                    thumbnailSize: configuration.thumbnailSizeForAnalysis,
                    allowNetworkAccess: runMode.allowsNetworkAccess
                )

                if let features = extraction.features {
                    featuresByAssetID[asset.localIdentifier] = features
                    if extraction.usedDegradedThumbnail {
                        degradedThumbnailCount += 1
                    }
                } else if extraction.skipReason == .noLocalThumbnail {
                    skippedNoLocalThumbnailCount += 1
                }
            }
            totalFeaturesExtracted += featuresByAssetID.count

            var similarEdgeMetricsByPairKey: [String: SimilarEdgeMetrics] = [:]
            let rawAdjacency = groupingService.buildAdjacency(assets: sequence.assets) { lhs, rhs in
                if !Self.withinPairwiseEdgeWindow(lhs: lhs, rhs: rhs) {
                    return false
                }
                guard
                    let lhsFeatures = featuresByAssetID[lhs.localIdentifier],
                    let rhsFeatures = featuresByAssetID[rhs.localIdentifier]
                else {
                    return false
                }
                let metrics = Self.computeEdgeMetrics(lhsFeatures, rhsFeatures)
                let isSimilar = similarityService.areSimilar(lhsFeatures, rhsFeatures, config: configuration)
                if isSimilar {
                    let pairKey = Self.pairKey(lhs.localIdentifier, rhs.localIdentifier)
                    similarEdgeMetricsByPairKey[pairKey] = metrics
                }
                return isSimilar
            }
            let adjacency = Self.refineAdjacencyByCoherence(
                assets: sequence.assets,
                adjacency: rawAdjacency,
                edgeMetricsByPairKey: similarEdgeMetricsByPairKey,
                config: configuration
            )
            totalSimilarityEdges += Self.edgeCount(adjacency: adjacency)

            let components = groupingService.connectedComponents(assets: sequence.assets, adjacency: adjacency)
            let candidateGroups = components.filter { $0.count >= configuration.minimumClusterSize }

            for component in candidateGroups {
                let initialRanked = rankingService.rank(assets: component, featuresByAssetID: featuresByAssetID)
                let refinedRanking = await refineRankingWithSecondPass(
                    ranked: initialRanked,
                    featuresByAssetID: featuresByAssetID,
                    runMode: runMode
                )
                let ranked = refinedRanking.rankedCandidates
                guard let suggested = ranked.first else { continue }
                let representativeID = suggested.asset.localIdentifier
                let dateRange = Self.dateRange(for: component)
                let similarityDiagnostics = Self.groupSimilarityDiagnostics(
                    for: component,
                    adjacency: adjacency,
                    edgeMetricsByPairKey: similarEdgeMetricsByPairKey
                )
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
                        dateRange: dateRange,
                        similarityDiagnostics: similarityDiagnostics,
                        rankingDiagnostics: refinedRanking.diagnostics
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
            librarySnapshot: currentSnapshot,
            config: configuration,
            diagnostics: AnalysisDiagnostics(
                sequenceCount: sequences.count,
                featureExtractionCount: totalFeaturesExtracted,
                similarityEdgeCount: totalSimilarityEdges,
                groupCount: sortedGroups.count
            ),
            runMode: runMode,
            assetAvailabilityDiagnostics: AssetAvailabilityDiagnostics(
                processedFeatureCount: totalFeaturesExtracted,
                degradedThumbnailCount: degradedThumbnailCount,
                skippedNoLocalThumbnailCount: skippedNoLocalThumbnailCount
            ),
            cacheValidationMode: cacheValidationMode
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

    private func refineRankingWithSecondPass(
        ranked: [RankedPhotoCandidate],
        featuresByAssetID: [String: AssetAnalysisFeatures],
        runMode: AnalysisRunMode
    ) async -> RefinedRankingResult {
        guard let firstPassWinner = ranked.first else {
            return RefinedRankingResult(rankedCandidates: ranked, diagnostics: nil)
        }

        let firstPassWinnerID = firstPassWinner.asset.localIdentifier
        let firstPassTopGap: Double? = if ranked.count >= 2 {
            ranked[0].score - ranked[1].score
        } else {
            nil
        }

        var finalRanking = ranked
        var secondPassTriggered = false
        var secondPassCandidateCount = 0
        var secondPassExtractionCount = 0
        var winnerChangeMargin: Double?

        if let firstPassTopGap, ranked.count >= 2, firstPassTopGap < Self.secondPassTieBreakGapThreshold {
            secondPassTriggered = true
            let topCount = min(Self.secondPassTopCandidateCount, ranked.count)
            secondPassCandidateCount = topCount
            let topAssets = Array(ranked.prefix(topCount)).map(\.asset)

            var mergedFeatures = featuresByAssetID
            for asset in topAssets {
                let extraction = await featureExtractionService.extractFeatures(
                    for: asset,
                    thumbnailSize: max(Self.secondPassThumbnailSize, configuration.thumbnailSizeForAnalysis),
                    allowNetworkAccess: runMode.allowsNetworkAccess
                )

                if let refined = extraction.features {
                    mergedFeatures[asset.localIdentifier] = refined
                    secondPassExtractionCount += 1
                }
            }

            if secondPassExtractionCount >= 2 {
                let rerankedTop = rankingService.rank(assets: topAssets, featuresByAssetID: mergedFeatures)
                if !rerankedTop.isEmpty {
                    let refinedWinnerID = rerankedTop[0].asset.localIdentifier
                    if refinedWinnerID != firstPassWinnerID {
                        let refinedWinnerScore = rerankedTop[0].score
                        let originalWinnerRefinedScore = rerankedTop
                            .first(where: { $0.asset.localIdentifier == firstPassWinnerID })?
                            .score ?? -Double.greatestFiniteMagnitude
                        let margin = refinedWinnerScore - originalWinnerRefinedScore
                        winnerChangeMargin = margin
                        if margin >= Self.secondPassWinnerOverrideMargin {
                            let rerankedTopIDs = Set(rerankedTop.map(\.asset.localIdentifier))
                            let remainder = ranked.filter { !rerankedTopIDs.contains($0.asset.localIdentifier) }
                            finalRanking = rerankedTop + remainder
                        }
                    }
                }
            }
        }

        let finalWinnerID = finalRanking.first?.asset.localIdentifier ?? firstPassWinnerID
        let diagnostics = GroupRankingDiagnostics(
            firstPassWinnerAssetID: firstPassWinnerID,
            finalWinnerAssetID: finalWinnerID,
            firstPassTopGap: firstPassTopGap,
            secondPassTriggered: secondPassTriggered,
            secondPassCandidateCount: secondPassCandidateCount,
            secondPassExtractionCount: secondPassExtractionCount,
            winnerChanged: finalWinnerID != firstPassWinnerID,
            winnerChangeMargin: winnerChangeMargin
        )

        return RefinedRankingResult(
            rankedCandidates: finalRanking,
            diagnostics: diagnostics
        )
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

    private static func pairKey(_ lhsID: String, _ rhsID: String) -> String {
        lhsID < rhsID ? "\(lhsID)|\(rhsID)" : "\(rhsID)|\(lhsID)"
    }

    static func refineAdjacencyByCoherence(
        assets: [PhotoAssetRef],
        adjacency: [String: Set<String>],
        edgeMetricsByPairKey: [String: SimilarEdgeMetrics],
        config: AnalysisConfiguration
    ) -> [String: Set<String>] {
        guard assets.count > 2 else { return adjacency }

        var refined = adjacency
        var bestNeighborByNode: [String: String] = [:]

        for asset in assets {
            let nodeID = asset.localIdentifier
            let neighbors = adjacency[nodeID] ?? []
            var bestScore = Double.greatestFiniteMagnitude
            var bestNeighbor: String?

            for neighbor in neighbors {
                let key = pairKey(nodeID, neighbor)
                guard let metrics = edgeMetricsByPairKey[key] else { continue }
                let score = coherenceScore(metrics: metrics, config: config)
                if score < bestScore {
                    bestScore = score
                    bestNeighbor = neighbor
                }
            }

            if let bestNeighbor {
                bestNeighborByNode[nodeID] = bestNeighbor
            }
        }

        for asset in assets {
            let lhsID = asset.localIdentifier
            let neighbors = adjacency[lhsID] ?? []
            for rhsID in neighbors where lhsID < rhsID {
                let key = pairKey(lhsID, rhsID)
                guard let metrics = edgeMetricsByPairKey[key] else { continue }

                let sharedNeighborCount = (adjacency[lhsID] ?? []).intersection(adjacency[rhsID] ?? []).count
                let isTopForEither = bestNeighborByNode[lhsID] == rhsID || bestNeighborByNode[rhsID] == lhsID
                let isStrong = isStrongEdge(metrics: metrics, config: config)

                if sharedNeighborCount == 0, !isTopForEither, !isStrong {
                    refined[lhsID, default: []].remove(rhsID)
                    refined[rhsID, default: []].remove(lhsID)
                }
            }
        }

        return refined
    }

    private static func computeEdgeMetrics(
        _ lhs: AssetAnalysisFeatures,
        _ rhs: AssetAnalysisFeatures
    ) -> SimilarEdgeMetrics {
        let timeGapSeconds = abs((lhs.asset.creationDate ?? .distantPast).timeIntervalSince(rhs.asset.creationDate ?? .distantPast))
        let xor = lhs.perceptualHash ^ rhs.perceptualHash
        let hashDistance = Double(xor.nonzeroBitCount) / 64.0

        var visionDistance: Float?
        if let lhsPrint = lhs.visionFeaturePrint, let rhsPrint = rhs.visionFeaturePrint {
            var rawDistance: Float = 0
            if (try? lhsPrint.computeDistance(&rawDistance, to: rhsPrint)) != nil {
                visionDistance = rawDistance
            }
        }

        return SimilarEdgeMetrics(
            timeGapSeconds: timeGapSeconds,
            hashDistance: hashDistance,
            visionDistance: visionDistance
        )
    }

    private static func groupSimilarityDiagnostics(
        for component: [PhotoAssetRef],
        adjacency: [String: Set<String>],
        edgeMetricsByPairKey: [String: SimilarEdgeMetrics]
    ) -> GroupSimilarityDiagnostics? {
        guard component.count >= 2 else { return nil }

        var edges: [SimilarEdgeMetrics] = []
        for lhsIndex in 0 ..< component.count {
            for rhsIndex in (lhsIndex + 1) ..< component.count {
                let lhs = component[lhsIndex]
                let rhs = component[rhsIndex]
                guard adjacency[lhs.localIdentifier]?.contains(rhs.localIdentifier) == true else {
                    continue
                }
                let key = pairKey(lhs.localIdentifier, rhs.localIdentifier)
                if let metrics = edgeMetricsByPairKey[key] {
                    edges.append(metrics)
                }
            }
        }

        guard !edges.isEmpty else { return nil }

        let edgeCount = edges.count
        let gapValues = edges.map(\.timeGapSeconds)
        let hashValues = edges.map(\.hashDistance)
        let visionValues = edges.compactMap(\.visionDistance)

        let averageGap = gapValues.reduce(0, +) / Double(edgeCount)
        let averageHash = hashValues.reduce(0, +) / Double(edgeCount)
        let averageVision: Float? = visionValues.isEmpty
            ? nil
            : (visionValues.reduce(0, +) / Float(visionValues.count))

        return GroupSimilarityDiagnostics(
            edgeCount: edgeCount,
            minEdgeGapSeconds: gapValues.min() ?? 0,
            maxEdgeGapSeconds: gapValues.max() ?? 0,
            averageEdgeGapSeconds: averageGap,
            minHashDistance: hashValues.min() ?? 0,
            maxHashDistance: hashValues.max() ?? 0,
            averageHashDistance: averageHash,
            visionEdgeCount: visionValues.count,
            minVisionDistance: visionValues.min(),
            maxVisionDistance: visionValues.max(),
            averageVisionDistance: averageVision
        )
    }

    private static func coherenceScore(
        metrics: SimilarEdgeMetrics,
        config: AnalysisConfiguration
    ) -> Double {
        let hashNorm = metrics.hashDistance / max(0.0001, config.hashDistanceThreshold)
        let visionNorm = metrics.visionDistance.map { Double($0 / max(0.001, config.visionDistanceThreshold)) } ?? 1.25
        let timeNorm = min(1.5, metrics.timeGapSeconds / maxPairwiseEdgeGapSeconds)
        return (hashNorm * 0.55) + (visionNorm * 0.30) + (timeNorm * 0.15)
    }

    private static func isStrongEdge(
        metrics: SimilarEdgeMetrics,
        config: AnalysisConfiguration
    ) -> Bool {
        let strictHashThreshold = max(0.10, config.hashDistanceThreshold - 0.08)
        let strictVisionThreshold = max(7, config.visionDistanceThreshold - 2.5)
        let isStrongHash = metrics.hashDistance <= strictHashThreshold
        let isStrongVision = metrics.visionDistance.map { $0 <= strictVisionThreshold } ?? false
        let isVeryClose = metrics.timeGapSeconds <= 30 && metrics.hashDistance <= min(0.26, config.hashDistanceThreshold + 0.02)

        if (isStrongHash || isStrongVision), metrics.timeGapSeconds <= 120 {
            return true
        }
        if isStrongHash && isStrongVision {
            return true
        }
        return isVeryClose
    }
}
