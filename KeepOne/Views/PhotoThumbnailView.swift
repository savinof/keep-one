import SwiftUI
import UIKit

struct PhotoThumbnailView: View {
    let localIdentifier: String
    let side: CGFloat

    @EnvironmentObject private var container: AppContainer
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: taskID) {
            await loadIfNeeded()
        }
    }

    private var taskID: String {
        "\(localIdentifier)-\(Int(side))"
    }

    private func loadIfNeeded() async {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        image = await container.thumbnailService.thumbnail(
            for: localIdentifier,
            targetSize: CGSize(width: side * scale, height: side * scale),
            contentMode: .aspectFill
        )
    }
}
