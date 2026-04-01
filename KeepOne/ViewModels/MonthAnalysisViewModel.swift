import Foundation

@MainActor
final class MonthAnalysisViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress: AnalysisProgress = .idle
    @Published private(set) var result: MonthAnalysisResult?
    @Published private(set) var temporalGapSeconds: TimeInterval = AnalysisConfiguration.default.temporalGapThresholdSeconds
    @Published private(set) var similarityPreset: SimilarityPreset = AnalysisConfiguration.default.similarityPreset
    @Published private(set) var cacheValidationMode: CacheValidationMode = .lightweightSnapshot
    @Published private(set) var settingsFilePath: String = ""
    @Published private(set) var lastRunMode: AnalysisRunMode = .localFirst

    let selection: MonthSelection

    private let analysisService: any MonthAnalysisServiceProtocol
    private var didLoadSettings = false

    init(
        selection: MonthSelection,
        analysisService: any MonthAnalysisServiceProtocol
    ) {
        self.selection = selection
        self.analysisService = analysisService
    }

    func loadSettingsIfNeeded() async {
        guard !didLoadSettings else { return }
        temporalGapSeconds = await analysisService.currentTemporalGapSeconds()
        similarityPreset = await analysisService.currentSimilarityPreset()
        cacheValidationMode = await analysisService.currentCacheValidationMode()
        settingsFilePath = await analysisService.settingsFilePath()
        didLoadSettings = true
    }

    func applyAnalysisSettings(
        seconds: TimeInterval,
        preset: SimilarityPreset,
        cacheValidationMode: CacheValidationMode
    ) async {
        await analysisService.updateTemporalGapSeconds(seconds)
        await analysisService.updateSimilarityPreset(preset)
        await analysisService.updateCacheValidationMode(cacheValidationMode)
        temporalGapSeconds = await analysisService.currentTemporalGapSeconds()
        similarityPreset = await analysisService.currentSimilarityPreset()
        self.cacheValidationMode = await analysisService.currentCacheValidationMode()
        await analyze(forceRecompute: true, runMode: .localFirst)
    }

    func improveWithNetwork() async {
        await analyze(forceRecompute: true, runMode: .improvedWithNetwork)
    }

    func temporalGapLabel(seconds: TimeInterval? = nil) -> String {
        let value = Int((seconds ?? temporalGapSeconds).rounded())
        let minutes = value / 60
        let remainingSeconds = value % 60
        if remainingSeconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }

    func analyze(forceRecompute: Bool = false, runMode: AnalysisRunMode = .localFirst) async {
        state = .loading
        progress = AnalysisProgress(stage: "Starting analysis", completedUnits: 0, totalUnits: 1)
        lastRunMode = runMode

        do {
            let result = try await analysisService.analyze(
                selection: selection,
                forceRecompute: forceRecompute,
                runMode: runMode,
                progress: { [weak self] update in
                    Task { @MainActor in
                        self?.progress = update
                    }
                }
            )
            self.result = result
            self.lastRunMode = result.runMode ?? runMode
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var canImproveWithNetwork: Bool {
        guard let diagnostics = result?.assetAvailabilityDiagnostics else { return false }
        return diagnostics.skippedNoLocalThumbnailCount > 0
    }

    var availabilityStatusText: String? {
        guard let diagnostics = result?.assetAvailabilityDiagnostics else { return nil }
        guard diagnostics.degradedThumbnailCount > 0 || diagnostics.skippedNoLocalThumbnailCount > 0 else { return nil }

        var parts: [String] = []
        if diagnostics.degradedThumbnailCount > 0 {
            parts.append("\(diagnostics.degradedThumbnailCount) used local preview thumbnails.")
        }
        if diagnostics.skippedNoLocalThumbnailCount > 0 {
            parts.append("\(diagnostics.skippedNoLocalThumbnailCount) skipped (iCloud-only, not local).")
        }
        return parts.joined(separator: " ")
    }
}
