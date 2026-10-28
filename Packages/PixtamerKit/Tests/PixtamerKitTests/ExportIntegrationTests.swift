import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PixtamerKit

/// End-to-end: real files in, real files out, verified by re-reading them.
@Suite("Export pipeline with real files")
struct ExportIntegrationTests {
    let exporter = BatchExporter(maxConcurrentJobs: 2)

    func export(_ inputs: [ImageInput], _ settings: ExportSettings, to destination: URL) async -> (ExportPlan, [VariantResult]) {
        let plan = ExportPlanner().plan(inputs: inputs, settings: settings, destination: destination)
        return (plan, await exporter.run(plan))
    }

    @Test func jpegToWebPFitWidthKeepsSourceUnchanged() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("Product Shot.jpg", width: 2400, height: 1600)
        let hashBefore = try Fixtures.sha256(source)
        let out = try dir.subdirectory("out")

        var settings = ExportSettings(format: .webp, quality: 75)
        settings.resize = ResizeSettings(mode: .fit, maxWidth: 1200)
        let (_, results) = await export([try Fixtures.input(source)], settings, to: out)

        let file = try #require(results.writtenFiles.first)
        #expect(file.url.lastPathComponent == "product-shot.webp")
        #expect(Fixtures.type(file.url) == "org.webmproject.webp")
        #expect(Fixtures.pixelSize(file.url) == PixelSize(width: 1200, height: 800))
        #expect(file.bytes == Fixtures.fileSize(file.url), "reported size is the real on-disk size")
        #expect(try Fixtures.sha256(source) == hashBefore)
        #expect(try dir.contents(out, includeHidden: true) == ["product-shot.webp"], "no temporary files left behind")
    }

    @Test(arguments: [OutputFormat.png, .webp, .avif])
    func transparencyIsPreserved(format: OutputFormat) async throws {
        guard Fixtures.systemCanWrite(format) else { return }
        let dir = try FixtureDirectory()
        let source = try dir.transparentPNG("logo.png", width: 200, height: 100)
        let out = try dir.subdirectory("out")
        let (_, results) = await export([try Fixtures.input(source)], ExportSettings(format: format, quality: 90), to: out)
        let file = try #require(results.writtenFiles.first)
        let opaque = try #require(await Fixtures.rgba(file.url, x: 20, y: 50))
        let clear = try #require(await Fixtures.rgba(file.url, x: 180, y: 50))
        #expect(opaque[3] == 255)
        #expect(clear[3] == 0)
    }

    @Test func jpegFlattensTransparencyOntoWhite() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.transparentPNG("logo.png", width: 200, height: 100)
        let out = try dir.subdirectory("out")
        let (_, results) = await export([try Fixtures.input(source)], ExportSettings(format: .jpeg, quality: 95), to: out)
        let file = try #require(results.writtenFiles.first)
        let pixel = try #require(await Fixtures.rgba(file.url, x: 180, y: 50))
        #expect(pixel[0] > 245 && pixel[1] > 245 && pixel[2] > 245, "transparent area becomes white, not black")
    }

    @Test func orientationIsAppliedAndNormalised() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("portrait.jpg", width: 600, height: 400, orientation: 6)
        let out = try dir.subdirectory("out")
        for metadata in MetadataPolicy.allCases {
            var settings = ExportSettings(format: .jpeg, metadata: metadata, collisionPolicy: .replace)
            settings.resize = ResizeSettings(mode: .fit, maxWidth: 200)
            let (_, results) = await export([try Fixtures.input(source)], settings, to: out)
            let file = try #require(results.writtenFiles.first)
            #expect(Fixtures.pixelSize(file.url) == PixelSize(width: 200, height: 300), "\(metadata)")
            let orientation = Fixtures.properties(file.url)[kCGImagePropertyOrientation] as? Int ?? 1
            #expect(orientation == 1, "pixels are rotated, so the tag must not rotate them again (\(metadata))")
        }
    }

    @Test func jpegQualityAffectsSize() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("photo.jpg", width: 1600, height: 1200, quality: 1.0)
        let input = try Fixtures.input(source)
        var sizes: [Int: Int64] = [:]
        for quality in [30, 90] {
            let out = try dir.subdirectory("q\(quality)")
            let (_, results) = await export([input], ExportSettings(format: .jpeg, quality: quality), to: out)
            sizes[quality] = try #require(results.writtenFiles.first).bytes
        }
        #expect(sizes[30]! < sizes[90]!)
    }

    @Test func webpLosslessRoundTripsPixelsExactly() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.png("flat.png", image: Fixtures.solid(width: 50, height: 50, red: 0.2, green: 0.4, blue: 0.6, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        let out = try dir.subdirectory("out")
        let (_, results) = await export([try Fixtures.input(source)], ExportSettings(format: .webp, webpLossless: true), to: out)
        let file = try #require(results.writtenFiles.first)
        let exported = await Fixtures.rgba(file.url, x: 10, y: 10)
        let original = await Fixtures.rgba(source, x: 10, y: 10)
        #expect(exported == original)
    }

    @Test func responsiveWidthsProduceExpectedFiles() async throws {
        let dir = try FixtureDirectory()
        let wide = try dir.jpeg("hero.jpg", width: 2000, height: 1125)
        let narrow = try dir.jpeg("thumb.jpg", width: 700, height: 700)
        let out = try dir.subdirectory("out")
        var settings = ExportSettings(format: .webp)
        settings.resize = ResizeSettings(mode: .widths, widths: [480, 960, 1440])
        settings.naming = FilenameRule(mode: .template, template: "{name}-{width}w")
        let (plan, results) = await export([try Fixtures.input(wide), try Fixtures.input(narrow)], settings, to: out)

        #expect(plan.writeCount == 4)
        #expect(try dir.contents(out) == ["hero-1440w.webp", "hero-480w.webp", "hero-960w.webp", "thumb-480w.webp"])
        #expect(Fixtures.pixelSize(out.appendingPathComponent("hero-960w.webp")) == PixelSize(width: 960, height: 540))
        #expect(Fixtures.pixelSize(out.appendingPathComponent("hero-1440w.webp")) == PixelSize(width: 1440, height: 810))
        let summary = BatchSummary.make(results)
        #expect(summary.writtenCount == 4)
        #expect(summary.skippedCount == 2, "thumb 960w and 1440w would upscale")
    }

    @Test func exactCropProducesSquare() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("wide.jpg", width: 1600, height: 900)
        let out = try dir.subdirectory("out")
        var settings = ExportSettings(format: .jpeg)
        settings.resize = ResizeSettings(mode: .exact, exactWidth: 800, exactHeight: 800, preserveAspectRatio: true)
        let (_, results) = await export([try Fixtures.input(source)], settings, to: out)
        #expect(Fixtures.pixelSize(try #require(results.writtenFiles.first).url) == PixelSize(width: 800, height: 800))
    }

    @Test func partialFailureIsIsolatedAndRetryDoesNotDuplicate() async throws {
        let dir = try FixtureDirectory()
        let src = try dir.subdirectory("src")
        let good1 = try dir.jpeg("one.jpg", width: 400, height: 300, in: src)
        let doomed = try dir.jpeg("two.jpg", width: 400, height: 300, in: src)
        let good2 = try dir.jpeg("three.jpg", width: 400, height: 300, in: src)
        let inputs = try [good1, doomed, good2].map(Fixtures.input)
        let doomedBytes = try Data(contentsOf: doomed)
        try Data("corrupted".utf8).write(to: doomed) // Damaged after import.

        let out = try dir.subdirectory("out")
        let settings = ExportSettings(format: .png)
        let (plan, results) = await export(inputs, settings, to: out)
        let summary = BatchSummary.make(results)
        #expect(summary.writtenCount == 2)
        #expect(summary.failedCount == 1)
        #expect(results.first { $0.inputFileName == "two.jpg" }?.outcome.isFailed == true)
        #expect(try dir.contents(out) == ["one.png", "three.png"])

        // User fixes the file and retries only what failed.
        try doomedBytes.write(to: doomed)
        let failedIDs = Set(results.filter(\.outcome.isFailed).map(\.id))
        let retry = await exporter.run(plan.restricted(to: failedIDs))
        #expect(retry.count == 1)
        #expect(retry.writtenFiles.count == 1)
        #expect(try dir.contents(out) == ["one.png", "three.png", "two.png"], "successful outputs are not exported twice")
    }

    @Test func missingSourceFailsWithActionableMessage() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("gone.jpg", width: 100, height: 100)
        let input = try Fixtures.input(source)
        try FileManager.default.removeItem(at: source)
        let (_, results) = await export([input], ExportSettings(format: .jpeg), to: try dir.subdirectory("out"))
        guard case .failed(let failure) = results.first?.outcome else { Issue.record("expected failure"); return }
        #expect(failure.code == .sourceMissing)
        #expect(failure.message.contains("gone.jpg"))
        #expect(!failure.message.contains(dir.url.path))
    }

    @Test func collisionPoliciesOnDisk() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("a.jpg", width: 100, height: 100)
        let input = try Fixtures.input(source)
        let out = try dir.subdirectory("out")
        let existing = out.appendingPathComponent("a.png")
        try Data("keep me".utf8).write(to: existing)

        let (_, renamed) = await export([input], ExportSettings(format: .png, collisionPolicy: .rename), to: out)
        #expect(renamed.writtenFiles.first?.url.lastPathComponent == "a-1.png")
        #expect(try Data(contentsOf: existing) == Data("keep me".utf8))

        let (_, skipped) = await export([input], ExportSettings(format: .png, collisionPolicy: .skip), to: out)
        #expect(skipped.first?.outcome == .skipped(.outputExists(fileName: "a.png")))
        #expect(try Data(contentsOf: existing) == Data("keep me".utf8))

        let (_, replaced) = await export([input], ExportSettings(format: .png, collisionPolicy: .replace), to: out)
        #expect(replaced.writtenFiles.first?.url.lastPathComponent == "a.png")
        #expect(Fixtures.type(existing) == "public.png")
        #expect(try dir.contents(out, includeHidden: true) == ["a-1.png", "a.png"])
    }

    @Test func exportingIntoSourceFolderNeverOverwritesSource() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("photo.jpg", width: 300, height: 200)
        let hash = try Fixtures.sha256(source)
        var settings = ExportSettings(format: .jpeg, collisionPolicy: .replace)
        settings.naming.webSafe = false
        let (_, results) = await export([try Fixtures.input(source)], settings, to: dir.url)
        #expect(results.writtenFiles.first?.url.lastPathComponent == "photo-1.jpg")
        #expect(try Fixtures.sha256(source) == hash)
    }

    @Test func finalizerRefusesProtectedPath() throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("src.jpg", width: 10, height: 10)
        let temp = try dir.file(".tmp", bytes: [1, 2, 3])
        #expect(throws: ExportFailure.self) {
            try OutputWriter.finalize(temp: temp, final: source, policy: .replace, protectedPathKeys: [PathKey.make(source)])
        }
        #expect(Fixtures.type(source) == "public.jpeg")
    }

    @Test func lateCollisionIsRenamedAtomically() throws {
        let dir = try FixtureDirectory()
        let target = dir.url.appendingPathComponent("x.png")
        try Data("other app".utf8).write(to: target)
        let temp = try dir.file(".x.tmp", bytes: [9])
        let result = try OutputWriter.finalize(temp: temp, final: target, policy: .rename, protectedPathKeys: [])
        #expect(result == .written(url: dir.url.appendingPathComponent("x-1.png"), bytes: 1, renamedFrom: "x.png"))
        #expect(try Data(contentsOf: target) == Data("other app".utf8))
    }

    @Test func metadataPolicies() async throws {
        let dir = try FixtureDirectory()
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Test Lens 50mm"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCopyrightNotice: "© Test"],
        ]
        let source = try dir.jpeg("geo.jpg", width: 200, height: 100, properties: gps)
        #expect(Fixtures.properties(source)[kCGImagePropertyGPSDictionary] != nil)
        let input = try Fixtures.input(source)

        func exported(_ policy: MetadataPolicy, _ format: OutputFormat = .jpeg) async throws -> [CFString: Any] {
            let out = try dir.subdirectory("\(policy)-\(format)")
            let (_, results) = await export([input], ExportSettings(format: format, metadata: policy), to: out)
            return Fixtures.properties(try #require(results.writtenFiles.first).url)
        }

        let stripped = try await exported(.strip)
        #expect(stripped[kCGImagePropertyGPSDictionary] == nil)
        #expect((stripped[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] == nil)

        let noLocation = try await exported(.keepWithoutLocation)
        #expect(noLocation[kCGImagePropertyGPSDictionary] == nil)
        #expect((noLocation[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] as? String == "Test Lens 50mm")
        #expect((noLocation[kCGImagePropertyIPTCDictionary] as? [CFString: Any])?[kCGImagePropertyIPTCCopyrightNotice] as? String == "© Test")

        let everything = try await exported(.keepAll)
        #expect(everything[kCGImagePropertyGPSDictionary] != nil)

        let webp = try await exported(.keepAll, .webp)
        #expect(webp[kCGImagePropertyGPSDictionary] == nil, "WebP always strips metadata")
    }

    @Test func colorProfileKeptExceptWebP() async throws {
        let dir = try FixtureDirectory()
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let source = try dir.png("p3.png", image: Fixtures.solid(width: 40, height: 40, red: 1, green: 0, blue: 0, colorSpace: p3))
        let input = try Fixtures.input(source)
        #expect(input.colorProfileName == "Display P3")

        let pngOut = try dir.subdirectory("png")
        let (_, png) = await export([input], ExportSettings(format: .png), to: pngOut)
        #expect(Fixtures.properties(try #require(png.writtenFiles.first).url)[kCGImagePropertyProfileName] as? String == "Display P3")

        let webpOut = try dir.subdirectory("webp")
        let (_, webp) = await export([input], ExportSettings(format: .webp, webpLossless: true), to: webpOut)
        let webpFile = try #require(webp.writtenFiles.first).url
        // Converted to sRGB: P3 pure red is outside sRGB, so it clips to (255, 0, 0)-ish rather than being misread.
        let pixel = try #require(await Fixtures.rgba(webpFile, x: 5, y: 5))
        #expect(pixel[0] > 250 && pixel[1] < 10 && pixel[2] < 10)
    }

    @Test func largeImageIsDownsampled() async throws {
        let dir = try FixtureDirectory()
        let source = try dir.jpeg("huge.jpg", width: 8000, height: 6000, quality: 0.8)
        let out = try dir.subdirectory("out")
        var settings = ExportSettings(format: .jpeg)
        settings.resize = ResizeSettings(mode: .fit, maxWidth: 1600)
        let start = Date()
        let (_, results) = await export([try Fixtures.input(source)], settings, to: out)
        #expect(Fixtures.pixelSize(try #require(results.writtenFiles.first).url) == PixelSize(width: 1600, height: 1200))
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func summaryMatchesDisk() async throws {
        let dir = try FixtureDirectory()
        let inputs = try (0..<5).map { try Fixtures.input(try dir.jpeg("img\($0).jpg", width: 600 + $0 * 100, height: 400)) }
        let out = try dir.subdirectory("out")
        let (_, results) = await export(inputs, ExportSettings(format: .webp), to: out)
        let summary = BatchSummary.make(results)
        let diskTotal = try dir.contents(out).map { Fixtures.fileSize(out.appendingPathComponent($0)) }.reduce(0, +)
        #expect(summary.outputBytes == diskTotal)
        #expect(summary.originalBytes == inputs.map(\.fileSize).reduce(0, +))
        #expect(summary.writtenCount == 5)
    }

    @Test func cancellationLeavesOnlyCompleteFiles() async throws {
        let dir = try FixtureDirectory()
        let src = try dir.subdirectory("src")
        let inputs = try (0..<24).map { try Fixtures.input(try dir.jpeg("big\($0).jpg", width: 3000, height: 2000, in: src)) }
        let out = try dir.subdirectory("out")
        let plan = ExportPlanner().plan(inputs: inputs, settings: ExportSettings(format: .avif, quality: 60), destination: out)
        let run = BatchExporter(maxConcurrentJobs: 2).start(plan)

        var results: [VariantResult] = []
        var cancelledFlag: Bool?
        for await event in run.events {
            switch event {
            case .variantFinished(let result):
                results.append(result)
                if results.count == 2 { run.cancel() }
            case .finished(let cancelled):
                cancelledFlag = cancelled
            default:
                break
            }
        }
        #expect(cancelledFlag == true)
        #expect(results.count == plan.variants.count, "every planned output has a final state")
        let summary = BatchSummary.make(results)
        #expect(summary.cancelledCount > 0)
        let files = try dir.contents(out, includeHidden: true)
        #expect(!files.contains { $0.contains(OutputWriter.temporaryMarker) }, "no partial files")
        #expect(files.count == summary.writtenCount)
        for name in files {
            #expect(Fixtures.pixelSize(out.appendingPathComponent(name)) == PixelSize(width: 3000, height: 2000))
        }
    }

    @Test func starterPresetsExportSuccessfully() async throws {
        let dir = try FixtureDirectory()
        let input = try Fixtures.input(try dir.jpeg("starter.jpg", width: 2400, height: 1600))
        for preset in PresetLibrary.starters().presets {
            let out = try dir.subdirectory(preset.id.uuidString)
            let (plan, results) = await export([input], preset.settings, to: out)
            #expect(results.writtenFiles.count == plan.writeCount, "\(preset.name)")
            #expect(results.allSatisfy { !$0.outcome.isFailed }, "\(preset.name)")
        }
    }

    @Test func estimateEncodesInMemoryOnly() throws {
        let dir = try FixtureDirectory()
        let input = try Fixtures.input(try dir.jpeg("e.jpg", width: 1000, height: 500))
        var settings = ExportSettings(format: .webp)
        settings.resize = ResizeSettings(mode: .fit, maxWidth: 500)
        let estimate = try #require(try ImageProcessor().estimate(input: input, settings: settings))
        #expect(estimate.pixelSize == PixelSize(width: 500, height: 250))
        #expect(estimate.bytes > 0)
        #expect(try dir.contents() == ["e.jpg"])
    }
}
