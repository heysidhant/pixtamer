import SwiftUI

/// Screen A: first launch and empty queue.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    let isDropTargeted: Bool

    var body: some View {
        // Scroll view + GeometryReader keep this view's size out of the window's minimum-size
        // calculation. Without it, wrapping text here fed back into the window size and sent
        // AppKit into a constraint-update loop (reproduced as a launch crash).
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("Pixtamer")
                    .font(.largeTitle.weight(.semibold))
                Text("Convert, compress, resize and rename hundreds of images in one batch.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }

            VStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                Text("Drop images or folders here")
                    .font(.headline)
                HStack(spacing: 12) {
                    Button {
                        model.addFilesWithPanel()
                    } label: {
                        Label("Add Images…", systemImage: "photo.badge.plus")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        model.addFolderWithPanel()
                    } label: {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                            .frame(minWidth: 130)
                    }
                    .controlSize(.large)
                }
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 20)
            .frame(maxWidth: 520)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 1.5, dash: isDropTargeted ? [] : [7, 5]))
                    .background(RoundedRectangle(cornerRadius: 14).fill(isDropTargeted ? Color.accentColor.opacity(0.06) : .clear))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Drop zone. Drop images or folders, or use the Add buttons.")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) { benefits }
                VStack(alignment: .leading, spacing: 14) { benefits }
            }

            Label("Your images are processed on this Mac. No account, no upload.", systemImage: "desktopcomputer")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    @ViewBuilder
    private var benefits: some View {
        Benefit(symbol: "arrow.down.right.and.arrow.up.left", title: "Responsive sizes", detail: "One source, every width you need, named consistently.")
        Benefit(symbol: "slider.horizontal.3", title: "Reusable presets", detail: "Save a recipe once and apply it to the next batch.")
        Benefit(symbol: "lock.shield", title: "Safe and local", detail: "Originals are never changed. Nothing is uploaded.")
    }
}

private struct Benefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 180, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
