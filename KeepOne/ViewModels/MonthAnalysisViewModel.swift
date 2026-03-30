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
    @Published private(set) var settingsFilePath: String = ""

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
        settingsFilePath = await analysisService.settingsFilePath()
        didLoadSettings = true
    }

    func applyTemporalGap(seconds: TimeInterval) async {
        await analysisService.updateTemporalGapSeconds(seconds)
        temporalGapSeconds = await analysisService.currentTemporalGapSeconds()
        await analyze(forceRecompute: true)
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

    func analyze(forceRecompute: Bool = false) async {
        state = .loading
        progress = AnalysisProgress(stage: "Starting analysis", completedUnits: 0, totalUnits: 1)

        do {
            let result = try await analysisService.analyze(
                selection: selection,
                forceRecompute: forceRecompute,
                progress: { [weak self] update in
                    Task { @MainActor in
                        self?.progress = update
                    }
                }
            )
            self.result = result
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
