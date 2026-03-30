import Foundation

struct MonthListItem: Identifiable, Hashable {
    let month: MonthSection
    let hasCachedAnalysis: Bool

    var id: String { month.id }
}

@MainActor
final class MonthListViewModel: ObservableObject {
    @Published private(set) var items: [MonthListItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let year: Int

    private let photoLibraryService: any PhotoLibraryServiceProtocol
    private let cache: any AnalysisCacheProtocol

    init(
        year: Int,
        photoLibraryService: any PhotoLibraryServiceProtocol,
        cache: any AnalysisCacheProtocol
    ) {
        self.year = year
        self.photoLibraryService = photoLibraryService
        self.cache = cache
    }

    func loadMonths() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let months = await photoLibraryService.fetchMonths(in: year)
            .sorted { lhs, rhs in
                lhs.month > rhs.month
            }

        items = months.map { month in
            MonthListItem(
                month: month,
                hasCachedAnalysis: cache.hasCachedResult(selection: month.selection)
            )
        }

        if items.isEmpty {
            errorMessage = "No photos were found for \(year)."
        }

        isLoading = false
    }
}
