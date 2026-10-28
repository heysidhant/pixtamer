import Testing
@testable import PixtamerKit

@Suite("Settings validation")
struct SettingsValidationTests {
    let all = OutputFormat.allCases

    @Test func defaultsAreValid() {
        #expect(!ExportSettings().validate(availableFormats: all).hasErrors)
    }

    @Test func unavailableFormatIsAnError() {
        let issues = ExportSettings(format: .avif).validate(availableFormats: [.jpeg, .png, .webp])
        #expect(issues.messages(for: .format).first?.severity == .error)
    }

    @Test func qualityRange() {
        #expect(ExportSettings(format: .jpeg, quality: 0).validate(availableFormats: all).hasErrors)
        #expect(ExportSettings(format: .jpeg, quality: 101).validate(availableFormats: all).hasErrors)
        #expect(!ExportSettings(format: .png, quality: 0).validate(availableFormats: all).hasErrors, "PNG ignores quality")
    }

    @Test func responsiveWidths() {
        var settings = ExportSettings()
        settings.resize = ResizeSettings(mode: .widths, widths: [])
        #expect(settings.validate(availableFormats: all).messages(for: .widths).contains { $0.severity == .error })

        settings.resize.widths = [480, 0]
        #expect(settings.validate(availableFormats: all).hasErrors)

        settings.resize.widths = [480, 20_000]
        #expect(settings.validate(availableFormats: all).hasErrors)

        settings.resize.widths = [480, 480, 960]
        let issues = settings.validate(availableFormats: all)
        #expect(!issues.hasErrors)
        #expect(issues.messages(for: .widths).contains { $0.severity == .warning })
        #expect(settings.resize.normalizedWidths == [480, 960])
    }

    @Test func webpDimensionLimit() {
        var settings = ExportSettings(format: .webp)
        settings.resize = ResizeSettings(mode: .fit, maxWidth: 16_384)
        #expect(settings.validate(availableFormats: all).hasErrors)
        settings.format = .png
        #expect(!settings.validate(availableFormats: all).hasErrors)
    }

    @Test func templateRequiresWidthForResponsive() {
        var settings = ExportSettings()
        settings.resize = ResizeSettings(mode: .widths)
        settings.naming = FilenameRule(mode: .template, template: "{name}")
        #expect(settings.validate(availableFormats: all).messages(for: .naming).contains { $0.severity == .error })
        settings.naming.template = "{name}-{width}w"
        #expect(!settings.validate(availableFormats: all).hasErrors)
    }

    @Test func subfolderValidation() {
        var settings = ExportSettings()
        settings.subfolder = SubfolderRule(mode: .custom, customName: "  ")
        #expect(settings.validate(availableFormats: all).hasErrors)
        settings.subfolder.customName = "a/b"
        #expect(settings.validate(availableFormats: all).hasErrors)
        settings.subfolder.customName = "exports"
        #expect(!settings.validate(availableFormats: all).hasErrors)
    }

    @Test func webpMetadataWarning() {
        let settings = ExportSettings(format: .webp, metadata: .keepAll)
        #expect(settings.validate(availableFormats: all).messages(for: .metadata).first?.severity == .warning)
        #expect(settings.effectiveMetadata == .strip)
    }
}
