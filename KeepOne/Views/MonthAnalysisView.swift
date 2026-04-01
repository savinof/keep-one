import SwiftUI

struct MonthAnalysisView: View {
    @StateObject private var viewModel: MonthAnalysisViewModel
    @EnvironmentObject private var container: AppContainer
    @State private var isShowingGapSheet = false
    @State private var draftGapSeconds: Double = AnalysisConfiguration.default.temporalGapThresholdSeconds
    @State private var draftPreset: SimilarityPreset = AnalysisConfiguration.default.similarityPreset
    @State private var draftCacheValidationMode: CacheValidationMode = .lightweightSnapshot

    init(viewModel: MonthAnalysisViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView

            case .failed(let message):
                ContentUnavailableView(
                    "Analysis Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )

            case .loaded:
                loadedView
            }
        }
        .navigationTitle(viewModel.selection.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Re-Run") {
                    Task { await viewModel.analyze(forceRecompute: true, runMode: .localFirst) }
                }
                .disabled(viewModel.state == .loading)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Improve") {
                    Task { await viewModel.improveWithNetwork() }
                }
                .disabled(viewModel.state == .loading || !viewModel.canImproveWithNetwork)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("\(viewModel.similarityPreset.title) · \(viewModel.temporalGapLabel())") {
                    draftGapSeconds = viewModel.temporalGapSeconds
                    draftPreset = viewModel.similarityPreset
                    draftCacheValidationMode = viewModel.cacheValidationMode
                    isShowingGapSheet = true
                }
                .disabled(viewModel.state == .loading)
            }
        }
        .task {
            await viewModel.loadSettingsIfNeeded()
            if viewModel.result == nil {
                await viewModel.analyze(forceRecompute: false, runMode: .localFirst)
            }
        }
        .sheet(isPresented: $isShowingGapSheet) {
            NavigationStack {
                Form {
                    Section("Similarity Preset") {
                        Picker("Preset", selection: $draftPreset) {
                            ForEach(SimilarityPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(presetDescription(for: draftPreset))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Temporal Gap") {
                        Text("Photos shot within this window are considered in the same sequence before visual similarity checks.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.temporalGapLabel(seconds: draftGapSeconds))
                                .font(.headline)
                            Slider(
                                value: $draftGapSeconds,
                                in: 10 ... 900,
                                step: 10
                            )
                        }
                    }

                    Section("Cache Validation") {
                        Picker("Mode", selection: $draftCacheValidationMode) {
                            ForEach(CacheValidationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(draftCacheValidationMode.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Tracking File") {
                        Text(viewModel.settingsFilePath)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .navigationTitle("Similarity Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingGapSheet = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            isShowingGapSheet = false
                            Task {
                                await viewModel.applyAnalysisSettings(
                                    seconds: draftGapSeconds,
                                    preset: draftPreset,
                                    cacheValidationMode: draftCacheValidationMode
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(viewModel.progress.stage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var loadedView: some View {
        if let result = viewModel.result {
            if result.groups.isEmpty {
                let diagnosticsText: String = {
                    guard let diagnostics = result.diagnostics else { return "" }
                    return " Sequences: \(diagnostics.sequenceCount), features: \(diagnostics.featureExtractionCount), similarity links: \(diagnostics.similarityEdgeCount)."
                }()
                let availabilityText: String = if let status = viewModel.availabilityStatusText {
                    " \(status)"
                } else {
                    ""
                }
                ContentUnavailableView(
                    "No Similar Groups Found",
                    systemImage: "checkmark.shield",
                    description: Text(
                        "Analyzed \(result.assetCountAnalyzed) photos and found no safe matches. " +
                            "Try another month or adjust gap and re-run." +
                            diagnosticsText +
                            availabilityText
                    )
                )
            } else {
                List {
                    if let status = viewModel.availabilityStatusText {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(result.groups) { group in
                        NavigationLink {
                            GroupDetailView(
                                viewModel: GroupDetailViewModel(
                                    group: group,
                                    photoLibraryService: container.photoLibraryService
                                ),
                                onDeleted: {
                                    await viewModel.analyze(forceRecompute: true)
                                }
                            )
                        } label: {
                            GroupCardView(group: group)
                        }
                    }
                }
                .listStyle(.plain)
            }
        } else {
            ContentUnavailableView(
                "No Analysis Result",
                systemImage: "photo.stack",
                description: Text("Tap Re-Run to start month analysis.")
            )
        }
    }

    private func presetDescription(for preset: SimilarityPreset) -> String {
        switch preset {
        case .strict:
            return "Fewest false matches. Best when you want only near-duplicates."
        case .balanced:
            return "Recommended default for typical monthly review."
        case .relaxed:
            return "Catches more variations of a scene, with higher false-match risk."
        }
    }
}
