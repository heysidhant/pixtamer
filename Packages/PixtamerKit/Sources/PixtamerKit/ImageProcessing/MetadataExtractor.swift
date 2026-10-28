import Foundation
import ImageIO

/// Builds the property dictionary passed to the encoder according to the metadata policy.
enum MetadataExtractor {
    static func properties(from source: CGImageSource, policy: MetadataPolicy) -> MetadataProperties? {
        guard policy != .strip,
              let all = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }

        var copied: [CFString: Any] = [:]
        var blocks: [CFString] = [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary]
        if policy == .keepAll { blocks.append(kCGImagePropertyGPSDictionary) }

        for key in blocks {
            guard var block = all[key] as? [CFString: Any] else { continue }
            if key == kCGImagePropertyTIFFDictionary {
                // Pixels are already rotated, so the stored orientation must become "up".
                block[kCGImagePropertyTIFFOrientation] = 1
            }
            if key == kCGImagePropertyExifDictionary {
                // Stale after resizing; Image I/O writes the real dimensions.
                block.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                block.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            }
            copied[key] = block
        }
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let value = all[key] { copied[key] = value }
        }
        copied[kCGImagePropertyOrientation] = 1
        return MetadataProperties(dictionary: copied as NSDictionary)
    }
}
