import Foundation

@MainActor
final class GroupDetailViewModel: ObservableObject {
    @Published private(set) var selectedForDeletion = Set<String>()
    @Published private(set) var isDeleting = false
    @Published var deleteErrorMessage: String?
    @Published var showDeleteConfirmation = false

    let group: SimilarPhotoGroup

    private let photoLibraryService: any PhotoLibraryServiceProtocol

    init(
        group: SimilarPhotoGroup,
        photoLibraryService: any PhotoLibraryServiceProtocol
    ) {
        self.group = group
        self.photoLibraryService = photoLibraryService
    }

    var suggestedCandidate: RankedPhotoCandidate? {
        group.rankedCandidates.first { $0.asset.localIdentifier == group.suggestedBestAssetID } ?? group.rankedCandidates.first
    }

    var canDelete: Bool {
        !selectedForDeletion.isEmpty && !isDeleting
    }

    func isSuggested(assetID: String) -> Bool {
        assetID == group.suggestedBestAssetID
    }

    func isSelected(assetID: String) -> Bool {
        selectedForDeletion.contains(assetID)
    }

    func toggleSelection(for assetID: String) {
        if selectedForDeletion.contains(assetID) {
            selectedForDeletion.remove(assetID)
        } else {
            selectedForDeletion.insert(assetID)
        }
    }

    func requestDeleteConfirmation() {
        guard canDelete else { return }
        showDeleteConfirmation = true
    }

    func deleteSelected() async -> Bool {
        guard canDelete else { return false }

        isDeleting = true
        deleteErrorMessage = nil
        defer { isDeleting = false }

        do {
            try await photoLibraryService.deleteAssets(with: Array(selectedForDeletion))
            selectedForDeletion.removeAll()
            return true
        } catch {
            deleteErrorMessage = error.localizedDescription
            return false
        }
    }
}
