import SwiftUI

struct GroupCardView: View {
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
            }
        }
        .padding(.vertical, 6)
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
