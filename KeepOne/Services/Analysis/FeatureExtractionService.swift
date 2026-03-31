import CoreGraphics
import Foundation
import Photos
import UIKit
import Vision

struct AssetAnalysisFeatures {
    let asset: PhotoAssetRef
    let perceptualHash: UInt64
    let sharpness: Double
    let faceCount: Int
    let faceAreaRatio: Double
    let faceCentering: Double
    let luminanceMean: Double
    let luminanceContrast: Double
    let saliencyScore: Double
    let visionFeaturePrint: VNFeaturePrintObservation?
}

protocol FeatureExtractionServiceProtocol {
    func extractFeatures(for asset: PhotoAssetRef, thumbnailSize: Int) async -> AssetAnalysisFeatures?
}

final class FeatureExtractionService: FeatureExtractionServiceProtocol {
    private let thumbnailService: any ThumbnailServiceProtocol

    init(thumbnailService: any ThumbnailServiceProtocol) {
        self.thumbnailService = thumbnailService
    }

    func extractFeatures(for asset: PhotoAssetRef, thumbnailSize: Int) async -> AssetAnalysisFeatures? {
        let size = CGSize(width: thumbnailSize, height: thumbnailSize)
        guard
            let image = await thumbnailService.thumbnail(
                for: asset.localIdentifier,
                targetSize: size,
                contentMode: .aspectFit
            ),
            let cgImage = image.normalizedCGImage
        else {
            return nil
        }

        guard
            let hashPixels = Self.makeGrayscalePixels(from: cgImage, width: 9, height: 8),
            let sharpnessPixels = Self.makeGrayscalePixels(from: cgImage, width: 64, height: 64)
        else {
            return nil
        }

        let perceptualHash = Self.differenceHash(pixels: hashPixels, width: 9, height: 8)
        let sharpness = Self.estimateSharpness(pixels: sharpnessPixels, width: 64, height: 64)
        let luminanceStats = Self.luminanceStats(pixels: sharpnessPixels)
        let faceSignals = Self.detectFaces(in: cgImage)
        let saliencyScore = Self.computeSaliencyScore(for: cgImage)
        let featurePrint = Self.computeVisionFeaturePrint(for: cgImage)

        return AssetAnalysisFeatures(
            asset: asset,
            perceptualHash: perceptualHash,
            sharpness: sharpness,
            faceCount: faceSignals.count,
            faceAreaRatio: faceSignals.areaRatio,
            faceCentering: faceSignals.centering,
            luminanceMean: luminanceStats.mean,
            luminanceContrast: luminanceStats.contrast,
            saliencyScore: saliencyScore,
            visionFeaturePrint: featurePrint
        )
    }

    private static func makeGrayscalePixels(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drewSuccessfully = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard
                let baseAddress = rawBuffer.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return drewSuccessfully ? pixels : nil
    }

    private static func differenceHash(pixels: [UInt8], width: Int, height: Int) -> UInt64 {
        precondition(width == 9 && height == 8)
        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0

        for y in 0 ..< height {
            for x in 0 ..< (width - 1) {
                let left = pixels[(y * width) + x]
                let right = pixels[(y * width) + x + 1]
                if left > right {
                    hash |= (1 << bitIndex)
                }
                bitIndex += 1
            }
        }

        return hash
    }

    private static func estimateSharpness(pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 1, height > 1 else { return 0 }

        var total: Double = 0
        var samples: Double = 0

        for y in 1 ..< height {
            for x in 1 ..< width {
                let current = Double(pixels[(y * width) + x])
                let left = Double(pixels[(y * width) + (x - 1)])
                let top = Double(pixels[((y - 1) * width) + x])
                let dx = abs(current - left)
                let dy = abs(current - top)
                total += (dx + dy)
                samples += 1
            }
        }

        guard samples > 0 else { return 0 }
        return min(1, (total / samples) / 255)
    }

    private static func luminanceStats(pixels: [UInt8]) -> (mean: Double, contrast: Double) {
        guard !pixels.isEmpty else { return (0, 0) }

        let normalized = pixels.map { Double($0) / 255.0 }
        let mean = normalized.reduce(0, +) / Double(normalized.count)
        let variance = normalized.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(normalized.count)

        let stddev = sqrt(max(0, variance))
        let normalizedContrast = min(1, stddev / 0.5)
        return (mean, normalizedContrast)
    }

    private static func detectFaces(in image: CGImage) -> (count: Int, areaRatio: Double, centering: Double) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            let faces = request.results ?? []
            guard !faces.isEmpty else {
                return (0, 0, 0)
            }

            var totalArea = 0.0
            var weightedCentering = 0.0
            let maxDistance = sqrt(0.5 * 0.5 + 0.5 * 0.5)

            for face in faces {
                let area = Double(face.boundingBox.width * face.boundingBox.height)
                totalArea += area

                let dx = Double(face.boundingBox.midX - 0.5)
                let dy = Double(face.boundingBox.midY - 0.5)
                let distance = sqrt((dx * dx) + (dy * dy))
                let centeredness = max(0, 1 - min(1, distance / maxDistance))
                weightedCentering += centeredness * area
            }

            let centering = totalArea > 0 ? weightedCentering / totalArea : 0
            return (faces.count, min(1, totalArea), centering)
        } catch {
            return (0, 0, 0)
        }
    }

    private static func computeSaliencyScore(for image: CGImage) -> Double {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard
                let observation = request.results?.first as? VNSaliencyImageObservation,
                let salientObjects = observation.salientObjects,
                !salientObjects.isEmpty
            else {
                return 0
            }

            let maxArea = salientObjects.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
            let bestConfidence = salientObjects.map { Double($0.confidence) }.max() ?? 0
            let areaContribution = min(1, maxArea / 0.4)
            return min(1, (bestConfidence * 0.7) + (areaContribution * 0.3))
        } catch {
            return 0
        }
    }

    private static func computeVisionFeaturePrint(for image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }
}

private extension UIImage {
    var normalizedCGImage: CGImage? {
        if let cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return normalized.cgImage
    }
}
