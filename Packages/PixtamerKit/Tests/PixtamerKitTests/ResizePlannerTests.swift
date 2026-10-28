import Testing
@testable import PixtamerKit

@Suite("Resize rules, aspect ratio and no-upscale")
struct ResizePlannerTests {
    let landscape = PixelSize(width: 3000, height: 2000)

    func renderedSizes(_ decisions: [VariantDecision]) -> [PixelSize] {
        decisions.compactMap { if case .render(let plan) = $0 { plan.outputSize } else { nil } }
    }

    @Test func originalKeepsSize() {
        #expect(renderedSizes(ResizePlanner.variants(for: landscape, settings: ResizeSettings(mode: .original))) == [landscape])
    }

    @Test func fitByWidth() {
        let size = ResizePlanner.fitSize(source: landscape, maxWidth: 1000, maxHeight: nil, allowUpscale: false)
        #expect(size == PixelSize(width: 1000, height: 667))
    }

    @Test func fitByHeight() {
        let size = ResizePlanner.fitSize(source: landscape, maxWidth: nil, maxHeight: 500, allowUpscale: false)
        #expect(size == PixelSize(width: 750, height: 500))
    }

    @Test func fitWithinBoxUsesTighterSide() {
        #expect(ResizePlanner.fitSize(source: landscape, maxWidth: 1200, maxHeight: 1200, allowUpscale: false) == PixelSize(width: 1200, height: 800))
        let portrait = PixelSize(width: 2000, height: 3000)
        #expect(ResizePlanner.fitSize(source: portrait, maxWidth: 1200, maxHeight: 1200, allowUpscale: false) == PixelSize(width: 800, height: 1200))
    }

    @Test func fitDoesNotUpscaleByDefault() {
        let small = PixelSize(width: 800, height: 600)
        #expect(ResizePlanner.fitSize(source: small, maxWidth: 1600, maxHeight: nil, allowUpscale: false) == small)
        #expect(ResizeSettings().allowUpscale == false, "Do not upscale is the default")
    }

    @Test func fitUpscalesWhenAllowed() {
        let small = PixelSize(width: 800, height: 600)
        #expect(ResizePlanner.fitSize(source: small, maxWidth: 1600, maxHeight: nil, allowUpscale: true) == PixelSize(width: 1600, height: 1200))
    }

    @Test func fitWithoutLimitsKeepsOriginal() {
        #expect(ResizePlanner.fitSize(source: landscape, maxWidth: nil, maxHeight: nil, allowUpscale: true) == landscape)
    }

    @Test(arguments: [
        PixelSize(width: 4032, height: 3024),
        PixelSize(width: 1080, height: 1920),
        PixelSize(width: 1001, height: 333),
        PixelSize(width: 7, height: 5000),
        PixelSize(width: 12_000, height: 9),
    ])
    func aspectRatioPreserved(source: PixelSize) {
        let settings = ResizeSettings(mode: .widths, widths: [1, 5, 480, 960, 1440], allowUpscale: true)
        for size in renderedSizes(ResizePlanner.variants(for: source, settings: settings)) {
            let expectedHeight = Double(source.height) * Double(size.width) / Double(source.width)
            #expect(abs(Double(size.height) - expectedHeight) <= 0.5 || size.height == 1, "rounding error under half a pixel")
            #expect(size.height >= 1)
        }
    }

    @Test func widthsSortedDedupedAndSkipUpscale() {
        let source = PixelSize(width: 1000, height: 500)
        let settings = ResizeSettings(mode: .widths, widths: [1440, 480, 960, 480, 0, -5])
        let decisions = ResizePlanner.variants(for: source, settings: settings)
        #expect(decisions.count == 3)
        #expect(renderedSizes(decisions) == [PixelSize(width: 480, height: 240), PixelSize(width: 960, height: 480)])
        #expect(decisions.last == .skip(.wouldUpscale(requestedWidth: 1440, sourceWidth: 1000)))
    }

    @Test func widthsUpscaleWhenAllowed() {
        let source = PixelSize(width: 1000, height: 500)
        let settings = ResizeSettings(mode: .widths, widths: [480, 1440], allowUpscale: true)
        #expect(renderedSizes(ResizePlanner.variants(for: source, settings: settings)) == [PixelSize(width: 480, height: 240), PixelSize(width: 1440, height: 720)])
    }

    @Test func variantCountForResponsiveExport() {
        let settings = ResizeSettings(mode: .widths, widths: [480, 960, 1440])
        #expect(ResizePlanner.variants(for: PixelSize(width: 2000, height: 1000), settings: settings).count == 3)
        #expect(renderedSizes(ResizePlanner.variants(for: PixelSize(width: 1200, height: 800), settings: settings)).count == 2)
        #expect(renderedSizes(ResizePlanner.variants(for: PixelSize(width: 300, height: 300), settings: settings)).isEmpty)
    }

    @Test func exactCropAndStretch() {
        let crop = ResizeSettings(mode: .exact, exactWidth: 1200, exactHeight: 1200, preserveAspectRatio: true)
        #expect(ResizePlanner.variants(for: landscape, settings: crop) == [.render(VariantPlan(outputSize: PixelSize(width: 1200, height: 1200), fill: .cropToFill))])
        let stretch = ResizeSettings(mode: .exact, exactWidth: 1200, exactHeight: 1200, preserveAspectRatio: false)
        #expect(ResizePlanner.variants(for: landscape, settings: stretch) == [.render(VariantPlan(outputSize: PixelSize(width: 1200, height: 1200), fill: .stretch))])
    }

    @Test func exactSkipsWhenSourceTooSmall() {
        let settings = ResizeSettings(mode: .exact, exactWidth: 1200, exactHeight: 1200)
        let small = PixelSize(width: 1500, height: 1000)
        #expect(ResizePlanner.variants(for: small, settings: settings) == [.skip(.sourceSmallerThanTarget(source: small, target: PixelSize(width: 1200, height: 1200)))])
        var upscale = settings
        upscale.allowUpscale = true
        #expect(renderedSizes(ResizePlanner.variants(for: small, settings: upscale)) == [PixelSize(width: 1200, height: 1200)])
    }

    @Test func cropRectCoversCanvasCentred() {
        let rect = ImageRenderer.drawRect(source: landscape, plan: VariantPlan(outputSize: PixelSize(width: 1200, height: 1200), fill: .cropToFill))
        #expect(rect.height == 1200)
        #expect(rect.width == 1800)
        #expect(rect.minX == -300)
    }
}
