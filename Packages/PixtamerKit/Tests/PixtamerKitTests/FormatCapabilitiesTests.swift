import CoreGraphics
import ImageIO
import Foundation
import Testing
@testable import PixtamerKit

@Suite("Runtime format detection")
struct FormatCapabilitiesTests {
    @Test func coreFormatsAreAvailable() async {
        let caps = await FormatCapabilities.detected()
        #expect(caps.isAvailable(.jpeg))
        #expect(caps.isAvailable(.png))
        #expect(caps.isAvailable(.webp), "bundled libwebp must always pass its probe")
    }

    @Test func avifMatchesSystemEncoderList() async {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let probe = await FormatCapabilities.detected().probes.first { $0.format == .avif }
        if !writable.contains("public.avif") {
            #expect(probe?.available == false)
        }
        // When the system lists an AVIF encoder, availability is decided by the probe result,
        // which is recorded in docs/FORMAT_SUPPORT.md for the tested macOS version.
    }

    @Test func readableInputsAreLimitedToSupportedTypes() async {
        let caps = await FormatCapabilities.detected()
        #expect(caps.readableTypeIdentifiers.contains("public.jpeg"))
        #expect(caps.readableTypeIdentifiers.contains("public.png"))
        #expect(!caps.readableTypeIdentifiers.contains("com.adobe.photoshop-image"))
        #expect(caps.readableTypeIdentifiers.isSubset(of: Set(FormatCapabilities.supportedInputTypes.keys)))
    }

    @Test func missingEncoderIsUnavailable() async {
        let registry = EncoderRegistry(encoders: [ImageIOEncoder(format: .jpeg)])
        let caps = await FormatCapabilities.detected(registry: registry)
        #expect(caps.availableFormats == [.jpeg])
    }

    @Test func failingEncoderIsHidden() async {
        struct BrokenEncoder: ImageEncoder {
            let format = OutputFormat.png
            func encode(_ image: CGImage, options: EncodeOptions) throws(ExportFailure) -> Data {
                Data("not a png".utf8)
            }
        }
        let caps = await FormatCapabilities.detected(registry: EncoderRegistry(encoders: [ImageIOEncoder(format: .jpeg), BrokenEncoder()]))
        #expect(!caps.isAvailable(.png))
        #expect(caps.probes.first { $0.format == .png }?.detail.contains("decode") == true)
    }
}
