import Foundation

public struct ValidationIssue: Hashable, Sendable, Identifiable {
    public enum Severity: Hashable, Sendable { case error, warning }
    public enum Field: Hashable, Sendable { case format, quality, resize, widths, naming, subfolder, metadata }

    public var id: String { "\(field)-\(message)" }
    public let field: Field
    public let severity: Severity
    public let message: String

    public init(_ field: Field, _ severity: Severity, _ message: String) {
        self.field = field
        self.severity = severity
        self.message = message
    }
}

extension ExportSettings {
    /// Checks the recipe before export. Errors block export; warnings are shown inline only.
    public func validate(availableFormats: [OutputFormat]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if !availableFormats.contains(format) {
            issues.append(.init(.format, .error, "\(format.displayName) export isn’t available on this Mac. Choose another format."))
        }

        if format.usesQuality(webpLossless: webpLossless) && !Self.qualityRange.contains(quality) {
            issues.append(.init(.quality, .error, "Quality must be between 1 and 100."))
        }

        issues += resize.validate(format: format)

        if naming.mode == .template {
            for message in FilenameRenderer.templateErrors(naming.template, multipleWidths: resize.mode == .widths) {
                issues.append(.init(.naming, .error, message))
            }
            for message in FilenameRenderer.templateWarnings(naming.template) {
                issues.append(.init(.naming, .warning, message))
            }
        }
        if naming.mode == .suffix {
            if naming.suffix.contains("/") || naming.suffix.contains(":") {
                issues.append(.init(.naming, .error, "Suffix can’t contain / or :."))
            } else if naming.suffix.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(.init(.naming, .warning, "Suffix is empty, so names match the originals."))
            }
        }

        for message in SubfolderResolver.errors(rule: subfolder) {
            issues.append(.init(.subfolder, .error, message))
        }

        if metadata != .strip && !format.supportsMetadata {
            issues.append(.init(.metadata, .warning, "\(format.displayName) export removes metadata in this version."))
        }
        return issues
    }
}

extension ResizeSettings {
    func validate(format: OutputFormat) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let limit = min(Self.maxRequestedDimension, format.maxDimension)
        func check(_ value: Int?, _ label: String, field: ValidationIssue.Field = .resize) {
            guard let value else { return }
            if value < 1 {
                issues.append(.init(field, .error, "\(label) must be at least 1 px."))
            } else if value > limit {
                issues.append(.init(field, .error, "\(label) can’t exceed \(limit) px for \(format.displayName)."))
            }
        }

        switch mode {
        case .original:
            break
        case .fit:
            check(maxWidth, "Maximum width")
            check(maxHeight, "Maximum height")
            if maxWidth == nil && maxHeight == nil {
                issues.append(.init(.resize, .warning, "No maximum set, so images keep their original size."))
            }
        case .exact:
            check(exactWidth, "Width")
            check(exactHeight, "Height")
            if !preserveAspectRatio {
                issues.append(.init(.resize, .warning, "Images with a different shape will be stretched."))
            }
        case .widths:
            if widths.isEmpty {
                issues.append(.init(.widths, .error, "Add at least one width."))
            }
            for width in widths {
                check(width, "Width \(width)", field: .widths)
            }
            if Set(widths).count != widths.count {
                issues.append(.init(.widths, .warning, "Duplicate widths are exported once."))
            }
        }
        return issues
    }
}

extension Array where Element == ValidationIssue {
    public var hasErrors: Bool { contains { $0.severity == .error } }
    public func messages(for field: ValidationIssue.Field) -> [ValidationIssue] { filter { $0.field == field } }
}
