import AVFoundation
import FossifyCommons
import Foundation
import ImageIO
import Photos
import UIKit

/// Glide/Picasso stand-in: async wrappers around PHImageManager.
enum ImageLoader {
    static var manager: PHImageManager { PHImageManager.default() }

    static func deliveryMode(_ p: LoadingPriority) -> PHImageRequestOptionsDeliveryMode {
        switch p {
        case .speed: return .opportunistic
        case .compromise: return .highQualityFormat
        case .validity: return .highQualityFormat
        }
    }

    /// Original image data (for GIF animation, EXIF, editing).
    static func data(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.version = .current
            o.deliveryMode = .highQualityFormat
            manager.requestImageDataAndOrientation(for: asset, options: o) { data, _, _, _ in
                cont.resume(returning: data)
            }
        }
    }

    /// A single image of at least `size` points (PHImageManagerMaximumSize for the original).
    static func image(for asset: PHAsset, size: CGSize, contentMode: PHImageContentMode = .aspectFit) async -> UIImage? {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .highQualityFormat
            o.resizeMode = .fast
            manager.requestImage(for: asset, targetSize: size, contentMode: contentMode, options: o) { image, _ in
                cont.resume(returning: image)
            }
        }
    }

    static func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        await withCheckedContinuation { cont in
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .automatic
            manager.requestPlayerItem(forVideo: asset, options: o) { item, _ in
                cont.resume(returning: item)
            }
        }
    }

    static func avAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { cont in
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = true
            o.version = .current
            manager.requestAVAsset(forVideo: asset, options: o) { av, _, _ in
                cont.resume(returning: av)
            }
        }
    }

    /// Animated UIImage from GIF data (ImageIO frames with their delays).
    static func animatedImage(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += delay < 0.011 ? 0.1 : delay
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    /// File URL of the original for sharing / printing (exported into the temp folder).
    static func exportedFile(for m: Medium) async -> URL? {
        let resources = PHAssetResource.assetResources(for: m.asset)
        guard let r = resources.first(where: { [.photo, .video, .fullSizePhoto, .fullSizeVideo].contains($0.type) }) ?? resources.first else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(r.originalFilename)
        let o = PHAssetResourceRequestOptions()
        o.isNetworkAccessAllowed = true
        return await withCheckedContinuation { cont in
            PHAssetResourceManager.default().writeData(for: r, toFile: url, options: o) { error in
                cont.resume(returning: error == nil ? url : nil)
            }
        }
    }
}

/// ExifInterface reads used by the properties dialog and extended details.
enum Exif {
    static func properties(_ data: Data) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func dateTaken(_ data: Data) -> Date? {
        let exif = properties(data)[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard let s = exif?[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: s)
    }

    /// ExifInterface.getExifCameraModel(): "<make> <model>".
    static func cameraModel(_ props: [CFString: Any]) -> String {
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let make = (tiff?[kCGImagePropertyTIFFMake] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if make.isEmpty && model.isEmpty { return "" }
        return model.hasPrefix(make) ? model : "\(make) \(model)".trimmingCharacters(in: .whitespaces)
    }

    /// ExifInterface.getExifProperties(): "F/1.8  26mm  1/120s  ISO-50".
    static func exifProperties(_ props: [CFString: Any]) -> String {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var parts: [String] = []
        if let f = exif[kCGImagePropertyExifFNumber] as? Double { parts.append("F/\(trim(f))") }
        if let fl = exif[kCGImagePropertyExifFocalLength] as? Double { parts.append("\(trim(fl))mm") }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            parts.append(t < 1 ? "1/\(Int((1 / t).rounded()))s" : "\(trim(t))s")
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { parts.append("ISO-\(iso)") }
        return parts.joined(separator: "  ")
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}
