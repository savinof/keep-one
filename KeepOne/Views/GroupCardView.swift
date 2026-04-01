import SwiftUI

struct GroupCardView: View {
    struct RankingSummary: Equatable {
        let iconName: String
        let text: String
    }

    let group: SimilarPhotoGroup

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PhotoThumbnailView(localIdentifier: group.representativeAssetID, side: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Suggested")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("\(group.count) similar photos")
                    .font(.headline)
                if let dateText = dateText {
                    Text(dateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let summary = Self.rankingSummary(for: group.rankingDiagnostics) {
                    Label(summary.text, systemImage: summary.iconName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }

    static func rankingSummary(for diagnostics: GroupRankingDiagnostics?) -> RankingSummary? {
        guard let diagnostics else { return nil }

        if !diagnostics.secondPassTriggered {
            return RankingSummary(
                iconName: "checkmark.seal",
                text: "Clear first-pass winner"
            )
        }

        if diagnostics.secondPassExtractionCount < 2 {
            return RankingSummary(
                iconName: "exclamationmark.triangle",
                text: "Second pass had limited data"
            )
        }

        if diagnostics.winnerChanged {
            return RankingSummary(
                iconName: "arrow.triangle.2.circlepath",
                text: "Refined on larger preview"
            )
        }

        return RankingSummary(
            iconName: "checkmark.circle",
            text: "Confirmed on larger preview"
        )
    }

    private var dateText: String? {
        guard let range = group.dateRange else { return nil }
        if Calendar.current.isDate(range.start, inSameDayAs: range.end) {
            return Self.shortDateFormatter.string(from: range.start)
        }
        return "\(Self.shortDateFormatter.string(from: range.start)) - \(Self.shortDateFormatter.string(from: range.end))"
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
