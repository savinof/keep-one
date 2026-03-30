import Foundation
import Photos

protocol PhotoLibraryServiceProtocol {
    func authorizationStatus() -> PHAuthorizationStatus
    func requestAuthorization() async -> PHAuthorizationStatus
    func fetchAvailableYears() async -> [YearSection]
    func fetchMonths(in year: Int) async -> [MonthSection]
    func fetchImageAssets(for selection: MonthSelection) async -> [PhotoAssetRef]
    func fetchAsset(localIdentifier: String) -> PHAsset?
    func deleteAssets(with localIdentifiers: [String]) async throws
}

enum PhotoLibraryError: LocalizedError {
    case missingAssetsForDeletion
    case unknownDeletionFailure

    var errorDescription: String? {
        switch self {
        case .missingAssetsForDeletion:
            return "Some selected photos were no longer available."
        case .unknownDeletionFailure:
            return "Photo deletion did not complete."
        }
    }
}

final class PhotoLibraryService: PhotoLibraryServiceProtocol {
    private let queue = DispatchQueue(label: "keepone.photo-library", qos: .userInitiated)

    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchAvailableYears() async -> [YearSection] {
        let queue = self.queue
        return await withCheckedContinuation { continuation in
            queue.async {
                let index = Self.buildYearMonthIndex()
                let years = index
                    .map { (year, monthMap) in
                        YearSection(year: year, assetCount: monthMap.values.reduce(0, +))
                    }
                    .sorted { $0.year > $1.year }
                continuation.resume(returning: years)
            }
        }
    }

    func fetchMonths(in year: Int) async -> [MonthSection] {
        let queue = self.queue
        return await withCheckedContinuation { continuation in
            queue.async {
                let index = Self.buildYearMonthIndex()
                let monthCounts = index[year] ?? [:]
                let months = monthCounts
                    .map { month, count in
                        MonthSection(year: year, month: month, assetCount: count)
                    }
                    .sorted { lhs, rhs in lhs.month > rhs.month }
                continuation.resume(returning: months)
            }
        }
    }

    func fetchImageAssets(for selection: MonthSelection) async -> [PhotoAssetRef] {
        await withCheckedContinuation { continuation in
            queue.async {
                let options = PHFetchOptions()
                options.predicate = NSPredicate(
                    format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
                    PHAssetMediaType.image.rawValue,
                    selection.startDate as NSDate,
                    selection.endDate as NSDate
                )
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

                let fetchResult = PHAsset.fetchAssets(with: options)
                var results: [PhotoAssetRef] = []
                results.reserveCapacity(fetchResult.count)

                fetchResult.enumerateObjects { asset, _, _ in
                    results.append(Self.map(asset: asset))
                }
                continuation.resume(returning: results)
            }
        }
    }

    func fetchAsset(localIdentifier: String) -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return fetchResult.firstObject
    }

    func deleteAssets(with localIdentifiers: [String]) async throws {
        guard !localIdentifiers.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard fetchResult.count == localIdentifiers.count else {
            throw PhotoLibraryError.missingAssetsForDeletion
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibraryError.unknownDeletionFailure)
                }
            }
        }
    }

    private static func buildYearMonthIndex() -> [Int: [Int: Int]] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let fetchResult = PHAsset.fetchAssets(with: options)
        var result: [Int: [Int: Int]] = [:]
        let calendar = MonthSelection.calendar

        fetchResult.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { return }
            result[year, default: [:]][month, default: 0] += 1
        }

        return result
    }

    private static func map(asset: PHAsset) -> PhotoAssetRef {
        PhotoAssetRef(
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            mediaSubtypesRawValue: asset.mediaSubtypes.rawValue,
            burstIdentifier: asset.burstIdentifier,
            burstSelectionTypesRawValue: asset.burstSelectionTypes.rawValue,
            isFavorite: asset.isFavorite
        )
    }
}
