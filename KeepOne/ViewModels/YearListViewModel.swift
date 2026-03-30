import Foundation

@MainActor
final class YearListViewModel: ObservableObject {
    @Published private(set) var years: [YearSection] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let photoLibraryService: any PhotoLibraryServiceProtocol

    init(photoLibraryService: any PhotoLibraryServiceProtocol) {
        self.photoLibraryService = photoLibraryService
    }

    func loadYears() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        years = await photoLibraryService.fetchAvailableYears()
        if years.isEmpty {
            errorMessage = "No photos were found in the library."
        }
        isLoading = false
    }
}
