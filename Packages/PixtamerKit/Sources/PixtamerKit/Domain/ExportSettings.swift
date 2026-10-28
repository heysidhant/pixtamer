import Foundation

/// One export recipe. Stored in presets and preferences, so every field decodes with a default
/// to keep older or newer files readable.
public struct ExportSettings: Codable, Hashable, Sendable {
    public static let qualityRange = 1...100
    public static let defaultQuality = 80

    public var format: OutputFormat
    /// 1–100. Used only when `format.usesQuality(webpLossless:)` is true.
    public var quality: Int
    public var webpLossless: Bool
    public var resize: ResizeSettings
    public var naming: FilenameRule
    public var subfolder: SubfolderRule
    public var metadata: MetadataPolicy
    public var collisionPolicy: CollisionPolicy

    public init(
        format: OutputFormat = .webp,
        quality: Int = ExportSettings.defaultQuality,
        webpLossless: Bool = false,
        resize: ResizeSettings = ResizeSettings(),
        naming: FilenameRule = FilenameRule(),
        subfolder: SubfolderRule = SubfolderRule(),
        metadata: MetadataPolicy = .strip,
        collisionPolicy: CollisionPolicy = .rename
    ) {
        self.format = format
        self.quality = quality
        self.webpLossless = webpLossless
        self.resize = resize
        self.naming = naming
        self.subfolder = subfolder
        self.metadata = metadata
        self.collisionPolicy = collisionPolicy
    }

    /// Quality clamped to the valid range.
    public var effectiveQuality: Int {
        min(max(quality, Self.qualityRange.lowerBound), Self.qualityRange.upperBound)
    }

    /// Metadata policy after accounting for formats that cannot carry metadata.
    public var effectiveMetadata: MetadataPolicy {
        format.supportsMetadata ? metadata : .strip
    }

    enum CodingKeys: String, CodingKey {
        case format, quality, webpLossless, resize, naming, subfolder, metadata, collisionPolicy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportSettings()
        format = c.decode(.format, default: d.format)
        quality = c.decode(.quality, default: d.quality)
        webpLossless = c.decode(.webpLossless, default: d.webpLossless)
        resize = c.decode(.resize, default: d.resize)
        naming = c.decode(.naming, default: d.naming)
        subfolder = c.decode(.subfolder, default: d.subfolder)
        metadata = c.decode(.metadata, default: d.metadata)
        collisionPolicy = c.decode(.collisionPolicy, default: d.collisionPolicy)
    }
}

// MARK: - Resize

public struct ResizeSettings: Codable, Hashable, Sendable {
    public static let maxRequestedDimension = 16_384

    public enum Mode: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Keep source pixel dimensions.
        case original
        /// Scale down to fit within a maximum width and/or height. Aspect ratio is always kept.
        case fit
        /// Produce exactly `exactWidth × exactHeight`, either cropping or stretching.
        case exact
        /// One output per width in `widths`. Aspect ratio is always kept.
        case widths

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .original: "Original size"
            case .fit: "Fit within"
            case .exact: "Exact size"
            case .widths: "Multiple widths"
            }
        }
    }

    public var mode: Mode
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var exactWidth: Int
    public var exactHeight: Int
    /// Exact mode only. `true` scales to cover the box and crops the overflow from the centre.
    /// `false` stretches the image to the box, ignoring its aspect ratio.
    public var preserveAspectRatio: Bool
    public var widths: [Int]
    /// When false (the default) outputs are never larger than the source.
    public var allowUpscale: Bool

    public init(
        mode: Mode = .original,
        maxWidth: Int? = 1600,
        maxHeight: Int? = nil,
        exactWidth: Int = 1200,
        exactHeight: Int = 1200,
        preserveAspectRatio: Bool = true,
        widths: [Int] = [480, 960, 1440],
        allowUpscale: Bool = false
    ) {
        self.mode = mode
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.exactWidth = exactWidth
        self.exactHeight = exactHeight
        self.preserveAspectRatio = preserveAspectRatio
        self.widths = widths
        self.allowUpscale = allowUpscale
    }

    /// Widths that will actually be used: positive, within limits, de-duplicated and ascending.
    public var normalizedWidths: [Int] {
        Array(Set(widths.filter { (1...Self.maxRequestedDimension).contains($0) })).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case mode, maxWidth, maxHeight, exactWidth, exactHeight, preserveAspectRatio, widths, allowUpscale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ResizeSettings()
        mode = c.decode(.mode, default: d.mode)
        maxWidth = c.decode(.maxWidth, default: nil)
        maxHeight = c.decode(.maxHeight, default: nil)
        exactWidth = c.decode(.exactWidth, default: d.exactWidth)
        exactHeight = c.decode(.exactHeight, default: d.exactHeight)
        preserveAspectRatio = c.decode(.preserveAspectRatio, default: d.preserveAspectRatio)
        widths = c.decode(.widths, default: d.widths)
        allowUpscale = c.decode(.allowUpscale, default: d.allowUpscale)
    }
}

