import SwiftUI

struct MonthAnalysisView: View {
    @StateObject private var viewModel: MonthAnalysisViewModel
    @EnvironmentObject private var container: AppContainer
    @State private var isShowingGapSheet = false
    @State private var draftGapSeconds: Double = AnalysisConfiguration.default.temporalGapThresholdSeconds

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
                    Task { await viewModel.analyze(forceRecompute: true) }
                }
                .disabled(viewModel.state == .loading)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Gap \(viewModel.temporalGapLabel())") {
                    draftGapSeconds = viewModel.temporalGapSeconds
                    isShowingGapSheet = true
                }
                .disabled(viewModel.state == .loading)
            }
        }
        .task {
            await viewModel.loadSettingsIfNeeded()
            if viewModel.result == nil {
                await viewModel.analyze(forceRecompute: false)
            }
        }
        .sheet(isPresented: $isShowingGapSheet) {
            NavigationStack {
                Form {
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
                                await viewModel.applyTemporalGap(seconds: draftGapSeconds)
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
                ContentUnavailableView(
                    "No Similar Groups Found",
                    systemImage: "checkmark.shield",
                    description: Text(
                        "Analyzed \(result.assetCountAnalyzed) photos and found no safe matches. " +
                            "Try another month or adjust gap and re-run." +
                            diagnosticsText
                    )
                )
            } else {
                List {
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
}
