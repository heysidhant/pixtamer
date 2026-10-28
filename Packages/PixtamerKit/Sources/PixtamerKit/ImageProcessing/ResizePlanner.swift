import Foundation

/// How one output variant is drawn from the source.
public struct VariantPlan: Hashable, Sendable {
    public enum Fill: Hashable, Sendable {
        /// Output has the source's aspect ratio; the whole image is drawn.
        case whole
        /// Scale to cover the output box and crop the overflow equally from both sides.
        case cropToFill
        /// Draw the whole image into the output box, ignoring aspect ratio.
        case stretch
    }

    public let outputSize: PixelSize
    public let fill: Fill
    /// The width requested in multiple-widths mode. Used for naming and the width subfolder.
    public let requestedWidth: Int?

    public init(outputSize: PixelSize, fill: Fill = .whole, requestedWidth: Int? = nil) {
        self.outputSize = outputSize
        self.fill = fill
        self.requestedWidth = requestedWidth
    }
}

public enum SkipReason: Hashable, Sendable {
    /// Multiple-widths mode: the requested width is larger than the source.
    case wouldUpscale(requestedWidth: Int, sourceWidth: Int)
    /// Exact mode: the source is smaller than the requested box.
    case sourceSmallerThanTarget(source: PixelSize, target: PixelSize)
    /// Collision policy is Skip and the output name already exists.
    case outputExists(fileName: String)

    public var message: String {
        switch self {
        case .wouldUpscale(let requested, let source):
            "\(requested)w skipped: source is only \(source) px wide and upscaling is off."
        case .sourceSmallerThanTarget(let source, let target):
            "Skipped: source \(source) is smaller than \(target) and upscaling is off."
        case .outputExists(let name):
            "Skipped: \(name) already exists."
        }
    }
}

public enum VariantDecision: Hashable, Sendable {
    case render(VariantPlan)
    case skip(SkipReason)
}

/// Pure sizing rules. All maths is integer-exact on the constrained side and rounds the other
/// side to the nearest pixel, matching Image I/O's own thumbnail sizing.
public enum ResizePlanner {
    public static func variants(for source: PixelSize, settings: ResizeSettings) -> [VariantDecision] {
        guard source.isValid else { return [] }
        switch settings.mode {
        case .original:
            return [.render(VariantPlan(outputSize: source))]
        case .fit:
            return [.render(VariantPlan(outputSize: fitSize(source: source, maxWidth: settings.maxWidth, maxHeight: settings.maxHeight, allowUpscale: settings.allowUpscale)))]
        case .exact:
            return [exactDecision(source: source, settings: settings)]
        case .widths:
            return settings.normalizedWidths.map { width in
                if width > source.width && !settings.allowUpscale {
                    return .skip(.wouldUpscale(requestedWidth: width, sourceWidth: source.width))
                }
                return .render(VariantPlan(outputSize: sizeForWidth(width, source: source), requestedWidth: width))
            }
        }
    }

    /// Scales `source` to fit inside the optional bounds while keeping its aspect ratio.
    public static func fitSize(source: PixelSize, maxWidth: Int?, maxHeight: Int?, allowUpscale: Bool) -> PixelSize {
        let widthScale = maxWidth.map { Double($0) / Double(source.width) } ?? .infinity
        let heightScale = maxHeight.map { Double($0) / Double(source.height) } ?? .infinity
        var scale = min(widthScale, heightScale)
        if !allowUpscale { scale = min(scale, 1) }
        guard scale.isFinite, scale > 0, scale != 1 else { return source }

        if scale == widthScale, let maxWidth {
            return sizeForWidth(maxWidth, source: source)
        }
        if scale == heightScale, let maxHeight {
            let width = max(1, Int((Double(source.width) * Double(maxHeight) / Double(source.height)).rounded()))
            return PixelSize(width: width, height: maxHeight)
        }
        return PixelSize(
            width: max(1, Int((Double(source.width) * scale).rounded())),
            height: max(1, Int((Double(source.height) * scale).rounded()))
        )
    }

    public static func sizeForWidth(_ width: Int, source: PixelSize) -> PixelSize {
        let height = max(1, Int((Double(source.height) * Double(width) / Double(source.width)).rounded()))
        return PixelSize(width: width, height: height)
    }

    private static func exactDecision(source: PixelSize, settings: ResizeSettings) -> VariantDecision {
        let target = PixelSize(width: settings.exactWidth, height: settings.exactHeight)
        guard target.isValid else { return .render(VariantPlan(outputSize: source)) }
        if settings.preserveAspectRatio {
            let scale = max(Double(target.width) / Double(source.width), Double(target.height) / Double(source.height))
            if scale > 1 && !settings.allowUpscale {
                return .skip(.sourceSmallerThanTarget(source: source, target: target))
            }
            return .render(VariantPlan(outputSize: target, fill: .cropToFill))
        } else {
            if (target.width > source.width || target.height > source.height) && !settings.allowUpscale {
                return .skip(.sourceSmallerThanTarget(source: source, target: target))
            }
            return .render(VariantPlan(outputSize: target, fill: .stretch))
        }
    }
}
