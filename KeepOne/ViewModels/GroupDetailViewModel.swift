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

    var hasSimilarityDiagnostics: Bool {
        group.similarityDiagnostics != nil
    }

    var hasRankingDiagnostics: Bool {
        group.rankingDiagnostics != nil
    }

    var rankingExplanationLines: [String] {
        guard let diagnostics = group.rankingDiagnostics else { return [] }

        var lines: [String] = []
        if let topGap = diagnostics.firstPassTopGap {
            lines.append("First-pass top gap: \(Self.decimalString(topGap, decimals: 2)).")
        }

        if diagnostics.secondPassTriggered {
            lines.append(
                "Second pass re-checked top \(diagnostics.secondPassCandidateCount) candidates " +
                    "with larger thumbnails (\(diagnostics.secondPassExtractionCount) refreshed)."
            )

            if diagnostics.winnerChanged {
                if let margin = diagnostics.winnerChangeMargin {
                    lines.append(
                        "Suggestion changed after second pass (margin \(Self.decimalString(margin, decimals: 2)))."
                    )
                } else {
                    lines.append("Suggestion changed after second pass.")
                }
            } else if let margin = diagnostics.winnerChangeMargin {
                lines.append(
                    "Alternative winner was evaluated (margin \(Self.decimalString(margin, decimals: 2))), " +
                        "but below override threshold."
                )
            } else {
                lines.append("Second pass confirmed the first-pass suggestion.")
            }
        } else {
            lines.append("Second pass was skipped because the first-pass lead was already clear.")
        }

        return lines
    }

    var similarityExplanationLines: [String] {
        guard let diagnostics = group.similarityDiagnostics else { return [] }

        var lines: [String] = []
        lines.append("\(diagnostics.edgeCount) similarity links kept this group connected.")
        lines.append(
            "Capture gap: \(Self.durationString(diagnostics.minEdgeGapSeconds)) to " +
                "\(Self.durationString(diagnostics.maxEdgeGapSeconds)) " +
                "(avg \(Self.durationString(diagnostics.averageEdgeGapSeconds)))."
        )
        lines.append(
            "Hash distance: \(Self.decimalString(diagnostics.minHashDistance, decimals: 2)) to " +
                "\(Self.decimalString(diagnostics.maxHashDistance, decimals: 2)) " +
                "(avg \(Self.decimalString(diagnostics.averageHashDistance, decimals: 2))). Lower is more similar."
        )

        if diagnostics.visionEdgeCount > 0,
           let minVision = diagnostics.minVisionDistance,
           let maxVision = diagnostics.maxVisionDistance,
           let avgVision = diagnostics.averageVisionDistance {
            lines.append(
                "Vision distance: \(Self.decimalString(Double(minVision), decimals: 1)) to " +
                    "\(Self.decimalString(Double(maxVision), decimals: 1)) " +
                    "(avg \(Self.decimalString(Double(avgVision), decimals: 1))) " +
                    "on \(diagnostics.visionEdgeCount)/\(diagnostics.edgeCount) links. Lower is more similar."
            )
        } else {
            lines.append("Vision distance was unavailable for this group; grouping relied on hash + timing.")
        }

        return lines
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

    private static func durationString(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        if rounded < 60 {
            return "\(rounded)s"
        }
        let minutes = rounded / 60
        let remaining = rounded % 60
        if remaining == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remaining)s"
    }

    private static func decimalString(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
