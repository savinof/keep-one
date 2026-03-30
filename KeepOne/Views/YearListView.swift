import SwiftUI

struct YearListView: View {
    @StateObject private var viewModel: YearListViewModel
    @EnvironmentObject private var container: AppContainer

    init(viewModel: YearListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading years...")
            } else if let message = viewModel.errorMessage, viewModel.years.isEmpty {
                ContentUnavailableView(
                    "No Years Found",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(message)
                )
            } else {
                List(viewModel.years) { year in
                    NavigationLink {
                        MonthListView(
                            viewModel: MonthListViewModel(
                                year: year.year,
                                photoLibraryService: container.photoLibraryService,
                                cache: container.cache
                            )
                        )
                    } label: {
                        HStack {
                            Text(verbatim: String(year.year))
                            Spacer()
                            Text("\(year.assetCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Choose Year")
        .task {
            if viewModel.years.isEmpty {
                await viewModel.loadYears()
            }
        }
    }

}
