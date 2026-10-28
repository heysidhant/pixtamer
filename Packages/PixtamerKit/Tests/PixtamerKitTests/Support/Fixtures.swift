import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
@testable import PixtamerKit

/// Generates image fixtures on disk. Every test gets its own temporary directory.
final class FixtureDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixtamerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func subdirectory(_ name: String) throws -> URL {
        let sub = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        return sub
    }

    /// Colourful opaque test pattern.
    @discardableResult
    func jpeg(_ name: String, width: Int, height: Int, quality: Double = 0.9, orientation: Int? = nil, properties: [CFString: Any] = [:], in dir: URL? = nil) throws -> URL {
        var props = properties
        props[kCGImageDestinationLossyCompressionQuality] = quality
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        return try write(Fixtures.pattern(width: width, height: height, alpha: false), name: name, type: "public.jpeg", properties: props, in: dir)
    }

    /// Left half opaque pattern, right half fully transparent.
    @discardableResult
    func transparentPNG(_ name: String, width: Int, height: Int, in dir: URL? = nil) throws -> URL {
        try write(Fixtures.pattern(width: width, height: height, alpha: true), name: name, type: "public.png", properties: [:], in: dir)
    }

    @discardableResult
    func png(_ name: String, image: CGImage, in dir: URL? = nil) throws -> URL {
        try write(image, name: name, type: "public.png", properties: [:], in: dir)
    }

    @discardableResult
    func file(_ name: String, bytes: [UInt8], in dir: URL? = nil) throws -> URL {
        let target = (dir ?? url).appendingPathComponent(name)
        try Data(bytes).write(to: target)
        return target
    }

    @discardableResult
    func write(_ image: CGImage, name: String, type: String, properties: [CFString: Any], in dir: URL? = nil) throws -> URL {
        let target = (dir ?? url).appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, type as CFString, 1, nil) else {
            throw FixtureError.cannotCreate(type)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.cannotCreate(type) }
        return target
    }

    func contents(_ dir: URL? = nil, includeHidden: Bool = false) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: (dir ?? url).path)
            .filter { includeHidden || !$0.hasPrefix(".") }
            .sorted()
    }
}

enum FixtureError: Error { case cannotCreate(String) }

enum Fixtures {
    static func pattern(width: Int, height: Int, alpha: Bool, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: info)!
        let cell = max(1, min(width, height) / 12)
        for y in stride(from: 0, to: height, by: cell) {
            for x in stride(from: 0, to: width, by: cell) {
                context.setFillColor(CGColor(
                    red: CGFloat(x) / CGFloat(width),
                    green: CGFloat(y) / CGFloat(height),
                    blue: CGFloat((x / cell + y / cell) % 3) / 2,
                    alpha: 1
                ))
                context.fill(CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
        if alpha {
            context.clear(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        return context.makeImage()!
    }

    static func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat, colorSpace: CGColorSpace) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [red, green, blue, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func type(_ url: URL) -> String? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    static func pixelSize(_ url: URL) -> PixelSize? {
        let p = properties(url)
        guard let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return PixelSize(width: w, height: h)
    }

    /// RGBA (straight 0–255) of a pixel, measured from the top-left in display orientation.
    /// Decodes on `BlockingWorkQueue`, because AVIF decoding must not block cooperative threads.
    static func rgba(_ url: URL, x: Int, y: Int) async -> [UInt8]? {
        await BlockingWorkQueue.shared.run { rgbaOnCurrentThread(url, x: x, y: y) }
    }

    static func rgbaOnCurrentThread(_ url: URL, x: Int, y: Int) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 100_000,
              ] as CFDictionary) else { return nil }
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let p = context.data!.assumingMemoryBound(to: UInt8.self)
        let i = (y * image.width + x) * 4
        return [p[i], p[i + 1], p[i + 2], p[i + 3]]
    }

    static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? -1
    }

    /// Input types from Image I/O's reader list only. Deliberately *not* `FormatCapabilities.detect()`:
    /// running the encode probes inside a static initialiser that every parallel test waits on
    /// blocks the whole cooperative pool (see BlockingWorkQueue). Tests that need the full probe
    /// call `detect()` themselves.
    static let inspector: ImageInspector = {
        let readable = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        return ImageInspector(readableTypes: FormatCapabilities.supportedInputTypes.filter { readable.contains($0.key) })
    }()

    /// Cheap check used to skip format-specific tests on Macs without a system encoder.
    static func systemCanWrite(_ format: OutputFormat) -> Bool {
        format == .webp || ((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []).contains(format.typeIdentifier)
    }

    static func input(_ url: URL) throws -> ImageInput {
        try inspector.inspect(url).get()
    }

    static func makeInput(name: String = "photo.jpg", size: PixelSize = PixelSize(width: 4000, height: 3000), bytes: Int64 = 1000, url: URL? = nil) -> ImageInput {
        ImageInput(
            url: url ?? URL(fileURLWithPath: "/tmp/src/\(name)"),
            fileName: name,
            typeIdentifier: "public.jpeg",
            typeDisplayName: "JPEG",
            pixelSize: size,
            fileSize: bytes,
            hasAlpha: false
        )
    }
}

extension Array where Element == VariantResult {
    var writtenFiles: [WrittenFile] {
        compactMap { if case .written(let file) = $0.outcome { file } else { nil } }
    }
}
