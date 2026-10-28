import CoreGraphics
import Foundation
import ImageIO

/// What this Mac can actually read and write, discovered at runtime.
///
/// A format is offered for export only if its encoder exists *and* a probe image survives an
/// encode → decode round trip with the right type, size and transparency.
public struct FormatCapabilities: Hashable, Sendable {
    public struct Probe: Hashable, Sendable {
        public let format: OutputFormat
        public let available: Bool
        public let encoderName: String
        public let detail: String
    }

    public let probes: [Probe]
    /// Image I/O type identifiers Pixtamer accepts as input on this Mac.
    public let readableTypeIdentifiers: Set<String>

    public var availableFormats: [OutputFormat] {
        probes.filter(\.available).map(\.format)
    }

    public func isAvailable(_ format: OutputFormat) -> Bool {
        availableFormats.contains(format)
    }

    public init(probes: [Probe], readableTypeIdentifiers: Set<String>) {
        self.probes = probes
        self.readableTypeIdentifiers = readableTypeIdentifiers
    }

    /// Input types Pixtamer is designed for. RAW, PSD, PDF, EXR, DICOM and similar are excluded
    /// even when Image I/O can read them: they need workflows (development, layers, HDR) out of
    /// scope for v1.
    public static let supportedInputTypes: [String: String] = [
        "public.jpeg": "JPEG",
        "public.png": "PNG",
        "public.heic": "HEIC",
        "public.heif": "HEIF",
        "org.webmproject.webp": "WebP",
        "public.avif": "AVIF",
        "public.tiff": "TIFF",
        "com.compuserve.gif": "GIF",
        "com.microsoft.bmp": "BMP",
        "public.jpeg-xl": "JPEG XL",
    ]

    /// Probes every format on `BlockingWorkQueue`. Use this from async code.
    public static func detected(registry: EncoderRegistry = .standard) async -> FormatCapabilities {
        await BlockingWorkQueue.shared.run { detect(registry: registry) }
    }

    /// Probes every format on the current thread. Blocking and it encodes images, so never call it
    /// on the main thread or Swift's cooperative pool (see `BlockingWorkQueue`).
    public static func detect(registry: EncoderRegistry = .standard) -> FormatCapabilities {
        let readable = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let probes = OutputFormat.allCases.map { probe($0, registry: registry, systemWritable: writable, systemReadable: readable) }
        return FormatCapabilities(
            probes: probes,
            readableTypeIdentifiers: readable.intersection(supportedInputTypes.keys)
        )
    }

    static func probe(_ format: OutputFormat, registry: EncoderRegistry, systemWritable: Set<String>, systemReadable: Set<String>) -> Probe {
        let encoderName = format == .webp ? "libwebp \(WebPEncoder.libraryVersion) (bundled)" : "Apple Image I/O"
        func result(_ ok: Bool, _ detail: String) -> Probe {
            Probe(format: format, available: ok, encoderName: encoderName, detail: detail)
        }
        guard let encoder = registry.encoder(for: format) else { return result(false, "No encoder in this build.") }
        if encoder is ImageIOEncoder && !systemWritable.contains(format.typeIdentifier) {
            return result(false, "This version of macOS can’t write \(format.displayName).")
        }
        guard systemReadable.contains(format.typeIdentifier) else {
            return result(false, "This version of macOS can’t read \(format.displayName), so outputs can’t be verified.")
        }
        guard let image = probeImage() else { return result(false, "Probe image could not be created.") }
        let data: Data
        do {
            data = try encoder.encode(image, options: EncodeOptions(quality: 80))
        } catch {
            return result(false, "Probe encode failed: \(error.message)")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == format.typeIdentifier,
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              decoded.width == image.width, decoded.height == image.height else {
            return result(false, "Probe output did not decode correctly.")
        }
        if format.supportsTransparency && !decoded.hasAlphaChannel {
            return result(false, "Probe output lost transparency.")
        }
        return result(true, "Verified by encode/decode probe.")
    }

    /// 16×16 image, left half opaque colour, right half transparent.
    static func probeImage() -> CGImage? {
        guard let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: 16, height: 16))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        return context.makeImage()
    }
}
