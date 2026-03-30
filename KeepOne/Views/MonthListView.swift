import SwiftUI

struct MonthListView: View {
    @StateObject private var viewModel: MonthListViewModel
    @EnvironmentObject private var container: AppContainer

    init(viewModel: MonthListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading months...")
            } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No Months Found",
                    systemImage: "calendar",
                    description: Text(message)
                )
            } else {
                List(viewModel.items) { item in
                    NavigationLink {
                        MonthAnalysisView(
                            viewModel: MonthAnalysisViewModel(
                                selection: item.month.selection,
                                analysisService: container.monthAnalysisService
                            )
                        )
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.month.title)
                                Text("\(item.month.assetCount) photos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.hasCachedAnalysis {
                                Text("Cached")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(viewModel.year))
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadMonths()
            }
        }
    }
}
