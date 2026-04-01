import CryptoKit
import Foundation
import Photos

protocol PhotoLibraryServiceProtocol {
    func authorizationStatus() -> PHAuthorizationStatus
    func requestAuthorization() async -> PHAuthorizationStatus
    func fetchAvailableYears() async -> [YearSection]
    func fetchMonths(in year: Int) async -> [MonthSection]
    func fetchMonthAssetSnapshot(
        for selection: MonthSelection,
        includeFullContentSignature: Bool
    ) async -> MonthAssetSnapshot
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

    func fetchMonthAssetSnapshot(
        for selection: MonthSelection,
        includeFullContentSignature: Bool
    ) async -> MonthAssetSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                let fetchResult = Self.fetchResultForMonth(selection: selection)
                continuation.resume(
                    returning: Self.snapshot(
                        from: fetchResult,
                        includeFullContentSignature: includeFullContentSignature
                    )
                )
            }
        }
    }

    func fetchImageAssets(for selection: MonthSelection) async -> [PhotoAssetRef] {
        await withCheckedContinuation { continuation in
            queue.async {
                let fetchResult = Self.fetchResultForMonth(selection: selection)
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

    private static func fetchResultForMonth(selection: MonthSelection) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaType.image.rawValue,
            selection.startDate as NSDate,
            selection.endDate as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return PHAsset.fetchAssets(with: options)
    }

    private static func snapshot(
        from fetchResult: PHFetchResult<PHAsset>,
        includeFullContentSignature: Bool
    ) -> MonthAssetSnapshot {
        let count = fetchResult.count
        guard count > 0 else {
            return MonthAssetSnapshot(
                assetCount: 0,
                oldestAssetID: nil,
                newestAssetID: nil,
                oldestCreationDate: nil,
                newestCreationDate: nil,
                sampledAssetIDs: [],
                fullContentSignature: includeFullContentSignature ? emptyContentSignature() : nil
            )
        }

        let oldest = fetchResult.object(at: 0)
        let newest = fetchResult.object(at: count - 1)
        let sampleIndices = sampleIndices(totalCount: count, maxSamples: 12)
        let sampledAssetIDs = sampleIndices.map { fetchResult.object(at: $0).localIdentifier }
        let fullContentSignature: String? = if includeFullContentSignature {
            monthContentSignature(from: fetchResult)
        } else {
            nil
        }

        return MonthAssetSnapshot(
            assetCount: count,
            oldestAssetID: oldest.localIdentifier,
            newestAssetID: newest.localIdentifier,
            oldestCreationDate: oldest.creationDate,
            newestCreationDate: newest.creationDate,
            sampledAssetIDs: sampledAssetIDs,
            fullContentSignature: fullContentSignature
        )
    }

    private static func monthContentSignature(from fetchResult: PHFetchResult<PHAsset>) -> String {
        var hasher = SHA256()
        fetchResult.enumerateObjects { asset, _, _ in
            updateHasher(&hasher, with: asset.localIdentifier)
            updateHasher(&hasher, with: asset.creationDate?.timeIntervalSinceReferenceDate)
            updateHasher(&hasher, with: asset.modificationDate?.timeIntervalSinceReferenceDate)
            updateHasher(&hasher, with: UInt64(asset.pixelWidth))
            updateHasher(&hasher, with: UInt64(asset.pixelHeight))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func emptyContentSignature() -> String {
        let digest = SHA256.hash(data: Data())
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func updateHasher(_ hasher: inout SHA256, with value: String) {
        var data = Data(value.utf8)
        data.append(0)
        hasher.update(data: data)
    }

    private static func updateHasher(_ hasher: inout SHA256, with value: TimeInterval?) {
        let marker: UInt8 = value == nil ? 0 : 1
        hasher.update(data: Data([marker]))
        guard let value else { return }
        var bitPattern = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bitPattern) { bytes in
            hasher.update(bufferPointer: bytes)
        }
    }

    private static func updateHasher(_ hasher: inout SHA256, with value: UInt64) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            hasher.update(bufferPointer: bytes)
        }
    }

    private static func sampleIndices(totalCount: Int, maxSamples: Int) -> [Int] {
        guard totalCount > 0, maxSamples > 0 else { return [] }
        if totalCount <= maxSamples {
            return Array(0 ..< totalCount)
        }

        let denominator = max(1, maxSamples - 1)
        var indices = Set<Int>()
        for sampleIndex in 0 ..< maxSamples {
            let position = Int(round(Double(sampleIndex) * Double(totalCount - 1) / Double(denominator)))
            indices.insert(min(totalCount - 1, max(0, position)))
        }
        return indices.sorted()
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
