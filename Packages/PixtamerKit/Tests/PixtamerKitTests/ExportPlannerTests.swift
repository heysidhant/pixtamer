import Foundation
import Testing
@testable import PixtamerKit

@Suite("Export planning, duplicate names and collision policies")
struct ExportPlannerTests {
    let destination = URL(fileURLWithPath: "/tmp/out", isDirectory: true)

    func names(_ plan: ExportPlan) -> [String?] {
        plan.variants.map(\.plannedFileName)
    }

    @Test func singleOutputPerImage() {
        let inputs = [Fixtures.makeInput(name: "a.jpg"), Fixtures.makeInput(name: "b.png")]
        let plan = ExportPlanner(fileExists: { _ in false }).plan(inputs: inputs, settings: ExportSettings(format: .webp), destination: destination)
        #expect(names(plan) == ["a.webp", "b.webp"])
        #expect(plan.writeCount == 2)
    }

    @Test func responsiveVariantsAndNames() {
        var settings = ExportSettings(format: .webp)
        settings.resize = ResizeSettings(mode: .widths, widths: [480, 960, 1440])
        settings.naming = FilenameRule(mode: .template, template: "{name}-{width}w")
        let inputs = [Fixtures.makeInput(name: "Hero.jpg", size: PixelSize(width: 2000, height: 1000)), Fixtures.makeInput(name: "small.jpg", size: PixelSize(width: 1000, height: 1000))]
        let plan = ExportPlanner(fileExists: { _ in false }).plan(inputs: inputs, settings: settings, destination: destination)
        #expect(plan.variants.count == 6)
        #expect(plan.writeCount == 5)
        #expect(plan.plannedSkipCount == 1)
        #expect(names(plan) == ["hero-480w.webp", "hero-960w.webp", "hero-1440w.webp", "small-480w.webp", "small-960w.webp", nil])
    }

    @Test func duplicateNamesInBatchAreNumbered() {
        let inputs = [
            Fixtures.makeInput(name: "photo.jpg", url: URL(fileURLWithPath: "/tmp/a/photo.jpg")),
            Fixtures.makeInput(name: "photo.png", url: URL(fileURLWithPath: "/tmp/b/photo.png")),
            Fixtures.makeInput(name: "PHOTO.jpg", url: URL(fileURLWithPath: "/tmp/c/PHOTO.jpg")),
        ]
        for policy in CollisionPolicy.allCases {
            var settings = ExportSettings(format: .jpeg, collisionPolicy: policy)
            settings.naming.webSafe = false
            let plan = ExportPlanner(fileExists: { _ in false }).plan(inputs: inputs, settings: settings, destination: destination)
            #expect(names(plan) == ["photo.jpg", "photo-1.jpg", "PHOTO-2.jpg"], "policy \(policy)")
            #expect(plan.variants[1].notes == [.renamedDuplicateInBatch(originalName: "photo.jpg")])
        }
    }

    @Test func existingFileRename() {
        let existing: Set<String> = ["/tmp/out/a.webp", "/tmp/out/a-1.webp"]
        let plan = ExportPlanner(fileExists: { existing.contains($0.path) }).plan(inputs: [Fixtures.makeInput(name: "a.jpg")], settings: ExportSettings(collisionPolicy: .rename), destination: destination)
        #expect(names(plan) == ["a-2.webp"])
        #expect(plan.variants[0].notes == [.renamedExisting(originalName: "a.webp")])
    }

    @Test func existingFileSkip() {
        let plan = ExportPlanner(fileExists: { $0.lastPathComponent == "a.webp" }).plan(inputs: [Fixtures.makeInput(name: "a.jpg"), Fixtures.makeInput(name: "b.jpg")], settings: ExportSettings(collisionPolicy: .skip), destination: destination)
        #expect(plan.variants[0].action == .skip(.outputExists(fileName: "a.webp")))
        #expect(plan.writeCount == 1)
    }

    @Test func existingFileReplace() {
        let plan = ExportPlanner(fileExists: { $0.lastPathComponent == "a.webp" }).plan(inputs: [Fixtures.makeInput(name: "a.jpg")], settings: ExportSettings(collisionPolicy: .replace), destination: destination)
        #expect(names(plan) == ["a.webp"])
        #expect(plan.variants[0].notes == [.replacesExisting])
    }

    @Test func sourceIsNeverAPlannedOutputEvenWithReplace() {
        // Destination is the source folder, same format, same name.
        let source = URL(fileURLWithPath: "/tmp/out/photo.jpg")
        let input = Fixtures.makeInput(name: "photo.jpg", url: source)
        var settings = ExportSettings(format: .jpeg, collisionPolicy: .replace)
        settings.naming.webSafe = false
        let plan = ExportPlanner(fileExists: { $0.path == source.path }).plan(inputs: [input], settings: settings, destination: destination)
        #expect(names(plan) == ["photo-1.jpg"])
        #expect(plan.variants[0].notes == [.renamedToProtectSource(originalName: "photo.jpg")])
        #expect(plan.protectedPathKeys.contains(input.identityKey))
    }

    @Test func sourceProtectionIsCaseInsensitive() {
        let input = Fixtures.makeInput(name: "Photo.JPG", url: URL(fileURLWithPath: "/tmp/out/Photo.JPG"))
        var settings = ExportSettings(format: .jpeg, collisionPolicy: .replace)
        settings.naming.webSafe = true
        // The source exists on disk as "Photo.JPG"; web-safe naming plans "photo.jpg".
        let plan = ExportPlanner(fileExists: { $0.lastPathComponent.lowercased() == "photo.jpg" }).plan(inputs: [input], settings: settings, destination: destination)
        #expect(names(plan) == ["photo-1.jpg"])
    }

    @Test func subfolders() {
        var settings = ExportSettings(format: .avif)
        settings.resize = ResizeSettings(mode: .widths, widths: [480, 960])
        settings.subfolder = SubfolderRule(mode: .width)
        let plan = ExportPlanner(fileExists: { _ in false }).plan(inputs: [Fixtures.makeInput()], settings: settings, destination: destination)
        #expect(plan.variants.compactMap(\.destination?.path) == ["/tmp/out/480w/photo-480w.avif", "/tmp/out/960w/photo-960w.avif"])

        settings.subfolder = SubfolderRule(mode: .format)
        let byFormat = ExportPlanner(fileExists: { _ in false }).plan(inputs: [Fixtures.makeInput()], settings: settings, destination: destination)
        #expect(byFormat.variants.first?.destination?.path == "/tmp/out/avif/photo-480w.avif")

        settings.subfolder = SubfolderRule(mode: .custom, customName: "Client: Spring")
        let custom = ExportPlanner(fileExists: { _ in false }).plan(inputs: [Fixtures.makeInput()], settings: settings, destination: destination)
        #expect(custom.variants.first?.destination?.path == "/tmp/out/Client- Spring/photo-480w.avif")
    }

    @Test func restrictedPlanKeepsOnlyRequestedVariants() {
        var settings = ExportSettings()
        settings.resize = ResizeSettings(mode: .widths, widths: [480, 960])
        let plan = ExportPlanner(fileExists: { _ in false }).plan(inputs: [Fixtures.makeInput(name: "a.jpg"), Fixtures.makeInput(name: "b.jpg")], settings: settings, destination: destination)
        let keep = plan.variants[1].id
        let restricted = plan.restricted(to: [keep])
        #expect(restricted.variants.map(\.id) == [keep])
        #expect(restricted.jobs.count == 1)
        #expect(restricted.variants[0].destination == plan.variants[1].destination)
    }
}