// MARK: - Naming

public struct FilenameRule: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable, Identifiable {
        case original
        case suffix
        case template

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .original: "Original name"
            case .suffix: "Add suffix"
            case .template: "Template"
            }
        }
    }

    public var mode: Mode
    public var suffix: String
    public var template: String
    /// Lowercase, ASCII-only, hyphen-separated names that are safe in URLs.
    public var webSafe: Bool

    public init(mode: Mode = .original, suffix: String = "-web", template: String = "{name}-{width}w", webSafe: Bool = true) {
        self.mode = mode
        self.suffix = suffix
        self.template = template
        self.webSafe = webSafe
    }

    enum CodingKeys: String, CodingKey { case mode, suffix, template, webSafe }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FilenameRule()
        mode = c.decode(.mode, default: d.mode)
        suffix = c.decode(.suffix, default: d.suffix)
        template = c.decode(.template, default: d.template)
        webSafe = c.decode(.webSafe, default: d.webSafe)
    }
}

public struct SubfolderRule: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable, Identifiable {
        case none
        case format
        case width
        case custom

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .none: "None"
            case .format: "By format (webp/)"
            case .width: "By width (960w/)"
            case .custom: "Custom name"
            }
        }
    }

    public var mode: Mode
    public var customName: String

    public init(mode: Mode = .none, customName: String = "web") {
        self.mode = mode
        self.customName = customName
    }

    enum CodingKeys: String, CodingKey { case mode, customName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SubfolderRule()
        mode = c.decode(.mode, default: d.mode)
        customName = c.decode(.customName, default: d.customName)
    }
}

// MARK: - Policies

public enum CollisionPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Add a number (`photo-1.webp`) so nothing is replaced. Default.
    case rename
    /// Leave the existing file and report the output as skipped.
    case skip
    /// Replace an existing output file. Source images are never replaced.
    case replace

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rename: "Keep both (add number)"
        case .skip: "Skip"
        case .replace: "Replace existing file"
        }
    }

    public var explanation: String {
        switch self {
        case .rename: "If a file with the same name exists, a number is added, e.g. photo-1.webp."
        case .skip: "If a file with the same name exists, that output is skipped and reported."
        case .replace: "Existing files with the same name are replaced. Source images are never replaced."
        }
    }
}

public enum MetadataPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Write no EXIF/IPTC/GPS. The colour profile is kept (except WebP, which is converted to sRGB).
    case strip
    /// Copy EXIF, TIFF and IPTC; drop the GPS block.
    case keepWithoutLocation
    /// Copy EXIF, TIFF, IPTC and GPS.
    case keepAll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strip: "Remove metadata"
        case .keepWithoutLocation: "Keep, remove GPS location"
        case .keepAll: "Keep all metadata"
        }
    }

    public var explanation: String {
        switch self {
        case .strip: "Removes camera, copyright and GPS data. Smallest files; recommended for the web."
        case .keepWithoutLocation: "Keeps camera, copyright and caption data. Removes the GPS block."
        case .keepAll: "Keeps EXIF, IPTC and GPS location data. Location can reveal where a photo was taken."
        }
    }
}
