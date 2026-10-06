import Foundation

#if canImport(UIKit) && canImport(AVFoundation)
import UIKit
import AVFoundation

public final class TimelineThumbnailProvider {
    private let asset: AVAsset
    private let cache = NSCache<NSString, UIImage>()
    private let generator: AVAssetImageGenerator

    public init(asset: AVAsset) {
        self.asset = asset
        self.generator = AVAssetImageGenerator(asset: asset)
        self.generator.appliesPreferredTrackTransform = true
        self.generator.maximumSize = CGSize(width: 180, height: 100)
    }

    public func thumbnail(at time: TimeInterval) async -> UIImage? {
        let key = NSString(string: String(format: "%.3f", time))
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let imageRef = try self.generator.copyCGImage(at: cmTime, actualTime: nil)
                    let image = UIImage(cgImage: imageRef)
                    self.cache.setObject(image, forKey: key)
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func thumbnails(for times: [TimeInterval]) async -> [UIImage?] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, time) in times.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, nil) }
                    return (index, await self.thumbnail(at: time))
                }
            }

            var result = Array<UIImage?>(repeating: nil, count: times.count)
            for await (index, image) in group {
                result[index] = image
            }
            return result
        }
    }
}
#endif
