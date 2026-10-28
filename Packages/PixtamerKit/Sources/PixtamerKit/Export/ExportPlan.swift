import Foundation

public enum PlanNote: Hashable, Sendable {
    /// A file with the planned name already existed; a number was added.
    case renamedExisting(originalName: String)
    /// Another output in this batch already uses the name.
    case renamedDuplicateInBatch(originalName: String)
    /// The planned output path is one of the source images.
    case renamedToProtectSource(originalName: String)
    /// Collision policy is Replace and the file exists.
    case replacesExisting

    public var message: String {
        switch self {
        case .renamedExisting(let name): "\(name) already existed, so a number was added."
        case .renamedDuplicateInBatch(let name): "Another image in this batch also produces \(name), so a number was added."
        case .renamedToProtectSource(let name): "\(name) is a source image, so a number was added to avoid replacing it."
        case .replacesExisting: "Replaces an existing file."
        }
    }
}

/// One output file the export will try to produce (or deliberately skip).
public struct PlannedVariant: Identifiable, Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        case write(VariantPlan, destination: URL)
        case skip(SkipReason)
    }

    public let id: UUID
    public let inputID: UUID
    /// Human label such as "960w" or "1600×1067".
    public let label: String
    public let action: Action
    public let notes: [PlanNote]

    public init(id: UUID = UUID(), inputID: UUID, label: String, action: Action, notes: [PlanNote] = []) {
        self.id = id
        self.inputID = inputID
        self.label = label
        self.action = action
        self.notes = notes
    }

    public var destination: URL? {
        if case .write(_, let url) = action { return url }
        return nil
    }

    public var plannedFileName: String? { destination?.lastPathComponent }
}

/// All planned outputs for one source image.
public struct PlannedJob: Identifiable, Hashable, Sendable {
    public var id: UUID { input.id }
    public let input: ImageInput
    public let variants: [PlannedVariant]
}

/// A fully resolved export: every output path is decided before any pixels are processed.
public struct ExportPlan: Hashable, Sendable {
    public let destination: URL
    public let settings: ExportSettings
    public let jobs: [PlannedJob]
    /// Path keys of every source image. The writer refuses to finalise onto these.
    public let protectedPathKeys: Set<String>

    public var variants: [PlannedVariant] { jobs.flatMap(\.variants) }
    public var writeCount: Int { variants.filter { $0.destination != nil }.count }
    public var plannedSkipCount: Int { variants.count - writeCount }

    /// Restricts the plan to the given variant IDs (used by Retry Failed).
    public func restricted(to variantIDs: Set<UUID>) -> ExportPlan {
        let filtered = jobs.compactMap { job -> PlannedJob? in
            let kept = job.variants.filter { variantIDs.contains($0.id) }
            return kept.isEmpty ? nil : PlannedJob(input: job.input, variants: kept)
        }
        return ExportPlan(destination: destination, settings: settings, jobs: filtered, protectedPathKeys: protectedPathKeys)
    }
}
