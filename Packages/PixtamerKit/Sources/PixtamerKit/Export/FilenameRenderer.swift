import Foundation

/// Values available to filename templates.
public struct FilenameContext: Hashable, Sendable {
    public var name: String
    public var width: Int
    public var height: Int
    public var format: OutputFormat
    /// 1-based position of the source in the batch.
    public var index: Int
    /// Number of sources in the batch; used to zero-pad `{index}`.
    public var total: Int

    public init(name: String, width: Int, height: Int, format: OutputFormat, index: Int = 1, total: Int = 1) {
        self.name = name
        self.width = width
        self.height = height
        self.format = format
        self.index = index
        self.total = total
    }
}

public enum FilenameToken: String, CaseIterable, Sendable {
    case name, width, height, format, index

    public var placeholder: String { "{\(rawValue)}" }

    public var help: String {
        switch self {
        case .name: "Source file name without extension"
        case .width: "Output width in pixels"
        case .height: "Output height in pixels"
        case .format: "Output format, e.g. webp"
        case .index: "Position in the batch, zero-padded"
        }
    }
}

public enum FilenameRenderer {
    public static let maxBaseNameBytes = 200
    static let fallbackName = "image"

    /// Full output file name, including extension, after sanitisation.
    public static func fileName(rule: FilenameRule, context: FilenameContext, multipleWidths: Bool) -> String {
        let base = sanitize(rawBaseName(rule: rule, context: context, multipleWidths: multipleWidths), webSafe: rule.webSafe)
        return base + "." + context.format.fileExtension
    }

    /// Base name before sanitisation.
    static func rawBaseName(rule: FilenameRule, context: FilenameContext, multipleWidths: Bool) -> String {
        let widthSuffix = multipleWidths ? "-\(context.width)w" : ""
        switch rule.mode {
        case .original:
            return context.name + widthSuffix
        case .suffix:
            return context.name + rule.suffix + widthSuffix
        case .template:
            return expand(template: rule.template, context: context)
        }
    }

    static func expand(template: String, context: FilenameContext) -> String {
        let indexDigits = max(2, String(max(context.total, 1)).count)
        let indexText = String(repeating: "0", count: max(0, indexDigits - String(context.index).count)) + String(context.index)
        let values: [FilenameToken: String] = [
            .name: context.name,
            .width: String(context.width),
            .height: String(context.height),
            .format: context.format.fileExtension,
            .index: indexText,
        ]
        // Single pass, so a source name that itself contains "{width}" is never expanded twice.
        var result = ""
        var pending: String?
        for character in template {
            if character == "{" {
                if let pending { result += "{" + pending }
                pending = ""
            } else if character == "}", let name = pending {
                if let token = FilenameToken(rawValue: name), let value = values[token] {
                    result += value
                } else {
                    result += "{" + name + "}"
                }
                pending = nil
            } else if pending != nil {
                pending?.append(character)
            } else {
                result.append(character)
            }
        }
        if let pending { result += "{" + pending }
        return result
    }

    /// Problems that make a template unusable. Empty when valid.
    public static func templateErrors(_ template: String, multipleWidths: Bool) -> [String] {
        var errors: [String] = []
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ["Enter a template, for example {name}-{width}w."]
        }
        if template.contains("/") || template.contains(":") || template.contains("\\") {
            errors.append("Templates can’t contain / : or \\. Use the Subfolder option to organise files.")
        }
        var unknown: [String] = []
        var depth = 0
        var current = ""
        for character in template {
            switch character {
            case "{":
                if depth > 0 { errors.append("Unbalanced braces in template."); return errors }
                depth = 1
                current = ""
            case "}":
                if depth == 0 { errors.append("Unbalanced braces in template."); return errors }
                depth = 0
                if FilenameToken(rawValue: current) == nil { unknown.append("{\(current)}") }
            default:
                if depth > 0 { current.append(character) }
            }
        }
        if depth > 0 { errors.append("Unbalanced braces in template.") }
        if !unknown.isEmpty {
            let available = FilenameToken.allCases.map(\.placeholder).joined(separator: " ")
            errors.append("Unknown token \(unknown.joined(separator: ", ")). Available: \(available)")
        }
        if multipleWidths && !template.contains(FilenameToken.width.placeholder) {
            errors.append("Include {width} so each width gets its own file name.")
        }
        return errors
    }

    /// Warnings that do not block export.
    public static func templateWarnings(_ template: String) -> [String] {
        if !template.contains(FilenameToken.name.placeholder) && !template.contains(FilenameToken.index.placeholder) {
            return ["Without {name} or {index}, outputs from different images share a name and get numbered."]
        }
        return []
    }

    /// Makes a string safe as a single file-name component.
    ///
    /// - Always: removes path separators, control and Windows-reserved characters, leading dots
    ///   (no hidden files), trailing dots/spaces, and limits length to `maxBaseNameBytes` UTF-8 bytes.
    /// - Web-safe: transliterates to Latin, strips accents, lowercases and joins words with hyphens.
    public static func sanitize(_ input: String, webSafe: Bool) -> String {
        var text = input.precomposedStringWithCanonicalMapping

        if webSafe {
            text = text.applyingTransform(.toLatin, reverse: false) ?? text
            text = text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            text = text.lowercased()
            let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
            text = String(text.map { allowed.contains($0) ? $0 : "-" })
            text = collapse(text, character: "-")
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        } else {
            let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
            // A run of forbidden characters becomes a single hyphen; the user's own hyphens stay.
            var scalars = String.UnicodeScalarView()
            var replacing = false
            for scalar in text.unicodeScalars {
                if forbidden.contains(scalar) {
                    if !replacing { scalars.append("-") }
                    replacing = true
                } else {
                    scalars.append(scalar)
                    replacing = false
                }
            }
            text = String(scalars)
            text = collapse(text, character: " ")
            text = text.trimmingCharacters(in: .whitespaces)
        }

        while text.hasPrefix(".") { text.removeFirst() }
        while text.hasSuffix(".") || text.hasSuffix(" ") { text.removeLast() }

        text = truncate(text, maxBytes: maxBaseNameBytes)
        if text.isEmpty || text == "." || text == ".." { return fallbackName }
        return text
    }

    private static func collapse(_ text: String, character: Character) -> String {
        var result = ""
        var previous: Character?
        for c in text {
            if c == character && previous == character { continue }
            result.append(c)
            previous = c
        }
        return result
    }

    private static func truncate(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var result = ""
        for character in text {
            if result.utf8.count + String(character).utf8.count > maxBytes { break }
            result.append(character)
        }
        return result
    }
}
