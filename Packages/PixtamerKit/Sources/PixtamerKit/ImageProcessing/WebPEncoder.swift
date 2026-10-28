import Accelerate
import CoreGraphics
import CWebP
import Foundation

/// WebP encoder using the vendored libwebp. Image I/O can read WebP but cannot write it.
///
/// libwebp's simple API does not embed ICC profiles or EXIF, so pixels are converted to sRGB
/// before encoding and metadata is always dropped.
public struct WebPEncoder: ImageEncoder {
    public let format = OutputFormat.webp
    /// libwebp effort level 0 (fast) – 6 (slowest, smallest). 4 is libwebp's own default.
    public let method: Int32

    public init(method: Int32 = 4) {
        self.method = method
    }

    public static var libraryVersion: String {
        let v = WebPGetEncoderVersion()
        return "\((v >> 16) & 0xff).\((v >> 8) & 0xff).\(v & 0xff)"
    }

    public func encode(_ image: CGImage, options: EncodeOptions) throws(ExportFailure) -> Data {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= Int(WEBP_MAX_DIMENSION), height <= Int(WEBP_MAX_DIMENSION) else {
            throw ExportFailure(.dimensionsTooLarge, "WebP supports images up to \(WEBP_MAX_DIMENSION) px on each side.")
        }
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)

        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: stride, space: space,
                    bitmapInfo: hasAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard hasAlpha else { return true }
            // libwebp expects straight (non-premultiplied) alpha.
            var buffer = vImage_Buffer(data: raw.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: stride)
            return vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        guard drawn else { throw ExportFailure(.encodeFailed, "Could not prepare pixels for WebP encoding.") }

        var config = WebPConfig()
        guard WebPConfigInitInternal(&config, WEBP_PRESET_DEFAULT, Float(options.quality), WEBP_ENCODER_ABI_VERSION) != 0 else {
            throw ExportFailure(.encoderUnavailable, "The bundled WebP encoder failed to initialise.")
        }
        config.lossless = options.lossless ? 1 : 0
        config.method = method
        if options.lossless {
            // In lossless mode quality controls effort, not fidelity.
            config.quality = 75
        }
        guard WebPValidateConfig(&config) != 0 else {
            throw ExportFailure(.encodeFailed, "Invalid WebP settings.")
        }

        var picture = WebPPicture()
        guard WebPPictureInitInternal(&picture, WEBP_ENCODER_ABI_VERSION) != 0 else {
            throw ExportFailure(.encoderUnavailable, "The bundled WebP encoder failed to initialise.")
        }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(width)
        picture.height = Int32(height)
        picture.use_argb = options.lossless ? 1 : 0

        let imported = pixels.withUnsafeBufferPointer { buffer in
            hasAlpha
                ? WebPPictureImportRGBA(&picture, buffer.baseAddress, Int32(stride))
                : WebPPictureImportRGBX(&picture, buffer.baseAddress, Int32(stride))
        }
        guard imported != 0 else { throw ExportFailure(.encodeFailed, "Not enough memory to encode this image as WebP.") }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        let ok = withUnsafeMutablePointer(to: &writer) { pointer -> Int32 in
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard ok != 0, picture.error_code == VP8_ENC_OK, writer.size > 0, let memory = writer.mem else {
            throw ExportFailure(.encodeFailed, "WebP encoding failed (libwebp error \(picture.error_code.rawValue)).")
        }
        return Data(bytes: memory, count: writer.size)
    }
}
