import Testing
@testable import PixtamerKit

@Suite("Filename generation and sanitisation")
struct FilenameRendererTests {
    let context = FilenameContext(name: "Hero Banner", width: 960, height: 540, format: .webp, index: 3, total: 120)

    @Test func originalName() {
        let rule = FilenameRule(mode: .original, webSafe: false)
        #expect(FilenameRenderer.fileName(rule: rule, context: context, multipleWidths: false) == "Hero Banner.webp")
    }

    @Test func originalNameWebSafe() {
        let rule = FilenameRule(mode: .original, webSafe: true)
        #expect(FilenameRenderer.fileName(rule: rule, context: context, multipleWidths: false) == "hero-banner.webp")
    }

    @Test func suffix() {
        let rule = FilenameRule(mode: .suffix, suffix: "@2x", webSafe: false)
        #expect(FilenameRenderer.fileName(rule: rule, context: context, multipleWidths: false) == "Hero Banner@2x.webp")
    }

    @Test func multipleWidthsAppendWidthForOriginalAndSuffix() {
        #expect(FilenameRenderer.fileName(rule: FilenameRule(mode: .original), context: context, multipleWidths: true) == "hero-banner-960w.webp")
        #expect(FilenameRenderer.fileName(rule: FilenameRule(mode: .suffix, suffix: "_web"), context: context, multipleWidths: true) == "hero-banner_web-960w.webp")
    }

    @Test func templateTokens() {
        let rule = FilenameRule(mode: .template, template: "{index}_{name}_{width}x{height}.{format}", webSafe: false)
        #expect(FilenameRenderer.fileName(rule: rule, context: context, multipleWidths: false) == "003_Hero Banner_960x540.webp.webp")
    }

    @Test func indexPadsToAtLeastTwoDigits() {
        let small = FilenameContext(name: "a", width: 1, height: 1, format: .png, index: 4, total: 5)
        #expect(FilenameRenderer.expand(template: "{index}", context: small) == "04")
    }

    @Test func sourceNameContainingTokenIsNotExpandedTwice() {
        let tricky = FilenameContext(name: "{width}", width: 480, height: 320, format: .jpeg)
        let rule = FilenameRule(mode: .template, template: "{name}-{width}w", webSafe: false)
        #expect(FilenameRenderer.fileName(rule: rule, context: tricky, multipleWidths: true) == "{width}-480w.jpg")
    }

    @Test(arguments: [
        ("../../etc/passwd", false, "-..-etc-passwd"),
        ("a/b:c", false, "a-b-c"),
        (".hidden", false, "hidden"),
        ("...", false, "image"),
        ("", true, "image"),
        ("trailing. ", false, "trailing"),
        ("Café Crème", true, "cafe-creme"),
        ("Product  Photo__01!!", true, "product-photo__01"),
        ("写真", true, "xie-zhen"),
        ("bad<>|?*\"name", false, "bad-name"),
        ("line\nbreak", false, "line-break"),
    ])
    func sanitize(input: String, webSafe: Bool, expected: String) {
        #expect(FilenameRenderer.sanitize(input, webSafe: webSafe) == expected)
    }

    @Test func sanitizeNeverProducesPathSeparatorsOrLeadingDot() {
        for raw in ["/", "//x", "./x", "..", "a\\b", "x:y", "\u{0}nul"] {
            for webSafe in [true, false] {
                let result = FilenameRenderer.sanitize(raw, webSafe: webSafe)
                #expect(!result.contains("/"))
                #expect(!result.contains(":"))
                #expect(!result.hasPrefix("."))
                #expect(!result.isEmpty)
            }
        }
    }

    @Test func sanitizeLimitsLength() {
        let long = String(repeating: "é", count: 400)
        let result = FilenameRenderer.sanitize(long, webSafe: false)
        #expect(result.utf8.count <= FilenameRenderer.maxBaseNameBytes)
        #expect(result.allSatisfy { $0 == "é" })
    }

    @Test func templateValidation() {
        #expect(FilenameRenderer.templateErrors("{name}-{width}w", multipleWidths: true).isEmpty)
        #expect(!FilenameRenderer.templateErrors("", multipleWidths: false).isEmpty)
        #expect(!FilenameRenderer.templateErrors("{name}/{width}", multipleWidths: false).isEmpty)
        #expect(!FilenameRenderer.templateErrors("{name", multipleWidths: false).isEmpty)
        #expect(!FilenameRenderer.templateErrors("name}", multipleWidths: false).isEmpty)
        #expect(FilenameRenderer.templateErrors("{size}", multipleWidths: false).contains { $0.contains("{size}") })
        #expect(!FilenameRenderer.templateErrors("{name}", multipleWidths: true).isEmpty, "multiple widths require {width}")
        #expect(!FilenameRenderer.templateWarnings("banner-{width}").isEmpty)
        #expect(FilenameRenderer.templateWarnings("{name}").isEmpty)
    }
}
