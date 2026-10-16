import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Generates PDF fixtures on disk at test time.
///
/// Fixtures are produced programmatically rather than committed as binaries so
/// that the repository stays free of opaque test data and so the typographic
/// properties the converter keys off are explicit in the test itself.
enum PDFFixture {

    /// A line of text to draw, with the styling the analyser inspects.
    struct Line {
        var text: String
        var fontSize: Double
        var isBold: Bool
        var indent: Double

        init(_ text: String, fontSize: Double = 12, isBold: Bool = false, indent: Double = 0) {
            self.text = text
            self.fontSize = fontSize
            self.isBold = isBold
            self.indent = indent
        }
    }

    /// A temporary directory that is removed when the handle is released.
    final class Scratch {
        let directory: URL

        init() throws {
            directory = URL(filePath: NSTemporaryDirectory())
                .appending(path: "MarkdownKitTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: Double = 54
    private static let lineSpacing: Double = 8

    /// Rows are spaced more widely than the lines inside a cell, which is how
    /// the scanner tells a new row from a wrapped cell.
    private static let rowSpacing: Double = 18

    /// Writes a PDF containing `pages` and returns its location.
    ///
    /// - Parameters:
    ///   - pages: The lines to draw, grouped by page.
    ///   - name: The base file name, without an extension.
    ///   - directory: The directory to write into.
    @discardableResult
    static func write(pages: [[Line]], named name: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: "\(name).pdf")
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FixtureError.couldNotCreateContext
        }

        for page in pages {
            context.beginPDFPage(nil)
            draw(lines: page, in: context)
            context.endPDFPage()
        }

        context.closePDF()
        return url
    }

    /// Writes a single page PDF.
    @discardableResult
    static func write(lines: [Line], named name: String, in directory: URL) throws -> URL {
        try write(pages: [lines], named: name, in: directory)
    }

    /// Writes a PDF with one empty page, standing in for a scanned document.
    @discardableResult
    static func writeBlank(named name: String, in directory: URL) throws -> URL {
        try write(pages: [[]], named: name, in: directory)
    }

    /// Writes a PDF laying `rows` out as a grid of cells.
    ///
    /// Cells are drawn on a shared baseline at fixed column positions, which is
    /// the geometry the scanner relies on to recognise a table. Rows are spaced
    /// further apart than the lines within a cell so that row breaks are
    /// detectable.
    ///
    /// - Parameters:
    ///   - rows: The cell text, row by row.
    ///   - columnWidth: The horizontal distance between column origins.
    ///   - fontSize: The size to draw every cell at.
    @discardableResult
    static func write(
        tableRows rows: [[String]],
        columnWidth: Double = 110,
        fontSize: Double = 10,
        named name: String,
        in directory: URL
    ) throws -> URL {
        let url = directory.appending(path: "\(name).pdf")
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FixtureError.couldNotCreateContext
        }

        let font = NSFont(name: "Helvetica", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        context.beginPDFPage(nil)
        var cursorY = pageSize.height - margin

        for row in rows {
            cursorY -= fontSize + rowSpacing
            for (column, text) in row.enumerated() where !text.isEmpty {
                let attributed = NSAttributedString(string: text, attributes: [.font: font])
                context.textPosition = CGPoint(
                    x: margin + Double(column) * columnWidth,
                    y: cursorY
                )
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }

        context.endPDFPage()
        context.closePDF()
        return url
    }

    private static func draw(lines: [Line], in context: CGContext) {
        var cursorY = pageSize.height - margin

        for line in lines {
            // A document face is used in preference to the system UI font, which
            // cannot be embedded in a PDF and triggers CoreText substitution.
            let name = line.isBold ? "Helvetica-Bold" : "Helvetica"
            let font = NSFont(name: name, size: line.fontSize)
                ?? NSFont.userFont(ofSize: line.fontSize)
                ?? NSFont.systemFont(ofSize: line.fontSize)

            let attributed = NSAttributedString(
                string: line.text,
                attributes: [.font: font]
            )

            cursorY -= line.fontSize + lineSpacing
            context.textPosition = CGPoint(x: margin + line.indent, y: cursorY)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
    }

    enum FixtureError: Error {
        case couldNotCreateContext
    }
}
