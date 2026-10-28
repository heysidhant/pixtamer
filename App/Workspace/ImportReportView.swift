import PixtamerKit
import SwiftUI

/// Explains which files were not added and why. Shown only when something was rejected.
struct ImportReportView: View {
    let report: ImportReport
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            List(report.rejected) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName).lineLimit(1).truncationMode(.middle)
                    Text(file.reason.message).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(minHeight: 160)
            .listStyle(.bordered)

            HStack {
                Button("Copy List") {
                    let text = report.rejected.map { "\($0.fileName): \($0.reason.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button("OK", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }

    private var headline: String {
        let rejected = Formatting.count(report.rejected.count, "file")
        return report.added.isEmpty ? "\(rejected) couldn’t be added" : "Added \(Formatting.count(report.added.count, "image")). \(rejected) couldn’t be added."
    }

    private var detail: String {
        var parts = ["The files below were skipped. Nothing on disk was changed."]
        if report.duplicateCount > 0 { parts.append("\(Formatting.count(report.duplicateCount, "file")) already in the queue.") }
        if report.ignoredNonImageCount > 0 { parts.append("\(Formatting.count(report.ignoredNonImageCount, "non-image file")) ignored.") }
        return parts.joined(separator: " ")
    }
}
