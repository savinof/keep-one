import Foundation

protocol GroupingServiceProtocol {
    func temporalSequences(from assets: [PhotoAssetRef], maxGap: TimeInterval) -> [TemporalSequence]
    func buildAdjacency(
        assets: [PhotoAssetRef],
        isConnected: (PhotoAssetRef, PhotoAssetRef) -> Bool
    ) -> [String: Set<String>]
    func connectedComponents(
        assets: [PhotoAssetRef],
        adjacency: [String: Set<String>]
    ) -> [[PhotoAssetRef]]
}

final class GroupingService: GroupingServiceProtocol {
    func temporalSequences(from assets: [PhotoAssetRef], maxGap: TimeInterval) -> [TemporalSequence] {
        guard !assets.isEmpty else { return [] }

        var sequences: [[PhotoAssetRef]] = []
        var current: [PhotoAssetRef] = []
        var previousDate: Date?
        var previousBurstIdentifier: String?

        for asset in assets {
            guard let date = asset.creationDate else {
                if !current.isEmpty {
                    sequences.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                sequences.append([asset])
                previousDate = nil
                previousBurstIdentifier = nil
                continue
            }

            if let previousDate {
                let gap = date.timeIntervalSince(previousDate)
                let belongsToSameBurst: Bool = {
                    guard
                        let previousBurstIdentifier,
                        let currentBurst = asset.burstIdentifier
                    else {
                        return false
                    }
                    return previousBurstIdentifier == currentBurst
                }()

                if gap > maxGap, !belongsToSameBurst {
                    sequences.append(current)
                    current = [asset]
                } else {
                    current.append(asset)
                }
            } else {
                if !current.isEmpty {
                    sequences.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                current.append(asset)
            }

            previousDate = date
            previousBurstIdentifier = asset.burstIdentifier
        }

        if !current.isEmpty {
            sequences.append(current)
        }

        return sequences.enumerated().map { index, assets in
            TemporalSequence(id: index, assets: assets)
        }
    }

    func buildAdjacency(
        assets: [PhotoAssetRef],
        isConnected: (PhotoAssetRef, PhotoAssetRef) -> Bool
    ) -> [String: Set<String>] {
        var adjacency = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, Set<String>()) })

        guard assets.count > 1 else { return adjacency }

        for leftIndex in 0 ..< assets.count {
            for rightIndex in (leftIndex + 1) ..< assets.count {
                let left = assets[leftIndex]
                let right = assets[rightIndex]
                if isConnected(left, right) {
                    adjacency[left.localIdentifier, default: []].insert(right.localIdentifier)
                    adjacency[right.localIdentifier, default: []].insert(left.localIdentifier)
                }
            }
        }

        return adjacency
    }

    func connectedComponents(
        assets: [PhotoAssetRef],
        adjacency: [String: Set<String>]
    ) -> [[PhotoAssetRef]] {
        var idToAsset: [String: PhotoAssetRef] = [:]
        assets.forEach { idToAsset[$0.localIdentifier] = $0 }

        var visited = Set<String>()
        var components: [[PhotoAssetRef]] = []

        for asset in assets {
            let id = asset.localIdentifier
            if visited.contains(id) { continue }

            var stack = [id]
            var componentIDs: [String] = []
            visited.insert(id)

            while let current = stack.popLast() {
                componentIDs.append(current)
                let neighbors = adjacency[current] ?? []

                for neighbor in neighbors where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    stack.append(neighbor)
                }
            }

            let componentAssets = componentIDs.compactMap { idToAsset[$0] }
            components.append(componentAssets)
        }

        return components
    }
}
