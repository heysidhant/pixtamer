import Foundation

/// Output formats Pixtamer knows how to produce. Whether a format is actually offered is decided
/// at runtime by `FormatCapabilities`; never assume a case here is usable on the current Mac.
public enum OutputFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case jpeg
    case png
    case webp
    case avif

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .webp: "WebP"
        case .avif: "AVIF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .webp: "webp"
        case .avif: "avif"
        }
    }

    /// Uniform Type Identifier used by Image I/O for reading and writing.
    public var typeIdentifier: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        case .webp: "org.webmproject.webp"
        case .avif: "public.avif"
        }
    }

    /// Whether the quality slider applies. WebP is lossy unless lossless mode is chosen.
    public func usesQuality(webpLossless: Bool) -> Bool {
        switch self {
        case .jpeg, .avif: true
        case .webp: !webpLossless
        case .png: false
        }
    }

    public var supportsTransparency: Bool { self != .jpeg }

    /// Whether EXIF/IPTC metadata can be carried into the output with the current encoders.
    public var supportsMetadata: Bool { self != .webp }

    /// Largest width or height the encoder accepts.
    public var maxDimension: Int {
        switch self {
        case .webp: 16_383
        case .jpeg: 65_500
        case .png, .avif: 32_768
        }
    }

    public var summary: String {
        switch self {
        case .jpeg: "Lossy. Best for photos. Transparent areas are filled with white."
        case .png: "Lossless. Keeps transparency. Large for photos."
        case .webp: "Lossy or lossless. Keeps transparency. Widely supported by browsers."
        case .avif: "Lossy. Keeps transparency. Often smallest, slower to encode, newer browsers only."
        }
    }
}
