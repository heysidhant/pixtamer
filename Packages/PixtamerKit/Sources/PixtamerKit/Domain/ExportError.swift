import Foundation

/// Failure of a single output file. Messages are actionable and name files only by their file
/// name, never by full path, so they can be copied into diagnostics.
public struct ExportFailure: Error, Hashable, Sendable {
    public enum Code: String, Hashable, Sendable, Codable {
        case sourceMissing = "PB-SRC-MISSING"
        case sourceUnreadable = "PB-SRC-UNREADABLE"
        case decodeFailed = "PB-DECODE"
        case encoderUnavailable = "PB-ENC-UNAVAILABLE"
        case encodeFailed = "PB-ENC"
        case dimensionsTooLarge = "PB-ENC-DIMENSIONS"
        case verificationFailed = "PB-VERIFY"
        case destinationUnavailable = "PB-DEST"
        case writeFailed = "PB-WRITE"
        case protectedSource = "PB-PROTECTED"
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }
}

extension ExportFailure: LocalizedError {
    public var errorDescription: String? { message }
}
