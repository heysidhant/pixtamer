import Foundation

enum SubfolderResolver {
    /// Single path component for the output subfolder, or nil when files go directly into the
    /// destination.
    static func component(rule: SubfolderRule, format: OutputFormat, outputWidth: Int) -> String? {
        switch rule.mode {
        case .none:
            return nil
        case .format:
            return format.fileExtension
        case .width:
            return "\(outputWidth)w"
        case .custom:
            let trimmed = rule.customName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return FilenameRenderer.sanitize(trimmed, webSafe: false)
        }
    }

    static func errors(rule: SubfolderRule) -> [String] {
        guard rule.mode == .custom else { return [] }
        let trimmed = rule.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ["Enter a subfolder name."] }
        if trimmed.contains("/") || trimmed.contains(":") || trimmed == "." || trimmed == ".." {
            return ["Subfolder name must be a single folder name without / or :."]
        }
        return []
    }
}
