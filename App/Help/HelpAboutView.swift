import PixtamerKit
import SwiftUI

/// Screen I: version, formats, shortcuts, limitations, privacy and diagnostics.
struct HelpAboutView: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    private static let shortcuts: [(String, String)] = [
        ("⌘O", "Add images"),
        ("⇧⌘O", "Add folder"),
        ("⌘E", "Start export"),
        ("⌘Y or Space", "Preview selected image"),
        ("← →", "Previous / next image in preview"),
        ("Delete or ⌘⌫", "Remove selected images from the queue"),
        ("⇧⌘⌫", "Clear queue"),
        ("⇧⌘D", "Choose export folder"),
        ("⌥⌘I", "Show or hide export settings"),
        ("⌘1 – ⌘4", "Batch, Presets, Recent Exports, Settings"),
        ("⌘,", "Settings window"),
    ]

    private static let limitations = [
        "WebP export removes all metadata and converts colours to sRGB (the bundled encoder cannot embed profiles).",
        "AVIF export appears only when this Mac’s system encoder passes a test at launch.",
        "Animated GIFs: only the first frame is exported. RAW, PSD, PDF and HDR workflows are not supported.",
        "16-bit and HDR images are exported as 8-bit.",
        "PNG output is lossless; it does not reduce colours, so photos saved as PNG are often larger.",
        "Truncated JPEG/PNG files can still decode with grey areas. Pixtamer warns when a file looks incomplete.",
        "Pause is not available; Cancel finishes or discards in-progress files safely.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pixtamer").font(.title.weight(.semibold))
                        Text("Version \(model.appVersion) (\(model.appBuild))").foregroundStyle(.secondary)
                        Text("Batch image optimisation for the web.").foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Link("Source Code (MIT)", destination: URL(string: "https://github.com/heysidhant/pixtamer")!)
                            if let notices = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") {
                                Button("Third-Party Notices") { NSWorkspace.shared.open(notices) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }

                HelpSection(title: "Privacy") {
                    Text("Images are processed on this Mac. Pixtamer has no account, no analytics and no network access (the app is sandboxed without the network entitlement; links open in your browser). It can only read files you add and write to the folder you choose. Originals are never modified.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                HelpSection(title: "More from the Maker") {
                    Text("Pixtamer is free and open source. For video, audio, PDFs and on-device AI as well as images, try MightyBench: 49 private tools in one Mac app.")
                        .fixedSize(horizontal: false, vertical: true)
                    Link("mightybench.com", destination: URL(string: "https://mightybench.com/?ref=pixtamer")!)
                }

                HelpSection(title: "Formats on This Mac") {
                    if let capabilities = model.capabilities {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                            ForEach(capabilities.probes, id: \.format) { probe in
                                GridRow {
                                    Image(systemName: probe.available ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundStyle(probe.available ? .green : .secondary)
                                        .accessibilityLabel(probe.available ? "Available" : "Unavailable")
                                    Text(probe.format.displayName).fontWeight(.medium)
                                    Text(probe.encoderName).foregroundStyle(.secondary)
                                    Text(probe.available ? "Export available" : probe.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("Input: " + capabilities.readableTypeIdentifiers.compactMap { FormatCapabilities.supportedInputTypes[$0] }.sorted().joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }

                HelpSection(title: "Keyboard Shortcuts") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                        ForEach(Self.shortcuts, id: \.0) { shortcut in
                            GridRow {
                                Text(shortcut.0).font(.body.monospaced()).foregroundStyle(.secondary)
                                Text(shortcut.1)
                            }
                        }
                    }
                }

                HelpSection(title: "Known Limitations") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.limitations, id: \.self) { item in
                            Label(item, systemImage: "minus").labelStyle(BulletLabelStyle())
                        }
                    }
                }

                HelpSection(title: "Diagnostics") {
                    Text("Copy this into a bug report. It lists versions, format support and error codes. It contains no images and no full file paths.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.diagnosticsReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                    HStack {
                        Button(copied ? "Copied" : "Copy Diagnostics") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.diagnosticsReport, forType: .string)
                            copied = true
                        }
                        Spacer()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Pixtamer Help")
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}
