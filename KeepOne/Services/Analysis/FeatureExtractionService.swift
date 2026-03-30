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
        let (faceCount, faceAreaRatio) = Self.detectFaces(in: cgImage)
        let featurePrint = Self.computeVisionFeaturePrint(for: cgImage)

        return AssetAnalysisFeatures(
            asset: asset,
            perceptualHash: perceptualHash,
            sharpness: sharpness,
            faceCount: faceCount,
            faceAreaRatio: faceAreaRatio,
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

    private static func detectFaces(in image: CGImage) -> (count: Int, areaRatio: Double) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            let faces = request.results ?? []
            let area = faces.reduce(0.0) { partial, face in
                partial + Double(face.boundingBox.width * face.boundingBox.height)
            }
            return (faces.count, min(1, area))
        } catch {
            return (0, 0)
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
