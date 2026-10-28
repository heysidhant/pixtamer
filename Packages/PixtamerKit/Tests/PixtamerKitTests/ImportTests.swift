import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PixtamerKit

@Suite("Import, metadata and malformed files")
struct ImportTests {
    let importer = ImageImporter(inspector: Fixtures.inspector)

    @Test func jpegMetadata() throws {
        let dir = try FixtureDirectory()
        let url = try dir.jpeg("photo.jpg", width: 640, height: 480)
        let input = try Fixtures.input(url)
        #expect(input.pixelSize == PixelSize(width: 640, height: 480))
        #expect(input.typeDisplayName == "JPEG")
        #expect(input.fileSize == Fixtures.fileSize(url))
        #expect(input.hasAlpha == false)
        #expect(input.warnings.isEmpty)
        #expect(input.baseName == "photo")
    }

    @Test func orientationSwapsDisplaySize() throws {
        let dir = try FixtureDirectory()
        let url = try dir.jpeg("rotated.jpg", width: 600, height: 400, orientation: 6)
        let input = try Fixtures.input(url)
        #expect(input.orientation == 6)
        #expect(input.pixelSize == PixelSize(width: 400, height: 600))
    }

    @Test func transparentPNG() throws {
        let dir = try FixtureDirectory()
        let input = try Fixtures.input(try dir.transparentPNG("logo.png", width: 64, height: 64))
        #expect(input.hasAlpha)
        #expect(input.typeDisplayName == "PNG")
    }

    @Test func malformedFilesAreRejectedNotCrashing() throws {
        let dir = try FixtureDirectory()
        let garbage = try dir.file("garbage.jpg", bytes: (0..<4096).map { _ in UInt8.random(in: 0...255) })
        let empty = try dir.file("empty.png", bytes: [])
        let text = try dir.file("notes.txt", bytes: Array("hello".utf8))
        let missing = dir.url.appendingPathComponent("missing.jpg")

        #expect(Fixtures.inspector.inspect(garbage) == .failure(.unreadable))
        #expect(Fixtures.inspector.inspect(empty) == .failure(.emptyFile))
        #expect(Fixtures.inspector.inspect(text) == .failure(.notAnImage))
        #expect(Fixtures.inspector.inspect(missing) == .failure(.missing))
    }

    @Test func unsupportedImageTypeIsRejectedWithItsName() throws {
        let dir = try FixtureDirectory()
        // Image I/O can read TGA, but it is not a Pixtamer input type.
        let tga = try dir.write(Fixtures.pattern(width: 16, height: 16, alpha: false), name: "legacy.tga", type: "com.truevision.tga-image", properties: [:])
        guard case .failure(.unsupportedImageType(let name)) = Fixtures.inspector.inspect(tga) else {
            Issue.record("expected unsupportedImageType")
            return
        }
        #expect(!name.isEmpty)
    }

    @Test func truncatedJPEGImportsWithWarning() throws {
        let dir = try FixtureDirectory()
        let full = try dir.jpeg("full.jpg", width: 800, height: 600)
        let data = try Data(contentsOf: full)
        let truncated = dir.url.appendingPathComponent("truncated.jpg")
        try data.prefix(data.count / 2).write(to: truncated)
        let input = try Fixtures.input(truncated)
        #expect(input.warnings.contains(.possiblyTruncated))
        #expect(try Fixtures.input(full).warnings.isEmpty)
    }

    @Test func folderImportRecursesSkipsHiddenAndCountsNonImages() throws {
        let dir = try FixtureDirectory()
        let nested = try dir.subdirectory("nested")
        try dir.jpeg("a.jpg", width: 10, height: 10)
        try dir.transparentPNG("b.png", width: 10, height: 10, in: nested)
        try dir.file("readme.txt", bytes: Array("x".utf8))
        try dir.file(".hidden.jpg", bytes: Array("x".utf8))
        try dir.file("broken.jpg", bytes: [0xFF, 0xD8, 0x00, 0x01])

        let report = importer.importItems([dir.url], includeSubfolders: true, existingKeys: [])
        #expect(report.added.map(\.fileName) == ["a.jpg", "b.png"])
        #expect(report.ignoredNonImageCount == 1)
        #expect(report.rejected.map(\.fileName) == ["broken.jpg"])

        let shallow = importer.importItems([dir.url], includeSubfolders: false, existingKeys: [])
        #expect(shallow.added.map(\.fileName) == ["a.jpg"])
    }

    @Test func duplicatesAreNotAddedTwice() throws {
        let dir = try FixtureDirectory()
        let a = try dir.jpeg("a.jpg", width: 10, height: 10)
        let first = importer.importItems([a, a], includeSubfolders: true, existingKeys: [])
        #expect(first.added.count == 1)
        #expect(first.duplicateCount == 1)
        let second = importer.importItems([dir.url], includeSubfolders: true, existingKeys: Set(first.added.map(\.identityKey)))
        #expect(second.added.isEmpty)
        #expect(second.duplicateCount == 1)
    }

    @Test func mixedSelectionKeepsValidFiles() throws {
        let dir = try FixtureDirectory()
        let good = try dir.jpeg("good.jpg", width: 10, height: 10)
        let bad = try dir.file("bad.png", bytes: Array("<html>".utf8))
        let report = importer.importItems([good, bad], includeSubfolders: true, existingKeys: [])
        #expect(report.added.map(\.fileName) == ["good.jpg"])
        #expect(report.rejected.map(\.fileName) == ["bad.png"])
        #expect(report.rejected.first?.reason == .unreadable)
    }

    @Test func thumbnailsAreSmallAndOriented() throws {
        let dir = try FixtureDirectory()
        let url = try dir.jpeg("big.jpg", width: 3000, height: 2000, orientation: 6)
        let thumb = try #require(Thumbnailer.thumbnail(for: url, maxPixelSize: 128))
        #expect(thumb.width == 85)
        #expect(thumb.height == 128)
    }
}
