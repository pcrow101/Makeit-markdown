import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Finds pictures, vector drawings and charts on a PDF page and renders them
/// to PNG.
///
/// The page content stream is interpreted just far enough to learn where
/// images are drawn and where clusters of vector paths (curves, diagonal
/// strokes, bars) are painted. Nearby pieces are merged into one region, and
/// each region is rendered from the page itself so that the result matches
/// what a reader sees.
enum PDFGraphicsExtractor {

    struct Region {
        var rect: CGRect
    }

    // MARK: - Public entry points

    /// The graphic regions on `page`, ordered from top to bottom.
    static func regions(on page: PDFPage) -> [Region] {
        guard let cgPage = page.pageRef, cgPage.rotationAngle == 0 else { return [] }

        let pageRect = cgPage.getBoxRect(.cropBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return [] }

        let scan = PDFContentScan()
        scan.run(page: cgPage)

        let pageArea = pageRect.width * pageRect.height
        let pieces = scan.pieces.filter { piece in
            let rect = piece.rect.intersection(pageRect)
            guard !rect.isNull, !rect.isEmpty else { return false }
            let area = rect.width * rect.height
            switch piece.kind {
            case .image:
                return rect.width >= minimumImageSide && rect.height >= minimumImageSide
                    && area < pageArea * 0.9
            case .vector:
                // Page backgrounds and large panels are not drawings.
                return area < pageArea * 0.6
            }
        }

        var clusters = cluster(pieces)
        clusters = clusters.filter { $0.isGraphic(pageArea: pageArea) }

        return clusters
            .map { Region(rect: $0.rect.insetBy(dx: -padding, dy: -padding).intersection(pageRect)) }
            .filter { $0.rect.width >= minimumRegionSide && $0.rect.height >= minimumRegionSide }
            .sorted { $0.rect.maxY > $1.rect.maxY }
    }

    /// Renders `region` of `page` as PNG data.
    static func renderPNG(of region: Region, on page: PDFPage) -> Data? {
        guard let cgPage = page.pageRef else { return nil }

        var scale: CGFloat = 2
        let longest = max(region.rect.width, region.rect.height) * scale
        if longest > maximumPixelSide { scale *= maximumPixelSide / longest }

        let width = Int((region.rect.width * scale).rounded(.up))
        let height = Int((region.rect.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -region.rect.minX, y: -region.rect.minY)
        context.interpolationQuality = .high
        context.drawPDFPage(cgPage)

        guard let image = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // MARK: - Tuning

    private static let minimumImageSide: CGFloat = 16
    private static let minimumRegionSide: CGFloat = 40
    private static let mergeDistance: CGFloat = 4
    private static let padding: CGFloat = 4
    private static let maximumPixelSide: CGFloat = 2400

    // MARK: - Clustering

    struct Cluster {
        var rect: CGRect
        var images = 0
        var curves = 0
        var slanted = 0
        var barHeights: [Int] = []

        func isGraphic(pageArea: CGFloat) -> Bool {
            guard rect.width >= PDFGraphicsExtractor.minimumRegionSide - 2 * PDFGraphicsExtractor.padding,
                  rect.height >= PDFGraphicsExtractor.minimumRegionSide - 2 * PDFGraphicsExtractor.padding
            else { return false }
            if images > 0 { return true }
            if curves >= 8 { return true }
            if slanted >= 4 { return true }
            // Bars of differing heights read as a chart; equal heights are
            // usually table shading.
            return barHeights.count >= 4 && Set(barHeights).count >= 3
        }
    }

    private static func cluster(_ pieces: [GraphicPiece]) -> [Cluster] {
        var clusters = pieces.map { piece -> Cluster in
            Cluster(
                rect: piece.rect,
                images: piece.kind == .image ? 1 : 0,
                curves: piece.curves,
                slanted: piece.slanted,
                barHeights: piece.barHeights
            )
        }

        var merged = true
        while merged {
            merged = false
            outer: for first in clusters.indices {
                for second in clusters.indices where second > first {
                    let area = clusters[first].rect.insetBy(dx: -mergeDistance, dy: -mergeDistance)
                    if area.intersects(clusters[second].rect) {
                        let other = clusters.remove(at: second)
                        clusters[first].rect = clusters[first].rect.union(other.rect)
                        clusters[first].images += other.images
                        clusters[first].curves += other.curves
                        clusters[first].slanted += other.slanted
                        clusters[first].barHeights += other.barHeights
                        merged = true
                        break outer
                    }
                }
            }
        }
        return clusters
    }
}
