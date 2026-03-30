import Foundation
import Photos
import UIKit

protocol ThumbnailServiceProtocol {
    func thumbnail(for localIdentifier: String, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage?
}

final class ThumbnailService: ThumbnailServiceProtocol {
    private let imageManager = PHCachingImageManager()
    private let photoLibraryService: any PhotoLibraryServiceProtocol
    private let cache = NSCache<NSString, UIImage>()

    init(photoLibraryService: any PhotoLibraryServiceProtocol) {
        self.photoLibraryService = photoLibraryService
        cache.countLimit = 500
    }

    func thumbnail(for localIdentifier: String, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        let cacheKey = "\(localIdentifier)-\(Int(targetSize.width))x\(Int(targetSize.height))-\(contentMode.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let asset = photoLibraryService.fetchAsset(localIdentifier: localIdentifier) else {
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                if resumed { return }

                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }

                if info?[PHImageErrorKey] != nil {
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded {
                    return
                }

                resumed = true
                continuation.resume(returning: image)
            }
        }

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }

        return image
    }
}
