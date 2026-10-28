import PixtamerKit
import SwiftUI

/// Integer pixel field. Invalid text becomes 0 so validation can explain the problem inline.
struct PixelField: View {
    let title: String
    @Binding var value: Int
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            NumberTextField(title: title, text: $text)
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { if Int(text) != value { text = String(value) } }
        .onChange(of: text) { value = Int(text.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
}

/// Integer pixel field where empty means "no limit".
struct OptionalPixelField: View {
    let title: String
    @Binding var value: Int?
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            NumberTextField(title: title, text: $text, prompt: "No limit")
        }
        .onAppear { text = value.map(String.init) ?? "" }
        .onChange(of: value) { if Int(text) != value { text = value.map(String.init) ?? "" } }
        .onChange(of: text) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            value = trimmed.isEmpty ? nil : (Int(trimmed) ?? 0)
        }
    }
}

private struct NumberTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 84)
                .accessibilityLabel("\(title) in pixels")
            Text("px").foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

/// Editable list of responsive widths.
struct WidthsEditor: View {
    @Binding var widths: [Int]
    @State private var entry = ""
    @State private var entryError: String?

    private static let common = [320, 480, 640, 768, 960, 1024, 1280, 1440, 1600, 1920, 2560]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(widths.sorted(), id: \.self) { width in
                    HStack(spacing: 3) {
                        Text(verbatim: String(width)).monospacedDigit()
                        Button {
                            widths.removeAll { $0 == width }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove width \(width)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
            }
            HStack {
                TextField("Add width", text: $entry, prompt: Text("e.g. 1280"))
                    .onSubmit(add)
                    .accessibilityLabel("Width to add, in pixels")
                Button("Add", action: add)
                    .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                Menu("Common") {
                    ForEach(Self.common, id: \.self) { width in
                        Button("\(width) px") { insert([width]) }
                            .disabled(widths.contains(width))
                    }
                }
                .fixedSize()
            }
            if let entryError {
                Label(entryError, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func add() {
        let parts = entry.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        var values: [Int] = []
        for part in parts {
            guard let value = Int(part), (1...ResizeSettings.maxRequestedDimension).contains(value) else {
                entryError = "“\(part)” isn’t a width between 1 and \(ResizeSettings.maxRequestedDimension)."
                return
            }
            values.append(value)
        }
        insert(values)
        entry = ""
    }

    private func insert(_ values: [Int]) {
        entryError = nil
        widths = Array(Set(widths + values)).sorted()
    }
}

/// Live filename preview using the same planner as the export.
struct FilenamePreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sample = Array(model.batch.selectedOrAll.prefix(3))
        if sample.isEmpty {
            Caption("Add images to preview file names.")
        } else {
            let placeholder = URL(fileURLWithPath: "/PixtamerPreview", isDirectory: true)
            let plan = ExportPlanner(fileExists: { _ in false }).plan(inputs: sample.map(\.input), settings: model.settings, destination: placeholder)
            VStack(alignment: .leading, spacing: 3) {
                Text("Preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(plan.variants.prefix(6)) { variant in
                    if let destination = variant.destination {
                        Text(relativePath(destination, base: placeholder))
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if case .skip(let reason) = variant.action {
                        Text(reason.message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    }
                }
                if plan.variants.count > 6 {
                    Text("…").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Formatting.count(model.batch.items.count, "image")) → \(Formatting.count(model.plannedOutputCount, "file"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func relativePath(_ url: URL, base: URL) -> String {
        String(url.path.dropFirst(base.path.count + 1))
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Name entry for new and renamed presets, with inline validation.
struct PresetNameSheet: View {
    let title: String
    let actionTitle: String
    let initialName: String
    let validate: (String) -> PresetNameError?
    let commit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        let error = validate(name)
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit { if error == nil { commit(name); dismiss() } }
            if let error, !name.isEmpty {
                Label(error.message, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle) {
                    commit(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(error != nil)
            }
        }
        .padding(20)
        .onAppear { name = initialName }
    }
}
