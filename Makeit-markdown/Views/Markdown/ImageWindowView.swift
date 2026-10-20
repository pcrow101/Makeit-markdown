import AppKit
import SwiftUI

/// What an image window shows.
///
/// Window values must be `Codable` and `Hashable`, so the image travels as its
/// encoded bytes. Opening the same image twice focuses the existing window.
struct ImageWindowValue: Codable, Hashable {
    var title: String
    var data: Data
}

/// The zoom level of an image window, as a multiple of the fit-to-window size.
enum ImageZoom {

    /// 1 shows the whole image; larger values enlarge it.
    static let range: ClosedRange<CGFloat> = 1...16

    /// The factor applied by each zoom in or out step.
    static let step: CGFloat = 1.5

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, range.lowerBound), range.upperBound)
    }

    static func zoomedIn(_ zoom: CGFloat) -> CGFloat { clamped(zoom * step) }

    static func zoomedOut(_ zoom: CGFloat) -> CGFloat { clamped(zoom / step) }
}

/// A resizable window that shows one image, fitted to the window by default
/// and zoomable with buttons, keyboard shortcuts or a pinch gesture.
struct ImageWindowView: View {

    let value: ImageWindowValue?

    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat = 1

    private var image: NSImage? {
        value.flatMap { NSImage(data: $0.data) }
    }

    var body: some View {
        Group {
            if let image {
                viewer(for: image)
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo")
            }
        }
        .frame(minWidth: 240, minHeight: 180)
        .navigationTitle(value?.title ?? "Image")
    }

    private func viewer(for image: NSImage) -> some View {
        GeometryReader { proxy in
            let fit = fitSize(of: image, in: proxy.size)

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: fit.width * zoom, height: fit.height * zoom)
                    // Centre the image while it is smaller than the window.
                    .frame(
                        minWidth: proxy.size.width,
                        minHeight: proxy.size.height
                    )
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { gesture in
                        zoom = ImageZoom.clamped(gestureStartZoom * gesture.magnification)
                    }
                    .onEnded { _ in
                        gestureStartZoom = zoom
                    }
            )
            .toolbar {
                zoomControls(actualSize: actualSizeZoom(of: image, fit: fit))
            }
        }
    }

    @ToolbarContentBuilder
    private func zoomControls(actualSize: CGFloat) -> some ToolbarContent {
        ToolbarItemGroup {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                setZoom(ImageZoom.zoomedOut(zoom))
            }
            .keyboardShortcut("-")
            .disabled(zoom <= ImageZoom.range.lowerBound)

            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                setZoom(ImageZoom.zoomedIn(zoom))
            }
            .keyboardShortcut("+")
            .disabled(zoom >= ImageZoom.range.upperBound)

            Button("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
                setZoom(1)
            }
            .keyboardShortcut("0")

            Button("Actual Size", systemImage: "1.magnifyingglass") {
                setZoom(ImageZoom.clamped(actualSize))
            }
            .keyboardShortcut("1")
        }
    }

    private func setZoom(_ newValue: CGFloat) {
        zoom = newValue
        gestureStartZoom = newValue
    }

    /// The largest size at which the whole image fits `container`.
    private func fitSize(of image: NSImage, in container: CGSize) -> CGSize {
        let available = CGSize(
            width: max(container.width, 1),
            height: max(container.height, 1)
        )
        guard image.size.width > 0, image.size.height > 0 else { return available }

        let ratio = min(
            available.width / image.size.width,
            available.height / image.size.height
        )
        return CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    }

    /// The zoom at which the image is drawn at its own pixel size.
    private func actualSizeZoom(of image: NSImage, fit: CGSize) -> CGFloat {
        guard fit.width > 0 else { return 1 }
        return image.size.width / fit.width
    }
}
