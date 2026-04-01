import Foundation
import Photos
import UIKit

enum ThumbnailFetchSkipReason {
    case noLocalRepresentation
    case unavailable
}

struct ThumbnailFetchResult {
    let image: UIImage?
    let usedDegradedThumbnail: Bool
    let skipReason: ThumbnailFetchSkipReason?
}

protocol ThumbnailServiceProtocol {
    func thumbnail(for localIdentifier: String, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage?
    func analysisThumbnail(
        for localIdentifier: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        allowNetworkAccess: Bool
    ) async -> ThumbnailFetchResult
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

    func analysisThumbnail(
        for localIdentifier: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        allowNetworkAccess: Bool
    ) async -> ThumbnailFetchResult {
        let modeKey = allowNetworkAccess ? "network" : "local"
        let cacheKey = "analysis-\(modeKey)-\(localIdentifier)-\(Int(targetSize.width))x\(Int(targetSize.height))-\(contentMode.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return ThumbnailFetchResult(
                image: cached,
                usedDegradedThumbnail: false,
                skipReason: nil
            )
        }

        guard let asset = photoLibraryService.fetchAsset(localIdentifier: localIdentifier) else {
            return ThumbnailFetchResult(
                image: nil,
                usedDegradedThumbnail: false,
                skipReason: .unavailable
            )
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = allowNetworkAccess ? .highQualityFormat : .opportunistic
        options.resizeMode = .exact
        options.isSynchronous = false
        options.isNetworkAccessAllowed = allowNetworkAccess

        let fetchResult = await withCheckedContinuation { (continuation: CheckedContinuation<ThumbnailFetchResult, Never>) in
            var resumed = false
            var degradedFallback: UIImage?

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                if resumed { return }

                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    resumed = true
                    continuation.resume(returning: ThumbnailFetchResult(
                        image: nil,
                        usedDegradedThumbnail: false,
                        skipReason: .unavailable
                    ))
                    return
                }

                if info?[PHImageErrorKey] != nil {
                    resumed = true
                    continuation.resume(returning: ThumbnailFetchResult(
                        image: nil,
                        usedDegradedThumbnail: false,
                        skipReason: .unavailable
                    ))
                    return
                }

                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

                if !allowNetworkAccess {
                    if let image {
                        resumed = true
                        continuation.resume(returning: ThumbnailFetchResult(
                            image: image,
                            usedDegradedThumbnail: isDegraded,
                            skipReason: nil
                        ))
                        return
                    }

                    if isInCloud {
                        resumed = true
                        continuation.resume(returning: ThumbnailFetchResult(
                            image: nil,
                            usedDegradedThumbnail: false,
                            skipReason: .noLocalRepresentation
                        ))
                    } else {
                        resumed = true
                        continuation.resume(returning: ThumbnailFetchResult(
                            image: nil,
                            usedDegradedThumbnail: false,
                            skipReason: .unavailable
                        ))
                    }
                    return
                }

                if let image {
                    if isDegraded {
                        degradedFallback = image
                        return
                    }

                    resumed = true
                    continuation.resume(returning: ThumbnailFetchResult(
                        image: image,
                        usedDegradedThumbnail: false,
                        skipReason: nil
                    ))
                    return
                }

                if isInCloud, let degradedFallback {
                    resumed = true
                    continuation.resume(returning: ThumbnailFetchResult(
                        image: degradedFallback,
                        usedDegradedThumbnail: true,
                        skipReason: nil
                    ))
                } else if !isInCloud {
                    resumed = true
                    continuation.resume(returning: ThumbnailFetchResult(
                        image: degradedFallback,
                        usedDegradedThumbnail: degradedFallback != nil,
                        skipReason: degradedFallback == nil ? .unavailable : nil
                    ))
                }
            }
        }

        if let image = fetchResult.image {
            cache.setObject(image, forKey: cacheKey)
        }

        return fetchResult
    }
}
