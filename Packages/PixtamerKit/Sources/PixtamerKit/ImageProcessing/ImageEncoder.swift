import CoreGraphics
import Foundation
import ImageIO

/// Immutable Image I/O property dictionary carried from source to output.
public struct MetadataProperties: @unchecked Sendable {
    // NSDictionary is immutable once built and only read by the encoder.
    let dictionary: NSDictionary
}

public struct EncodeOptions: Sendable {
    public var quality: Int
    public var lossless: Bool
    public var metadata: MetadataProperties?

    public init(quality: Int, lossless: Bool = false, metadata: MetadataProperties? = nil) {
        self.quality = quality
        self.lossless = lossless
        self.metadata = metadata
    }
}

/// Encodes a fully rendered 8-bit image into a file format. Implementations must be thread-safe.
public protocol ImageEncoder: Sendable {
    var format: OutputFormat { get }
    func encode(_ image: CGImage, options: EncodeOptions) throws(ExportFailure) -> Data
}

/// Encoder backed by Apple Image I/O (`CGImageDestination`).
public struct ImageIOEncoder: ImageEncoder {
    public let format: OutputFormat

    public init(format: OutputFormat) {
        self.format = format
    }

    public func encode(_ image: CGImage, options: EncodeOptions) throws(ExportFailure) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.typeIdentifier as CFString, 1, nil) else {
            throw ExportFailure(.encoderUnavailable, "\(format.displayName) encoding isn’t available on this Mac.")
        }
        let properties = options.metadata.map { NSMutableDictionary(dictionary: $0.dictionary) } ?? NSMutableDictionary()
        if format.usesQuality(webpLossless: false) {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(options.quality) / 100.0
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination), data.length > 0 else {
            throw ExportFailure(.encodeFailed, "\(format.displayName) encoder could not write this image.")
        }
        return data as Data
    }
}

/// Lookup of encoders by format.
public struct EncoderRegistry: Sendable {
    private let encoders: [OutputFormat: any ImageEncoder]

    public init(encoders: [any ImageEncoder]) {
        var map: [OutputFormat: any ImageEncoder] = [:]
        for encoder in encoders { map[encoder.format] = encoder }
        self.encoders = map
    }

    public static let standard = EncoderRegistry(encoders: [
        ImageIOEncoder(format: .jpeg),
        ImageIOEncoder(format: .png),
        ImageIOEncoder(format: .avif),
        WebPEncoder(),
    ])

    public func encoder(for format: OutputFormat) -> (any ImageEncoder)? {
        encoders[format]
    }
}
