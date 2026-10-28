import Foundation

/// Resolves every output name and path for a batch before processing starts, applying the
/// collision policy deterministically. Pure apart from the injected `fileExists` check.
public struct ExportPlanner: Sendable {
    public typealias FileExists = @Sendable (URL) -> Bool

    public static let defaultFileExists: FileExists = { FileManager.default.fileExists(atPath: $0.path) }

    let fileExists: FileExists

    public init(fileExists: @escaping FileExists = ExportPlanner.defaultFileExists) {
        self.fileExists = fileExists
    }

    public func plan(inputs: [ImageInput], settings: ExportSettings, destination: URL) -> ExportPlan {
        let protected = Set(inputs.map(\.identityKey))
        var reserved = Set<String>()
        let multipleWidths = settings.resize.mode == .widths

        let jobs = inputs.enumerated().map { offset, input -> PlannedJob in
            let decisions = ResizePlanner.variants(for: input.pixelSize, settings: settings.resize)
            let variants = decisions.map { decision -> PlannedVariant in
                switch decision {
                case .skip(let reason):
                    let label = Self.skipLabel(reason)
                    return PlannedVariant(inputID: input.id, label: label, action: .skip(reason))
                case .render(let plan):
                    let label = plan.requestedWidth.map { "\($0)w" } ?? plan.outputSize.description
                    let context = FilenameContext(
                        name: input.baseName,
                        width: plan.outputSize.width,
                        height: plan.outputSize.height,
                        format: settings.format,
                        index: offset + 1,
                        total: inputs.count
                    )
                    let fileName = FilenameRenderer.fileName(rule: settings.naming, context: context, multipleWidths: multipleWidths)
                    var directory = destination
                    if let sub = SubfolderResolver.component(rule: settings.subfolder, format: settings.format, outputWidth: plan.outputSize.width) {
                        directory = directory.appendingPathComponent(sub, isDirectory: true)
                    }
                    return resolve(
                        fileName: fileName,
                        directory: directory,
                        inputID: input.id,
                        label: label,
                        plan: plan,
                        policy: settings.collisionPolicy,
                        protected: protected,
                        reserved: &reserved
                    )
                }
            }
            return PlannedJob(input: input, variants: variants)
        }
        return ExportPlan(destination: destination, settings: settings, jobs: jobs, protectedPathKeys: protected)
    }

    private func resolve(
        fileName: String,
        directory: URL,
        inputID: UUID,
        label: String,
        plan: VariantPlan,
        policy: CollisionPolicy,
        protected: Set<String>,
        reserved: inout Set<String>
    ) -> PlannedVariant {
        let candidate = directory.appendingPathComponent(fileName, isDirectory: false)
        let key = PathKey.make(candidate)
        var notes: [PlanNote] = []

        // Collisions inside the batch and with sources always rename, whatever the policy:
        // replacing either would destroy data the user did not ask to replace.
        let forcedRenameNote: PlanNote? = if reserved.contains(key) {
            .renamedDuplicateInBatch(originalName: fileName)
        } else if protected.contains(key) {
            .renamedToProtectSource(originalName: fileName)
        } else {
            nil
        }

        if let note = forcedRenameNote {
            notes.append(note)
            let url = nextAvailable(after: candidate, protected: protected, reserved: reserved)
            reserved.insert(PathKey.make(url))
            return PlannedVariant(inputID: inputID, label: label, action: .write(plan, destination: url), notes: notes)
        }

        if fileExists(candidate) {
            switch policy {
            case .rename:
                notes.append(.renamedExisting(originalName: fileName))
                let url = nextAvailable(after: candidate, protected: protected, reserved: reserved)
                reserved.insert(PathKey.make(url))
                return PlannedVariant(inputID: inputID, label: label, action: .write(plan, destination: url), notes: notes)
            case .skip:
                return PlannedVariant(inputID: inputID, label: label, action: .skip(.outputExists(fileName: fileName)))
            case .replace:
                notes.append(.replacesExisting)
            }
        }
        reserved.insert(key)
        return PlannedVariant(inputID: inputID, label: label, action: .write(plan, destination: candidate), notes: notes)
    }

    /// `photo.webp` → `photo-1.webp`, `photo-2.webp`, … skipping names that exist, are sources,
    /// or are already reserved by this batch.
    func nextAvailable(after url: URL, protected: Set<String>, reserved: Set<String>) -> URL {
        NumberedName.next(after: url) { candidate in
            let key = PathKey.make(candidate)
            return !reserved.contains(key) && !protected.contains(key) && !fileExists(candidate)
        }
    }

    static func skipLabel(_ reason: SkipReason) -> String {
        switch reason {
        case .wouldUpscale(let width, _): "\(width)w"
        case .sourceSmallerThanTarget(_, let target): target.description
        case .outputExists(let name): name
        }
    }
}

enum NumberedName {
    static let maxAttempts = 9_999

    static func next(after url: URL, isAvailable: (URL) -> Bool) -> URL {
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        for counter in 1...maxAttempts {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            let candidate = directory.appendingPathComponent(name, isDirectory: false)
            if isAvailable(candidate) { return candidate }
        }
        // Pathological folder with thousands of numbered copies: fall back to a unique token.
        let token = UUID().uuidString.prefix(8).lowercased()
        return directory.appendingPathComponent(ext.isEmpty ? "\(base)-\(token)" : "\(base)-\(token).\(ext)", isDirectory: false)
    }
}
