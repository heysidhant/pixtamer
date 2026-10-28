import Foundation

extension ExportSettings {
    /// Short recipe description, e.g. "WebP 80 · Fit 1600 px wide".
    public var summary: String {
        [formatSummary, resize.summary].joined(separator: " · ")
    }

    public var formatSummary: String {
        if format == .webp && webpLossless { return "WebP lossless" }
        return format.usesQuality(webpLossless: webpLossless) ? "\(format.displayName) \(effectiveQuality)" : format.displayName
    }
}

extension ResizeSettings {
    public var summary: String {
        switch mode {
        case .original:
            return "Original size"
        case .fit:
            switch (maxWidth, maxHeight) {
            case let (w?, h?): return "Fit \(w)×\(h)"
            case let (w?, nil): return "Fit \(w) px wide"
            case let (nil, h?): return "Fit \(h) px tall"
            case (nil, nil): return "Original size"
            }
        case .exact:
            return "\(exactWidth)×\(exactHeight) \(preserveAspectRatio ? "crop" : "stretch")"
        case .widths:
            let list = normalizedWidths.map(String.init).joined(separator: "/")
            return list.isEmpty ? "No widths" : "\(list) px"
        }
    }
}
