import SwiftUI

struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GroupDetailViewModel
    @State private var previewAssetID: String?
    @State private var showHelpSheet = false

    private let onDeleted: @MainActor () async -> Void

    init(
        viewModel: GroupDetailViewModel,
        onDeleted: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDeleted = onDeleted
    }

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(viewModel.group.assets) { asset in
                            photoTile(asset: asset)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.toggleSelection(for: asset.localIdentifier)
                                }
                                .onLongPressGesture(minimumDuration: 0.28) {
                                    previewAssetID = asset.localIdentifier
                                }
                        }
                    }
                }
                .padding()
            }

            Divider()
            footer
        }
        .navigationTitle("Review Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHelpSheet = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Review instructions")
            }
        }
        .alert("Delete selected photos?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let didDelete = await viewModel.deleteSelected()
                    if didDelete {
                        await onDeleted()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Deletion is permanent. KeepOne will only delete what you selected.")
        }
        .alert("Delete Failed", isPresented: deleteFailedBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.deleteErrorMessage ?? "Unknown error")
        }
        .fullScreenCover(isPresented: previewIsPresentedBinding) {
            if let previewAssetID {
                PhotoPreviewView(
                    assetIDs: viewModel.group.assets.map(\.localIdentifier),
                    initialAssetID: previewAssetID,
                    isSuggested: { assetID in
                        viewModel.isSuggested(assetID: assetID)
                    },
                    isSelectedForDeletion: { assetID in
                        viewModel.isSelected(assetID: assetID)
                    },
                    onToggleSelection: { assetID in
                        viewModel.toggleSelection(for: assetID)
                    }
                )
            }
        }
        .sheet(isPresented: $showHelpSheet) {
            NavigationStack {
                List {
                    Text("Suggested photo has a green border.")
                    Text("Tap a photo to mark or unmark it for deletion.")
                    Text("Long-press any photo to open full-screen preview.")
                    Text("Swipe left or right in preview to compare photos.")
                    Text("Deletion runs only after explicit confirmation.")
                }
                .navigationTitle("How Review Works")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showHelpSheet = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func photoTile(asset: PhotoAssetRef) -> some View {
        let isSuggested = viewModel.isSuggested(assetID: asset.localIdentifier)
        let isSelected = viewModel.isSelected(assetID: asset.localIdentifier)

        ZStack(alignment: .topTrailing) {
            PhotoThumbnailView(localIdentifier: asset.localIdentifier, side: 108)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? Color.red : (isSuggested ? Color.green : Color.clear),
                            lineWidth: isSelected || isSuggested ? 3 : 0
                        )
                }

            if isSuggested {
                Text("Suggested")
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(6)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .red)
                    .padding(6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedForDeletion.count) selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                viewModel.requestDeleteConfirmation()
            } label: {
                if viewModel.isDeleting {
                    ProgressView()
                } else {
                    Text("Delete")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .disabled(!viewModel.canDelete)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var deleteFailedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.deleteErrorMessage = nil
                }
            }
        )
    }

    private var previewIsPresentedBinding: Binding<Bool> {
        Binding(
            get: { previewAssetID != nil },
            set: { isPresented in
                if !isPresented {
                    previewAssetID = nil
                }
            }
        )
    }

}
