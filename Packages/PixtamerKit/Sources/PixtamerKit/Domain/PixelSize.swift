import CoreGraphics

/// Integer pixel dimensions, always in display orientation (EXIF orientation already applied).
public struct PixelSize: Codable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var longSide: Int { max(width, height) }
    public var isValid: Bool { width > 0 && height > 0 }
    public var pixelCount: Int { width * height }
    public var description: String { "\(width)×\(height)" }
    var cgSize: CGSize { CGSize(width: width, height: height) }
}
