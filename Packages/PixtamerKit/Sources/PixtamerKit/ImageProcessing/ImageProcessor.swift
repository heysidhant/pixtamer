import CoreGraphics
import Foundation
import ImageIO

/// Processes one source image into its planned outputs. Synchronous and UI-independent; the
/// batch exporter calls it from bounded background tasks.
public struct ImageProcessor: Sendable {
    public let registry: EncoderRegistry

    public init(registry: EncoderRegistry = .standard) {
        self.registry = registry
    }

    public func process(
        job: PlannedJob,
        settings: ExportSettings,
        protectedPathKeys: Set<String>,
        isCancelled: () -> Bool
    ) -> [VariantResult] {
        let input = job.input
        func result(_ variant: PlannedVariant, _ outcome: VariantOutcome, extra: [String] = []) -> VariantResult {
            VariantResult(
                id: variant.id,
                inputID: input.id,
                inputFileName: input.fileName,
                sourceBytes: input.fileSize,
                label: variant.label,
                plannedFileName: variant.plannedFileName,
                outcome: outcome,
                notes: variant.notes.map(\.message) + extra
            )
        }

        let needsSource = job.variants.contains { $0.destination != nil }
        var source: CGImageSource?
        var sourceError: ExportFailure?
        if needsSource && !isCancelled() {
            switch Self.openSource(input) {
            case .success(let opened): source = opened
            case .failure(let error): sourceError = error
            }
        }
        if sourceError == nil, needsSource, registry.encoder(for: settings.format) == nil {
            sourceError = ExportFailure(.encoderUnavailable, "\(settings.format.displayName) encoding isn’t available in this build.")
        }

        let metadata = source.flatMap { MetadataExtractor.properties(from: $0, policy: settings.effectiveMetadata) }
        let options = EncodeOptions(
            quality: settings.effectiveQuality,
            lossless: settings.format == .webp && settings.webpLossless,
            metadata: metadata
        )

        return job.variants.map { variant in
            switch variant.action {
            case .skip(let reason):
                return result(variant, .skipped(reason))
            case .write(let plan, let destination):
                if isCancelled() { return result(variant, .cancelled) }
                if let sourceError { return result(variant, .failed(sourceError)) }
                guard let source, let encoder = registry.encoder(for: settings.format) else { return result(variant, .cancelled) }
                return autoreleasepool {
                    do throws(ExportFailure) {
                        let image = try ImageRenderer.render(source: source, sourceSize: input.pixelSize, plan: plan, format: settings.format)
                        let data = try encoder.encode(image, options: options)
                        guard let finalized = try OutputWriter.write(
                            data: data,
                            to: destination,
                            expectedFormat: settings.format,
                            expectedSize: plan.outputSize,
                            policy: settings.collisionPolicy,
                            protectedPathKeys: protectedPathKeys,
                            isCancelled: isCancelled
                        ) else {
                            return result(variant, .cancelled)
                        }
                        switch finalized {
                        case .written(let url, let bytes, let renamedFrom):
                            let file = WrittenFile(url: url, bytes: bytes, pixelSize: plan.outputSize, format: settings.format)
                            let extra = renamedFrom.map { ["\($0) appeared while exporting, so a number was added."] } ?? []
                            return result(variant, .written(file), extra: extra)
                        case .skippedExisting(let name):
                            return result(variant, .skipped(.outputExists(fileName: name)))
                        }
                    } catch {
                        return result(variant, .failed(error))
                    }
                }
            }
        }
    }

    /// Encodes the first renderable variant in memory with exactly the export code path, without
    /// writing anything. Used by the preview to show an *estimated* size.
    public func estimate(input: ImageInput, settings: ExportSettings) throws(ExportFailure) -> OutputEstimate? {
        let decisions = ResizePlanner.variants(for: input.pixelSize, settings: settings.resize)
        guard let plan = decisions.lazy.compactMap({ if case .render(let p) = $0 { p } else { nil } }).last else { return nil }
        guard let encoder = registry.encoder(for: settings.format) else {
            throw ExportFailure(.encoderUnavailable, "\(settings.format.displayName) encoding isn’t available in this build.")
        }
        let source = try Self.openSource(input).get()
        let metadata = MetadataExtractor.properties(from: source, policy: settings.effectiveMetadata)
        let image = try ImageRenderer.render(source: source, sourceSize: input.pixelSize, plan: plan, format: settings.format)
        let data = try encoder.encode(image, options: EncodeOptions(
            quality: settings.effectiveQuality,
            lossless: settings.format == .webp && settings.webpLossless,
            metadata: metadata
        ))
        return OutputEstimate(label: plan.requestedWidth.map { "\($0)w" } ?? plan.outputSize.description, pixelSize: plan.outputSize, format: settings.format, data: data)
    }

    static func openSource(_ input: ImageInput) -> Result<CGImageSource, ExportFailure> {
        guard FileManager.default.fileExists(atPath: input.url.path) else {
            return .failure(ExportFailure(.sourceMissing, "\(input.fileName) was moved or deleted after it was added."))
        }
        guard let source = CGImageSourceCreateWithURL(input.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .failure(ExportFailure(.sourceUnreadable, "\(input.fileName) could not be read. It may be damaged or no longer accessible."))
        }
        if ImageInspector.orientedSize(properties) != input.pixelSize {
            return .failure(ExportFailure(.sourceUnreadable, "\(input.fileName) changed after it was added. Remove it and add it again."))
        }
        return .success(source)
    }
}

/// In-memory encode result. Always labelled as an estimate in the UI.
public struct OutputEstimate: Sendable {
    public let label: String
    public let pixelSize: PixelSize
    public let format: OutputFormat
    public let data: Data
    public var bytes: Int64 { Int64(data.count) }
}
