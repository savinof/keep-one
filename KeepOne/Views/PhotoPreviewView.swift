import SwiftUI
import UIKit

struct PhotoPreviewView: View {
    let assetIDs: [String]
    let initialAssetID: String
    let isSuggested: (String) -> Bool
    let isSelectedForDeletion: (String) -> Bool
    let onToggleSelection: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedIndex: Int

    init(
        assetIDs: [String],
        initialAssetID: String,
        isSuggested: @escaping (String) -> Bool,
        isSelectedForDeletion: @escaping (String) -> Bool,
        onToggleSelection: @escaping (String) -> Void
    ) {
        let resolvedAssetIDs = assetIDs.isEmpty ? [initialAssetID] : assetIDs
        self.assetIDs = resolvedAssetIDs
        self.initialAssetID = initialAssetID
        self.isSuggested = isSuggested
        self.isSelectedForDeletion = isSelectedForDeletion
        self.onToggleSelection = onToggleSelection
        _selectedIndex = State(initialValue: resolvedAssetIDs.firstIndex(of: initialAssetID) ?? 0)
    }

    private var currentAssetID: String {
        guard assetIDs.indices.contains(selectedIndex) else {
            return initialAssetID
        }
        return assetIDs[selectedIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(assetIDs.enumerated()), id: \.offset) { index, assetID in
                    PhotoPreviewPage(localIdentifier: assetID)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: assetIDs.count > 1 ? .automatic : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Spacer()

                    if isSuggested(currentAssetID) {
                        Text("Suggested best")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.92))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Spacer()

                Text("\(selectedIndex + 1) of \(assetIDs.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 6)

                if assetIDs.count > 1 {
                    Text("Swipe left or right to compare")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 8)
                }

                Button {
                    onToggleSelection(currentAssetID)
                } label: {
                    Label(
                        isSelectedForDeletion(currentAssetID) ? "Remove from deletion" : "Mark for deletion",
                        systemImage: isSelectedForDeletion(currentAssetID) ? "checkmark.circle.fill" : "trash"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSelectedForDeletion(currentAssetID) ? .gray : .red)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }
}

private struct PhotoPreviewPage: View {
    let localIdentifier: String

    @EnvironmentObject private var container: AppContainer
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 64)
        .task(id: localIdentifier) {
            await loadPreviewIfNeeded()
        }
    }

    private func loadPreviewIfNeeded() async {
        guard image == nil else { return }
        let screen = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        image = await container.thumbnailService.thumbnail(
            for: localIdentifier,
            targetSize: CGSize(width: screen.width * scale, height: screen.height * scale),
            contentMode: .aspectFit
        )
    }
}
