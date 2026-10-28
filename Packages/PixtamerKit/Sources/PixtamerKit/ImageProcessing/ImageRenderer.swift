import CoreGraphics
import Foundation
import ImageIO

/// Produces the final 8-bit pixels for one output variant.
///
/// Decoding goes through `CGImageSourceCreateThumbnailAtIndex`, which applies EXIF orientation
/// and downsamples while decoding, so a 6000 px JPEG headed for 960 px never needs a full-size
/// bitmap. The result is always redrawn into a known RGB pixel format so encoders get
/// predictable input (CMYK, greyscale and 16-bit sources become 8-bit RGB).
enum ImageRenderer {
    static func render(source: CGImageSource, sourceSize: PixelSize, plan: VariantPlan, format: OutputFormat) throws(ExportFailure) -> CGImage {
        let output = plan.outputSize
        guard output.isValid else { throw ExportFailure(.decodeFailed, "Invalid output size \(output).") }
        if output.width > format.maxDimension || output.height > format.maxDimension {
            throw ExportFailure(.dimensionsTooLarge, "\(format.displayName) supports up to \(format.maxDimension) px on each side; this output would be \(output).")
        }

        let drawRect = drawRect(source: sourceSize, plan: plan)
        let neededLongSide = Int(max(drawRect.width, drawRect.height).rounded(.up))
        let decodeLongSide = max(1, min(neededLongSide, sourceSize.longSide))

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeLongSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ExportFailure(.decodeFailed, "The image data could not be decoded. The file may be damaged.")
        }

        let keepAlpha = format.supportsTransparency && decoded.hasAlphaChannel
        guard let context = makeContext(size: output, preferredSpace: decoded.colorSpace, format: format, alpha: keepAlpha) else {
            throw ExportFailure(.decodeFailed, "Not enough memory to render a \(output) image.")
        }
        if !keepAlpha {
            // JPEG has no transparency: composite onto white rather than the black CG would use.
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: output.cgSize))
        }
        context.interpolationQuality = .high
        context.draw(decoded, in: drawRect)
        guard let rendered = context.makeImage() else {
            throw ExportFailure(.decodeFailed, "Rendering the resized image failed.")
        }
        return rendered
    }

    /// Where the decoded image is drawn inside the output canvas (CG coordinates).
    static func drawRect(source: PixelSize, plan: VariantPlan) -> CGRect {
        let output = plan.outputSize.cgSize
        switch plan.fill {
        case .whole, .stretch:
            return CGRect(origin: .zero, size: output)
        case .cropToFill:
            let scale = max(output.width / CGFloat(source.width), output.height / CGFloat(source.height))
            let size = CGSize(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
            return CGRect(x: (output.width - size.width) / 2, y: (output.height - size.height) / 2, width: size.width, height: size.height)
        }
    }

    /// Keeps the source's RGB colour space (so its ICC profile is embedded by Image I/O) except for
    /// WebP, whose encoder cannot embed a profile and therefore gets sRGB pixels.
    static func outputColorSpace(preferred: CGColorSpace?, format: OutputFormat) -> CGColorSpace {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard format != .webp, let preferred, preferred.model == .rgb, preferred.supportsOutput else { return sRGB }
        return preferred
    }

    private static func makeContext(size: PixelSize, preferredSpace: CGColorSpace?, format: OutputFormat, alpha: Bool) -> CGContext? {
        let bitmapInfo = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let space = outputColorSpace(preferred: preferredSpace, format: format)
        if let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) {
            return context
        }
        // Some wide-gamut/HDR spaces cannot back an 8-bit context; fall back to sRGB.
        return CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo)
    }
}

extension CGImage {
    var hasAlphaChannel: Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo)
    }
}
