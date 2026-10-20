import AppKit
import MarkdownKit
import SwiftUI

/// Draws an image referenced from Markdown, fitted to the available width.
///
/// The image comes from the conversion's in-memory assets, so it displays
/// before anything has been saved to disk.
struct MarkdownImageView: View {

    let alt: String
    let path: String
    let assets: [ConversionAsset]

    @Environment(\.openWindow)
    private var openWindow

    private var asset: ConversionAsset? {
        let decoded = path.removingPercentEncoding ?? path
        return assets.first { $0.relativePath == path || $0.relativePath == decoded }
    }

    private var image: NSImage? {
        asset.flatMap { NSImage(data: $0.data) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // Images are rendered at a high resolution for zooming, so show
                    // them at half their pixel size here.
                    .frame(maxWidth: image.size.width / 2, alignment: .leading)
                    .accessibilityLabel(alt)
                    .help("Double-click to open in a window")
                    .onTapGesture(count: 2) {
                        openImageWindow()
                    }
            } else {
                Label("Image unavailable", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }

            if !alt.isEmpty {
                Text(alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openImageWindow() {
        guard let asset else { return }
        let title = alt.isEmpty ? (path as NSString).lastPathComponent : alt
        openWindow(value: ImageWindowValue(title: title, data: asset.data))
    }
}
